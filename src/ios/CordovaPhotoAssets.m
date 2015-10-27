#import <Cordova/CDV.h>
#import "CordovaPhotoAssets.h"
#import <Photos/Photos.h>
#import <pthread.h>

NSString *allImageAssetsCollectionKey = @"all";
NSString *localStorageSubdir = @"CordovaPhotoAssets";
pthread_mutex_t cordovaPhotoAssetsSingletonMutex;

// Very helpful starting place:
// http://stackoverflow.com/questions/25981374/ios-8-photos-framework-get-a-list-of-all-albums-with-ios8

@interface CordovaPhotoAssets () <PHPhotoLibraryChangeObserver>
@property NSString *localStoragePath;
@property PHImageManager *imageManager;
@property NSMutableDictionary *subscriptions;
@end


@implementation CordovaPhotoAssets

- (void)pluginInitialize {
    NSLog(@"CordovaPhotoAssets initializing...");

    pthread_mutex_init(&cordovaPhotoAssetsSingletonMutex, NULL);

    self.imageManager = [PHImageManager defaultManager];
    self.subscriptions = [NSMutableDictionary new];

    [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self]; //(id<PHPhotoLibraryChangeObserver>)
    [self _initLocalStoragePath];

    NSLog(@"CordovaPhotoAssets initialized.");
    //TODO: make a subdirectory and delete all files in it here, on init
}

- (void)getCollections:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        // NOTE: no need to lock - _enumerateCollections doesn't access the plugin's singleton at all

        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray: _enumerateCollections()];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];

    }];

}

void _validateNumberOption
(
 NSMutableArray *errorsOut,
 NSDictionary *options,
 NSString *key,
 NSInteger minValue,
 NSInteger maxValue
 )
{
    NSNumber *nsNumber;
    if ((nsNumber = [options objectForKey:key])) {
        if ([nsNumber isKindOfClass:[NSNumber class]]) {
            NSInteger value = nsNumber.integerValue;
            if (value < minValue || value > maxValue) {
                [errorsOut addObject:[NSString
                                      stringWithFormat:@"Invalid value for %@: %ld. Expected integer in the range [%ld, %ld].",
                                      key,
                                      (long)value,
                                      (long)minValue,
                                      (long)maxValue
                                      ]];
            }
        }
        else [errorsOut addObject:[NSString stringWithFormat:@"Invalid value for %@. Expected a number.", key]];
    }
}

void _validateStringOption
(
 NSMutableArray *errorsOut,
 NSDictionary *options,
 NSString *key
 )
{
    NSString *nsString;
    if ((nsString = [options objectForKey:key])) {
        if (![nsString isKindOfClass:[NSString class]])
            [errorsOut addObject:[NSString stringWithFormat:@"Invalid value for %@. Expected a string.", key]];
    }
}

//////////////////////////
// Extract Options
//////////////////////////

NSUInteger defaultQuality = 95;
NSUInteger defaultMaxSize = 0; // 0 == no max size
NSUInteger defaultLimit = 3;
NSUInteger defaultOffset = 0;

NSString *getCollectionKeyFromDictionary(NSDictionary *dictionary) {
    NSString *value = [dictionary objectForKey:@"collectionKey"];
    if (!value) value = allImageAssetsCollectionKey;
    return value;
}

NSString *getSubscriptionHandleFromDictionary(NSDictionary *dictionary) {
    return [dictionary objectForKey:@"subscriptionHandle"];
}

NSUInteger getQualityFromDictionary(NSDictionary *dictionary) {
    NSNumber *nsNumber;
    NSUInteger value = defaultQuality;

    if ((nsNumber = [dictionary objectForKey:@"quality"])) {
        value = nsNumber.unsignedIntegerValue;
        if (value > 100) value = 100;
    }
    return value;
}

NSUInteger getMaxSizeFromDictionary(NSDictionary *dictionary) {
    NSNumber *nsNumber;
    NSUInteger value = defaultMaxSize;

    if ((nsNumber = [dictionary objectForKey:@"maxSize"])) {
        value = nsNumber.unsignedIntegerValue;
    }
    return value;
}

NSUInteger getOffsetFromDictionary(NSDictionary *dictionary) {
    NSNumber *nsNumber;
    NSUInteger value = defaultOffset;

    if ((nsNumber = [dictionary objectForKey:@"offset"])) {
        value = nsNumber.unsignedIntegerValue;
    }
    return value;
}

NSUInteger getLimitFromDictionary(NSDictionary *dictionary) {
    NSNumber *nsNumber;
    NSUInteger value = defaultLimit;

    if ((nsNumber = [dictionary objectForKey:@"limit"])) {
        value = nsNumber.unsignedIntegerValue;
    }
    return value;
}

void setCollectionKeyInDictionary   (NSMutableDictionary *dictionary, NSString  *value) {[dictionary setObject:value                                        forKey:@"collectionKey"];}
void setLimitInDictionary           (NSMutableDictionary *dictionary, NSUInteger value) {[dictionary setObject:[NSNumber numberWithUnsignedInteger: value]  forKey:@"limit"];}
void setOffsetInDictionary          (NSMutableDictionary *dictionary, NSUInteger value) {[dictionary setObject:[NSNumber numberWithUnsignedInteger: value]  forKey:@"offset"];}
void setMaxSizeInDictionary         (NSMutableDictionary *dictionary, NSUInteger value) {[dictionary setObject:[NSNumber numberWithUnsignedInteger: value]  forKey:@"maxSize"];}
void setQualityInDictionary         (NSMutableDictionary *dictionary, NSUInteger value) {[dictionary setObject:[NSNumber numberWithUnsignedInteger: value]  forKey:@"quality"];}

NSMutableDictionary *newSubscription(NSDictionary *options) {
    NSMutableDictionary *subscription = [NSMutableDictionary new];

    [subscription setObject:getSubscriptionHandleFromDictionary(options) forKey:@"subscriptionHandle"];
    setCollectionKeyInDictionary    (subscription, getCollectionKeyFromDictionary   (options));
    setLimitInDictionary            (subscription, getLimitFromDictionary           (options));
    setOffsetInDictionary           (subscription, getOffsetFromDictionary          (options));
    setMaxSizeInDictionary          (subscription, getMaxSizeFromDictionary         (options));
    setQualityInDictionary          (subscription, getQualityFromDictionary         (options));
    [subscription setObject:[NSNumber numberWithInteger:0] forKey:@"estimatedAssetCount"];

    [subscription setObject:[NSMutableArray new] forKey:@"assetsInWindow"];
    [subscription setObject:[NSMutableDictionary new] forKey:@"assetsInWindowByKey"];
    [subscription setObject:[NSMutableDictionary new] forKey:@"outputAssetsInWindowByKey"];


    return subscription;
}

//////////////////////////
// Subscriptions
//////////////////////////
- (void)subscribe:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        NSDictionary* options = [[command arguments] objectAtIndex:0];
        CDVPluginResult* pluginResult = nil;

        NSString *subscriptionHandle = [options objectForKey:@"subscriptionHandle"];
        NSMutableDictionary *subscription = nil;

        pthread_mutex_lock(&cordovaPhotoAssetsSingletonMutex);

        if (!subscriptionHandle || subscriptionHandle.length==0) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"missing or blank subscription 'subscriptionHandle' option"];
        } else if ((subscription = [self.subscriptions objectForKey:subscriptionHandle])) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"subscription with subscriptionHandle '%@' already exists", subscriptionHandle]];
        } else {
            subscription = newSubscription(options);
            [self.subscriptions setObject:subscription forKey:subscriptionHandle];
            [self _updateSubscription: subscription];
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        }

        pthread_mutex_unlock(&cordovaPhotoAssetsSingletonMutex);

        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (void)updateSubscriptionWindow:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        NSDictionary* options = [[command arguments] objectAtIndex:0];
        CDVPluginResult* pluginResult = nil;

        NSString *subscriptionHandle = getSubscriptionHandleFromDictionary(options);
        NSMutableDictionary *subscription = nil;

        pthread_mutex_lock(&cordovaPhotoAssetsSingletonMutex);

        if (!subscriptionHandle || subscriptionHandle.length==0) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"missing or blank subscription 'subscriptionHandle' option"];
        } else if (!(subscription = [self.subscriptions objectForKey:subscriptionHandle])) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"subscription not found for subscriptionHandle: '%@'", subscriptionHandle]];
        } else {

            setLimitInDictionary(subscription, getLimitFromDictionary(options));
            setOffsetInDictionary(subscription, getOffsetFromDictionary(options));

            [self _updateSubscription: subscription];
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        }

        pthread_mutex_unlock(&cordovaPhotoAssetsSingletonMutex);

        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (void)unsubscribe:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        NSDictionary* options = [[command arguments] objectAtIndex:0];
        CDVPluginResult* pluginResult = nil;

        NSString *subscriptionHandle = [options objectForKey:@"subscriptionHandle"];

        pthread_mutex_lock(&cordovaPhotoAssetsSingletonMutex);

        if (!subscriptionHandle || subscriptionHandle.length==0) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"missing or blank subscription 'subscriptionHandle' option"];
        } else {
            NSMutableDictionary *subscription = [self.subscriptions objectForKey:subscriptionHandle];
            if (!subscription) {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"subscription not found for subscriptionHandle: '%@'", subscriptionHandle]];
            } else {

                [self _deleteImageFilesForAssets:[subscription objectForKey:@"assetsInWindowByKey"] forSubscription:subscription];
                [self.subscriptions removeObjectForKey:subscriptionHandle];
            }
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        }

        pthread_mutex_unlock(&cordovaPhotoAssetsSingletonMutex);

        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

//////////////////////////
//////////////////////////


// NOTE: we can get all the EXIF data if we fetch the full-sized image.
// The returned CIImage has a properties field with this data.
// http://stackoverflow.com/questions/24462112/ios-8-photos-framework-access-photo-metadata
- (void)getPhoto:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        NSDictionary* options = [[command arguments] objectAtIndex:0];
        CDVPluginResult* pluginResult = nil;

        NSString *assetKey = [options objectForKey:@"assetKey"];

        NSInteger maxSize = getMaxSizeFromDictionary(options);
        NSInteger quality = getQualityFromDictionary(options);

        PHAsset *asset = assetFromKey(assetKey);

        if (!asset) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"asset not found for assetKey: %@", assetKey]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        } else {
            CGSize size = PHImageManagerMaximumSize;
            if (maxSize > 0) {
                size.height = size.width = maxSize;
            }
            NSMutableDictionary *fetchedProps = [self _fetchAsset:asset targetSize:size withQuality:quality forGroup:@"fullSizedPhotos"];

            if (fetchedProps)
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:fetchedProps];
            else
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"failed to load asset for assetKey: %@ and width %d and heigh %d", assetKey, (int)size.width, (int)size.height]];
        }

        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

PHAsset *assetFromKey(NSString *assetKey) {
    PHFetchResult *allPhotosResult = [PHAsset fetchAssetsWithLocalIdentifiers:[NSArray arrayWithObject:assetKey] options:nil];

    if (allPhotosResult.count < 1) {
        NSLog(@"assetFromKey: asset not found for %@", assetKey);
        return nil;
    }

    return (PHAsset *)[allPhotosResult objectAtIndex:0];
}


/**************************************************
 INTERFACE IMPLEMENTATIONS
 **************************************************/

// implement PHPhotoLibraryChangeObserver
- (void)photoLibraryDidChange:(PHChange *)changeInfo {
//    NSLog(@"photoLibraryDidChange");
    [self.commandDelegate runInBackground:^{
        pthread_mutex_lock(&cordovaPhotoAssetsSingletonMutex);
        [self _updateAllSubscriptions];
        [self _sendUpdateEventForCollections];
        pthread_mutex_unlock(&cordovaPhotoAssetsSingletonMutex);
    }];
}

/**************************************************
 PRIVATE
 **************************************************/

- (void)_deleteAllFilesInLocalStorage {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator *dirEnum = [fileManager enumeratorAtPath:self.localStoragePath];

    NSLog(@"cleaning up all files in localStoragePath: %@", self.localStoragePath);
    NSString *file;
    NSString *filePath;
    NSError *err = nil;
    while ((file = [dirEnum nextObject])) {
        filePath = [NSString stringWithFormat:@"%@/%@", self.localStoragePath, file];
        NSLog(@"deleting: %@", file);
        if (![fileManager removeItemAtPath:filePath error:&err]) {
            NSLog(@"Error removing temporary file: %@. Error: %@", file, [err localizedDescription]);
        }
    }
}

- (void)_initLocalStoragePath {
    self.localStoragePath = [[NSString stringWithFormat:@"%@/%@", NSTemporaryDirectory(), localStorageSubdir] stringByStandardizingPath];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDir = false;
    if ([fileManager fileExistsAtPath:self.localStoragePath isDirectory:&isDir] && isDir) {
        NSLog(@"localStoragePath already exists: %@", self.localStoragePath);
        [self _deleteAllFilesInLocalStorage];
        return;
    }

    NSLog(@"creating localStoragePath: %@", self.localStoragePath);
    NSError *err = nil;
    if (![fileManager
          createDirectoryAtPath: self.localStoragePath
          withIntermediateDirectories: YES
          attributes: nil
          error: &err]) {
        NSLog(@"Error creating localStoragePath: %@. Error: %@", self.localStoragePath, [err localizedDescription]);
        return;
    }
}

- (void)_dispatchEventType:(NSString *)eventType withDetails:(id) details {
    if (![NSJSONSerialization isValidJSONObject: details]) {
        NSLog(@"CordovaPhotoAssets DispatchEvent '%@': INVALID VALUE for 'details'. Not NSJSONSerialization compatible.", eventType);
        return;
    }

    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject: details options: 0 error: &error];

    if (!jsonData) {
        NSLog(@"CordovaPhotoAssets DispatchEvent '%@': INTERNAL ERROR converting 'details' to json: %@", eventType, [error localizedDescription]);
        return;
    }

    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    //    NSLog(@"CordovaPhotoAssets DispatchEvent '%@': jsonString: %@", eventType, jsonString);

    NSString *javascript = [NSString stringWithFormat:@"document.dispatchEvent(new CustomEvent('%@', {detail:%@}));", eventType, jsonString];
    //    NSLog(@"CordovaPhotoAssets DispatchEvent '%@': invoking javascript: %@", eventType, javascript);

    [self.commandDelegate evalJs: javascript scheduledOnRunLoop: true];
}

NSMutableDictionary *assetsToAssetsByKey(NSArray *assets) {
    NSMutableDictionary *assetsByKey = [NSMutableDictionary new];
    [assets enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger idx, BOOL *stop) {
        [assetsByKey setObject:asset forKey:asset.localIdentifier];
    }];
    return assetsByKey;
}

- (NSMutableArray *)_getOutputAssetArrayForSubscription:(NSMutableDictionary*)subscription {
    NSMutableArray *result = [NSMutableArray new];
    NSMutableArray *assetKeysInWindow = [subscription objectForKey:@"assetKeysInWindow"];
    NSMutableDictionary *assetsInWindowByKey = [subscription objectForKey:@"assetsInWindowByKey"];
    NSMutableDictionary *outputAssetsInWindowByKey = [subscription objectForKey:@"outputAssetsInWindowByKey"];

    [assetKeysInWindow enumerateObjectsUsingBlock:^(NSString *key, NSUInteger idx, BOOL *stop) {
        id outputAsset = [outputAssetsInWindowByKey objectForKey:key];
        if (!outputAsset) {
            outputAsset = [NSMutableDictionary new];
            _populateOutputAsset([assetsInWindowByKey objectForKey:key], outputAsset);
        }
        [result addObject:outputAsset];
    }];
    return result;
}

- (void)_sendUpdateEventForSubscription: (NSMutableDictionary *)subscription
{
    NSMutableDictionary *details = [NSMutableDictionary new];
    NSString *subscriptionHandle = getSubscriptionHandleFromDictionary(subscription);

    setCollectionKeyInDictionary(details, getCollectionKeyFromDictionary(subscription));
    setLimitInDictionary(details, getLimitFromDictionary(subscription));
    setOffsetInDictionary(details, getOffsetFromDictionary(subscription));
    setMaxSizeInDictionary(details, getMaxSizeFromDictionary(subscription));
    setQualityInDictionary(details, getQualityFromDictionary(subscription));
    [details setObject:[subscription objectForKey:@"estimatedAssetCount"] forKey:@"estimatedAssetCount"];
    [details setObject:subscriptionHandle                                           forKey:@"subscriptionHandle"];
    [details setObject:[self _getOutputAssetArrayForSubscription: subscription]     forKey:@"assets"];

    [self _dispatchEventType:@"photoAssetsChanged" withDetails:details];
}

- (void)_sendUpdateEventForCollections
{
    NSMutableDictionary *details = [NSMutableDictionary new];
    NSArray *collections = _enumerateCollections();

    [details setObject:collections forKey:@"collections"];

    [self _dispatchEventType:@"photoAssetsChanged" withDetails:details];
}


- (void)_updateAssetsForAllAssetSubscription:(NSMutableDictionary *)subscription
{
    NSUInteger limit = getLimitFromDictionary(subscription);
    NSUInteger offset = getOffsetFromDictionary(subscription);
    NSLog(@"CordovaPhotoAssets._updateAssetsForAllAssetSubscription: offset:%d, limit:%d",(int)offset, (int)limit);

    PHFetchOptions *allPhotosOptions = [PHFetchOptions new];
    allPhotosOptions.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];

    PHFetchResult *allPhotosResult = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeImage options:allPhotosOptions];

    NSMutableArray *outputAssetList = [NSMutableArray new];
    __block NSUInteger l = limit;
    __block NSUInteger o = offset;
    [allPhotosResult enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger idx, BOOL *stop) {
        if (o > 0) o--;
        else if (l > 0) {[outputAssetList addObject:asset]; l--;}
        else *stop = YES;
    }];

    [subscription setObject:[NSNumber numberWithInteger:_allPhotoAssetsCount()] forKey:@"estimatedAssetCount"];
    [subscription setObject:allPhotosResult forKey:@"phFetchResult"];
    [subscription setObject:outputAssetList forKey:@"assetsInWindow"];
}

- (void) _updateAssetsForSubscription:(NSMutableDictionary *)subscription
{

    NSString *collectionKey = getCollectionKeyFromDictionary(subscription);

    if (collectionKey && [collectionKey isEqualToString:allImageAssetsCollectionKey]) {
        [self _updateAssetsForAllAssetSubscription:subscription];
    } else {
        // TODO:
        //   * find the collection which matches currentCollectionKey
        //   * if none match, then we consider it an empty collection (not an error) and return an empty set of assets
        //   * if we found a valid collection, enumerate its assets within the selected window
        [subscription setObject:[NSMutableArray new] forKey:@"assetsInWindow"];
        [subscription setObject:[NSNumber numberWithInteger:0] forKey:@"estimatedAssetCount"];
    }

    NSMutableArray *assetWindow = [subscription objectForKey:@"assetsInWindow"];
    [subscription setObject:assetsToAssetsByKey(assetWindow) forKey:@"assetsInWindowByKey"];
    [subscription setObject:assetKeysFromAssets(assetWindow) forKey:@"assetKeysInWindow"];
}

- (void)_updateAllSubscriptions
{
    [self.subscriptions enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, NSMutableDictionary *subscription, BOOL * _Nonnull stop) {
        [self _updateSubscription:subscription];
    }];
}

- (void)_updateImageFilesForSubscription:(NSMutableDictionary*)subscription
            oldAssetsInWindowByKey:(NSMutableDictionary*)oldAssetsInWindowByKey
{
    NSMutableDictionary *newAssetsInWindowByKey = [subscription objectForKey:@"assetsInWindowByKey"];
    NSMutableDictionary *addedAssetsByKey = [NSMutableDictionary new];
    NSMutableDictionary *removedAssetsByKey = [NSMutableDictionary new];

    [self
     _splitNewAssetsByKey:   newAssetsInWindowByKey
     andOldAssetsByKey:      oldAssetsInWindowByKey
     intoAddedAssetsByKey:   addedAssetsByKey
     andRemovedAssetsByKey:  removedAssetsByKey
     ];

    [self _deleteImageFilesForAssets:removedAssetsByKey forSubscription:subscription];
    [self _createImageFilesForAssets:addedAssetsByKey forSubscription:subscription];
}

- (void)_updateSubscription:(NSMutableDictionary *)subscription
{
    NSMutableDictionary *oldAssetsInWindowByKey = [subscription objectForKey:@"assetsInWindowByKey"];
    [self _updateAssetsForSubscription:subscription];
    [self _updateImageFilesForSubscription:subscription oldAssetsInWindowByKey:oldAssetsInWindowByKey];
    [self _sendUpdateEventForSubscription:subscription];
}

NSMutableArray *assetKeysFromAssets(NSMutableArray *assets) {
    NSMutableArray *assetKeys = [NSMutableArray new];
    [assets enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger idx, BOOL *stop) {
        [assetKeys addObject:asset.localIdentifier];
    }];
    return assetKeys;
}

- (void)_deleteImageFilesForAssets:(NSDictionary *)assetsByKey forSubscription:(NSMutableDictionary *)subscription {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *group = getSubscriptionHandleFromDictionary(subscription);
    NSMutableDictionary *outputAssetsInWindowByKey = [subscription objectForKey:@"outputAssetsInWindowByKey"];

    [assetsByKey enumerateKeysAndObjectsUsingBlock:^(NSString *key, PHAsset *asset, BOOL *stop) {
        [outputAssetsInWindowByKey removeObjectForKey:key];
        NSString *filePath = [self _filePathForAsset:asset forGroup:group];
        NSError *err;
        if (![fileManager removeItemAtPath:filePath error:&err]) {
            NSLog(@"error deleting thumbnail: %@ error: %@", filePath, [err localizedDescription]);
        }
    }];
}

- (void)_splitNewAssetsByKey:(NSMutableDictionary *)newAssetsByKey
           andOldAssetsByKey:(NSMutableDictionary *)oldAssetsByKey
        intoAddedAssetsByKey:(NSMutableDictionary *)addedAssetsByKey
       andRemovedAssetsByKey:(NSMutableDictionary *)removedAssetsByKey
{
    [newAssetsByKey enumerateKeysAndObjectsUsingBlock:^(NSString *key, PHAsset *asset, BOOL *stop) {
        if (![oldAssetsByKey objectForKey:key]) {
            [addedAssetsByKey setObject:asset forKey:key];
        }
    }];

    [oldAssetsByKey enumerateKeysAndObjectsUsingBlock:^(NSString *key, PHAsset *asset, BOOL *stop) {
        if (![newAssetsByKey objectForKey:key]) {
            [removedAssetsByKey setObject:asset forKey:key];
        }
    }];
}

- (NSString *)_filePathForAsset:(PHAsset *)asset forGroup:(NSString *)group
{
    NSString *pathFriendlyIdentifier = [asset.localIdentifier stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    NSUInteger lastModifiedAgeInSeconds = asset.modificationDate.timeIntervalSince1970;
    return [NSString stringWithFormat:@"%@/%@_%@_%lu.jpg", self.localStoragePath, group, pathFriendlyIdentifier, (unsigned long)lastModifiedAgeInSeconds];
}


UIImage *fixOrientation(UIImage *image) {

    // No-op if the orientation is already correct
    if (image.imageOrientation == UIImageOrientationUp) return image;

    // We need to calculate the proper transformation to make the image upright.
    // We do it in 2 steps: Rotate if Left/Right/Down, and then flip if Mirrored.
    CGAffineTransform transform = CGAffineTransformIdentity;

    switch (image.imageOrientation) {
        case UIImageOrientationDown:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, image.size.width, image.size.height);
            transform = CGAffineTransformRotate(transform, M_PI);
            break;

        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
            transform = CGAffineTransformTranslate(transform, image.size.width, 0);
            transform = CGAffineTransformRotate(transform, M_PI_2);
            break;

        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, 0, image.size.height);
            transform = CGAffineTransformRotate(transform, -M_PI_2);
            break;
        case UIImageOrientationUp:
        case UIImageOrientationUpMirrored:
            break;
    }

    switch (image.imageOrientation) {
        case UIImageOrientationUpMirrored:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, image.size.width, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;

        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, image.size.height, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
        case UIImageOrientationUp:
        case UIImageOrientationDown:
        case UIImageOrientationLeft:
        case UIImageOrientationRight:
            break;
    }

    // Now we draw the underlying CGImage into a new context, applying the transform
    // calculated above.
    CGContextRef ctx = CGBitmapContextCreate(NULL, image.size.width, image.size.height,
                                             CGImageGetBitsPerComponent(image.CGImage), 0,
                                             CGImageGetColorSpace(image.CGImage),
                                             CGImageGetBitmapInfo(image.CGImage));
    CGContextConcatCTM(ctx, transform);
    switch (image.imageOrientation) {
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            // Grr...
            CGContextDrawImage(ctx, CGRectMake(0,0,image.size.height,image.size.width), image.CGImage);
            break;

        default:
            CGContextDrawImage(ctx, CGRectMake(0,0,image.size.width,image.size.height), image.CGImage);
            break;
    }

    // And now we just create a new UIImage from the drawing context
    CGImageRef cgimg = CGBitmapContextCreateImage(ctx);
    UIImage *img = [UIImage imageWithCGImage:cgimg];
    CGContextRelease(ctx);
    CGImageRelease(cgimg);
    return img;
}

- (NSString *)_writeImage:(UIImage *)image toFilePath:(NSString *)filePath withQuality:(NSInteger)quality
{
    image = fixOrientation(image);

    NSData *data = UIImageJPEGRepresentation(image, quality/100.0f);

    if (!data) {
        NSLog(@"error generating jpg for thumbnail: width:%d height:%d filePath:%@", (int)image.size.width, (int)image.size.height, filePath);
        return nil;
    }

    NSError *err = nil;
    BOOL success = [data writeToFile:filePath options:NSAtomicWrite error:&err];
    if (!success) {
        NSLog(@"error writing thumbnail: %@ error: %@", filePath, [err localizedDescription]);
        return nil;
    }

    return [[NSURL fileURLWithPath:filePath] absoluteString];
}

//- (void)_createThumbnailsForAssets:(NSDictionary *)assetsByKey
- (void)_createImageFilesForAssets:(NSDictionary *)assetsByKey forSubscription:(NSMutableDictionary *)subscription
{
    NSUInteger quality  = getQualityFromDictionary(subscription);
    NSUInteger maxSize  = getMaxSizeFromDictionary(subscription);
    NSString *subscriptionHandle = getSubscriptionHandleFromDictionary(subscription);
    NSMutableDictionary *assetsInWindowByKey = [subscription objectForKey:@"assetsInWindowByKey"];
    NSMutableDictionary *outputAssetsInWindowByKey = [subscription objectForKey:@"outputAssetsInWindowByKey"];

    CGSize size = PHImageManagerMaximumSize;
    if (maxSize > 0) {
        size.height = size.width = maxSize;
    }

    [assetsInWindowByKey enumerateKeysAndObjectsUsingBlock:^(NSString *key, PHAsset *asset, BOOL *stop) {
        [self.commandDelegate runInBackground:^{
            NSMutableDictionary *outputAsset = [self _fetchAsset:asset targetSize:size withQuality:quality forGroup:subscriptionHandle];
            if (outputAsset) {
                pthread_mutex_lock(&cordovaPhotoAssetsSingletonMutex);

                [outputAssetsInWindowByKey setObject:outputAsset forKey:key];
                [self _sendUpdateEventForSubscription: subscription];

                pthread_mutex_unlock(&cordovaPhotoAssetsSingletonMutex);
            }
        }];
    }];
}

void _populateOutputAsset(PHAsset *asset, NSMutableDictionary *outputAsset) {
    [outputAsset setObject:asset.localIdentifier forKey:@"assetKey"];
    [outputAsset setObject:[NSNumber numberWithInt:(int)asset.pixelWidth] forKey:@"originalPixelWidth"];
    [outputAsset setObject:[NSNumber numberWithInt:(int)asset.pixelHeight] forKey:@"originalPixelHeight"];
}

- (NSMutableDictionary *)_fetchAsset:(PHAsset *)asset
                          targetSize:(CGSize)size
                         withQuality:(NSInteger)quality
                            forGroup:(NSString*)group
{
    PHImageRequestOptions *requestOptions = [PHImageRequestOptions new];
    requestOptions.synchronous = true;
    requestOptions.deliveryMode = PHImageRequestOptionsDeliveryModeFastFormat;
    requestOptions.resizeMode = PHImageRequestOptionsResizeModeFast;

    NSMutableDictionary __block *props = nil;

    NSLog(@"_fetchAsset: targetSize:%dx%d", (int)size.width, (int)size.height);
    [self.imageManager
     requestImageForAsset:  asset
     targetSize:            size
     contentMode:           PHImageContentModeAspectFill
     options:               requestOptions
     resultHandler:^(UIImage *image, NSDictionary *info) {
         NSLog(@"_fetchAsset: imagePresent:%d, assetId:%@, size:%dx%d, targetSize:%dx%d", !!image, asset.localIdentifier, (int)image.size.width, (int)image.size.height, (int)size.width, (int)size.height);
         NSString *filePath = [self _writeImage:image toFilePath:[self _filePathForAsset:asset forGroup:group] withQuality:quality];
         if (filePath) {
//             NSLog(@"_fetchAsset: assetId:%@, fileUrl:%@", asset.localIdentifier, filePath);
             props = [NSMutableDictionary new];
             [props setObject:filePath              forKey:@"photoUrl"];
             [props setObject:[NSNumber numberWithInt:image.size.width] forKey:@"pixelWidth"];
             [props setObject:[NSNumber numberWithInt:image.size.height] forKey:@"pixelHeight"];
             _populateOutputAsset(asset, props);
             //                 [props setObject:asset.creationDate forKey:@"creationDate"];
             //                 [props setObject:asset.modificationDate forKey:@"modificationDate"];
         }
     }];
    return props;
}


NSArray *_enumerateCollections()
{
    PHFetchOptions *userAlbumsOptions = [PHFetchOptions new];
    userAlbumsOptions.predicate = [NSPredicate predicateWithFormat:@"estimatedAssetCount > 0"];

    PHFetchResult *userAlbums = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAny options:userAlbumsOptions];

    NSMutableArray *outputArray = [NSMutableArray new];

    NSMutableDictionary *outputCollection = [NSMutableDictionary new];
    [outputCollection setObject:allImageAssetsCollectionKey   forKey:@"collectionKey"];
    [outputCollection setObject:@"Camera Roll"      forKey:@"collectionName"];
    [outputCollection setObject:[NSNumber numberWithInteger:_allPhotoAssetsCount()] forKey:@"estimatedAssetCount"];
    [outputArray addObject:outputCollection];

    [userAlbums enumerateObjectsUsingBlock:^(PHAssetCollection *currentCollectionKey, NSUInteger idx, BOOL *stop) {
        NSMutableDictionary *outputCollection = [NSMutableDictionary new];
        [outputCollection setObject:currentCollectionKey.localIdentifier  forKey:@"collectionKey"];
        [outputCollection setObject:currentCollectionKey.localizedTitle   forKey:@"collectionName"];
        [outputCollection setObject:[NSNumber numberWithInteger:currentCollectionKey.estimatedAssetCount] forKey:@"estimatedAssetCount"];
        [outputArray addObject:outputCollection];
    }];

    return outputArray;
}

NSMutableDictionary *_findCollection(NSArray *collections, NSString *collectionKey) {
    __block NSMutableDictionary *result = nil;
    [collections enumerateObjectsUsingBlock:^(NSMutableDictionary *collection, NSUInteger idx, BOOL *stop) {
        if ([collectionKey isEqualToString:[collection objectForKey:@"collectionKey"]]) {
            result = collection;
            *stop = YES;
        }
    }];
    return result;
}

NSUInteger _allPhotoAssetsCount()
{
    PHFetchOptions *allPhotosOptions = [PHFetchOptions new];
    allPhotosOptions.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:YES]];
    PHFetchResult *allPhotosResult = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeImage options:allPhotosOptions];
    return allPhotosResult.count;
}

@end
