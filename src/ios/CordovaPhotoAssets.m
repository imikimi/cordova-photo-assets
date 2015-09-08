#import <Cordova/CDV.h>
#import "CordovaPhotoAssets.h"
#import <Photos/Photos.h>
#import <pthread.h>

NSString *allImageAssetsKey = @"all";
NSString *localStorageSubdir = @"CordovaPhotoAssets";
pthread_mutex_t cordovaPhotoAssetsSingletonMutex;

// Very helpful starting place:
// http://stackoverflow.com/questions/25981374/ios-8-photos-framework-get-a-list-of-all-albums-with-ios8

@interface CordovaPhotoAssets () <PHPhotoLibraryChangeObserver>
@property NSUInteger offset;
@property NSUInteger thumbnailQuality;
@property NSUInteger limit;
@property NSUInteger thumbnailSize;
@property NSString *currentCollectionKey;
@property NSString *localStoragePath;
@property PHImageManager *imageManager;
@property NSMutableArray *monitoredAssets;
@property NSMutableDictionary *monitoredAssetsByKey;
@end


@implementation CordovaPhotoAssets

- (void)pluginInitialize {
    NSLog(@"CordovaPhotoAssets initializing...");

    pthread_mutex_init(&cordovaPhotoAssetsSingletonMutex, NULL);

    self.offset = 0;
    self.limit = 50;
    self.thumbnailSize = 270; // big enough for max thumbnailQuality on iphone6+ at 4 per line (portrait) (iphone6+ device-pixel-width: 1080)
    self.thumbnailQuality = 95;
    self.currentCollectionKey = @"";

    self.imageManager = [PHImageManager defaultManager];
    self.monitoredAssets = [NSMutableArray new];
    self.monitoredAssetsByKey = [NSMutableDictionary new];

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

- (void)getOptionsForJavascript:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        pthread_mutex_lock(&cordovaPhotoAssetsSingletonMutex);

        NSMutableDictionary *results = [self _getOptionsAsDictionary];

        pthread_mutex_unlock(&cordovaPhotoAssetsSingletonMutex);

        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:results];
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

- (void)setOptionsFromJavascript:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        NSMutableArray *errors = [NSMutableArray new];
        NSDictionary* options = [[command arguments] objectAtIndex:0];
        CDVPluginResult* pluginResult = nil;

        _validateNumberOption(errors, options, @"limit", 1, 1000);
        _validateNumberOption(errors, options, @"offset", 0, 1000000000);
        _validateNumberOption(errors, options, @"thumbnailQuality", 0, 100);
        _validateNumberOption(errors, options, @"thumbnailSize", 1, 10000);
        _validateStringOption(errors, options, @"currentCollectionKey");

        if (errors.count > 0) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsArray:errors];
        } else {

            pthread_mutex_lock(&cordovaPhotoAssetsSingletonMutex);

            NSString *nsString;
            NSNumber *nsNumber;
            BOOL thumbnailOptionsChanged = NO;
            BOOL collectionRangeChanged = NO;

            // limit
            if ((nsNumber = [options objectForKey:@"limit"])) {
                NSUInteger limit = nsNumber.unsignedIntegerValue;
                if (limit != self.limit) {
                    collectionRangeChanged = YES;
                    self.limit = limit;
                }
            }

            // offset
            if ((nsNumber = [options objectForKey:@"offset"])) {
                NSUInteger offset = nsNumber.unsignedIntegerValue;
                if (offset != self.offset) {
                    collectionRangeChanged = YES;
                    self.offset = offset;
                }
            }

            // thumbnailQuality
            if ((nsNumber = [options objectForKey:@"thumbnailQuality"])) {
                NSUInteger thumbnailQuality = nsNumber.unsignedIntegerValue;
                if (thumbnailQuality > 100) thumbnailQuality = 100;
                if (thumbnailQuality != self.thumbnailQuality) {
                    thumbnailOptionsChanged = YES;
                    self.offset = thumbnailQuality;
                }
            }

            // thumbnailSize
            if ((nsNumber = [options objectForKey:@"thumbnailSize"])) {
                NSUInteger thumbnailSize = nsNumber.unsignedIntegerValue;
                if (thumbnailSize != self.thumbnailSize) {
                    thumbnailOptionsChanged = YES;
                    self.thumbnailSize = thumbnailSize;
                }
            }

            // currentCollectionKey
            if ((nsString = [options objectForKey:@"currentCollectionKey"])) {
                if (nsString != self.currentCollectionKey) {
                    thumbnailOptionsChanged = YES;
                    self.currentCollectionKey = nsString;
                }
            }

            if (thumbnailOptionsChanged || collectionRangeChanged) {
                [self _updateThumbnailsAndThumbnailOptionsChanged: thumbnailOptionsChanged];
            }

            pthread_mutex_unlock(&cordovaPhotoAssetsSingletonMutex);
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        }

        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

// NOTE: we can get all the EXIF data if we fetch the full-sized image.
// The returned CIImage has a properties field with this data.
// http://stackoverflow.com/questions/24462112/ios-8-photos-framework-access-photo-metadata
- (void)getPhoto:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        NSDictionary* options = [[command arguments] objectAtIndex:0];
        CDVPluginResult* pluginResult = nil;

        NSString *assetKey = [options objectForKey:@"assetKey"];

        NSInteger maxSize = 0;
        NSNumber *maxSizeNSN = nil;
        if ((maxSizeNSN = (NSNumber *)[options objectForKey:@"maxSize"])) {
            maxSize = maxSizeNSN.integerValue;
        }

        NSInteger quality = 95;
        NSNumber *qualityNSN = nil;
        if ((qualityNSN = (NSNumber *)[options objectForKey:@"quality"])) {
            quality = qualityNSN.integerValue;
            if (quality < 0) quality = 0;
            if (quality > 100) quality = 100;
        }

        PHAsset *asset = assetFromKey(assetKey);

        if (!asset) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"asset not found for assetKey: %@", assetKey]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        } else {
            CGSize size = PHImageManagerMaximumSize;
            if (maxSize > 0) {
                size.height = size.width = maxSize;
            }
            NSMutableDictionary *fetchedProps = [self _fetchAsset:asset targetSize:size withQuality:quality];

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
    NSLog(@"photoLibraryDidChange");
    [self.commandDelegate runInBackground:^{
        pthread_mutex_lock(&cordovaPhotoAssetsSingletonMutex);
        [self _updateThumbnailsAndThumbnailOptionsChanged:NO];
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


- (NSMutableDictionary *)_getOptionsAsDictionary {
    NSMutableDictionary *results = [NSMutableDictionary new];
    [results setObject:[NSNumber numberWithLong:self.limit] forKey:@"limit"];
    [results setObject:[NSNumber numberWithLong:self.offset] forKey:@"offset"];
    [results setObject:[NSNumber numberWithLong:self.thumbnailQuality] forKey:@"thumbnailQuality"];
    [results setObject:[NSNumber numberWithLong:self.thumbnailSize] forKey:@"thumbnailSize"];
    [results setObject:self.currentCollectionKey forKey:@"currentCollectionKey"];
    return results;
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

- (void)_sendUpdateEventWithAssets:(NSArray *)outputAssets
{
    NSMutableDictionary *details = [NSMutableDictionary new];
    NSArray *collections = _enumerateCollections();
    id currentCollection = _findCollection(collections, self.currentCollectionKey);
    if (!currentCollection) currentCollection = [NSNull new];

    [details setObject:collections                      forKey:@"collections"];
    [details setObject:[self _getOptionsAsDictionary]   forKey:@"options"];
    [details setObject:outputAssets                     forKey:@"assets"];
    [details setObject:currentCollection                forKey:@"currentCollection"];

    [self _dispatchEventType:@"photoAssetsChanged" withDetails:details];
}

- (void)_updateThumbnailsAndThumbnailOptionsChanged:(BOOL)thumbnailOptionsChanged
{
    NSMutableArray *newAssets;
    NSString *currentCollectionKey = self.currentCollectionKey;

    if (currentCollectionKey && [currentCollectionKey isEqualToString:allImageAssetsKey]) {
        newAssets = [self _enumerateAllAssets];
    } else {
        // TODO:
        //   * find the collection which matches currentCollectionKey
        //   * if none match, then we consider it an empty collection (not an error) and return an empty set of assets
        //   * if we found a valid collection, enumerate its assets within the selected window
        newAssets = [NSMutableArray new];
    }

    NSMutableArray *addedAssets = nil;
    NSMutableArray *removedAssets = nil;
    NSMutableDictionary *newAssetsByKey = assetsToAssetsByKey(newAssets);
    NSDictionary *oldAssetsByKey = self.monitoredAssetsByKey;

    if (thumbnailOptionsChanged) {
        addedAssets = newAssets;
        removedAssets = self.monitoredAssets;
    } else {
        // only the range changed, reuse already-rendered/monitored assets where possible
        addedAssets = [NSMutableArray new];
        removedAssets = [NSMutableArray new];

        [self _splitNewAssets:newAssetsByKey andOldAssets:oldAssetsByKey intoAddedAssets:addedAssets andRemovedAssets:removedAssets];
    }

    [self _deleteThumbnailsForAssets:removedAssets];
    NSMutableArray *outputAssets = [self _createThumbnailsForAssets:addedAssets];

    self.monitoredAssets = newAssets;
    self.monitoredAssetsByKey = newAssetsByKey;

    [self _sendUpdateEventWithAssets:outputAssets];

    /*
     Create all thumbnails
     Update monitoring of assets.
     - stop monitoring some
     - start monitoring others
     create data to send to javascript
     send event to javascript for currently available thumbnails.
     */
}

- (void)_deleteThumbnailsForAssets:(NSArray *)assetList {
    NSFileManager *fileManager = [NSFileManager defaultManager];

    [assetList enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger idx, BOOL *stop) {
        NSString *filePath = [self _thumbnailFilePathForAsset:asset];
        NSError *err;
        if (![fileManager removeItemAtPath:filePath error:&err]) {
            NSLog(@"error deleting thumbnail: %@ error: %@", filePath, [err localizedDescription]);
        }
    }];
}

- (void)_splitNewAssets:(NSDictionary *)newAssets
           andOldAssets:(NSDictionary *)oldAssets
        intoAddedAssets:(NSMutableArray *)addedAssets
       andRemovedAssets:(NSMutableArray *)removedAssets
{
    [newAssets enumerateKeysAndObjectsUsingBlock:^(NSString *key, PHAsset *asset, BOOL *stop) {
        if (![oldAssets objectForKey:key]) {
            [addedAssets addObject:asset];
        }
    }];

    [oldAssets enumerateKeysAndObjectsUsingBlock:^(NSString *key, PHAsset *asset, BOOL *stop) {
        if (![newAssets objectForKey:key]) {
            [removedAssets addObject:asset];
        }
    }];

}

- (NSString *)_thumbnailFilePathForAsset:(PHAsset *)asset {
    NSString *pathFriendlyIdentifier = [asset.localIdentifier stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    NSUInteger lastModifiedAgeInSeconds = asset.modificationDate.timeIntervalSince1970;
    return [NSString stringWithFormat:@"%@/thumbnail_%@_%lu.jpg", self.localStoragePath, pathFriendlyIdentifier, (unsigned long)lastModifiedAgeInSeconds];
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

    NSLog(@"image: %dx%d orientation:%d", (int)image.size.width, (int)image.size.height, (int)image.imageOrientation);
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

- (NSMutableArray *)_createThumbnailsForAssets:(NSArray *)assetList
{
    PHImageRequestOptions *requestOptions = [PHImageRequestOptions new];
    requestOptions.synchronous = true;
    requestOptions.deliveryMode = PHImageRequestOptionsDeliveryModeFastFormat;
    requestOptions.resizeMode = PHImageRequestOptionsResizeModeFast;

    NSMutableArray *outputAssets = [NSMutableArray new];
    CGSize size;
    size.height = size.width = self.thumbnailSize;
    [assetList enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger idx, BOOL *stop) {
        NSMutableDictionary *props = [self _fetchAsset:asset targetSize:size withQuality:self.thumbnailQuality];
        if (props) [outputAssets addObject:props];
    }];
    return outputAssets;
}

- (NSMutableDictionary *)_fetchAsset:(PHAsset *)asset targetSize:(CGSize)size withQuality:(NSInteger)quality {
    PHImageRequestOptions *requestOptions = [PHImageRequestOptions new];
    requestOptions.synchronous = true;
    requestOptions.deliveryMode = PHImageRequestOptionsDeliveryModeFastFormat;
    requestOptions.resizeMode = PHImageRequestOptionsResizeModeFast;

    NSMutableDictionary __block *props = nil;

    [self.imageManager
     requestImageForAsset:  asset
     targetSize:            size
     contentMode:           PHImageContentModeAspectFill
     options:               requestOptions
     resultHandler:^(UIImage *image, NSDictionary *info) {
         NSString *filePath = [self _writeImage:image toFilePath:[self _thumbnailFilePathForAsset:asset] withQuality:quality];
         if (filePath) {
             props = [NSMutableDictionary new];
             [props setObject:filePath              forKey:@"photoUrl"];
             [props setObject:asset.localIdentifier forKey:@"assetKey"];
             [props setObject:[NSNumber numberWithInt:image.size.width] forKey:@"pixelWidth"];
             [props setObject:[NSNumber numberWithInt:image.size.height] forKey:@"pixelHeight"];
             [props setObject:[NSNumber numberWithInt:(int)asset.pixelWidth] forKey:@"originalPixelWidth"];
             [props setObject:[NSNumber numberWithInt:(int)asset.pixelHeight] forKey:@"originalPixelHeight"];
             //                 [props setObject:asset.creationDate forKey:@"creationDate"];
             //                 [props setObject:asset.modificationDate forKey:@"modificationDate"];
         }
     }];
    return props;
}

- (NSMutableArray *)_enumerateAllAssets
{
    PHFetchOptions *allPhotosOptions = [PHFetchOptions new];
    allPhotosOptions.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:YES]];

    PHFetchResult *allPhotosResult = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeImage options:allPhotosOptions];

    NSMutableArray *outputAssetList = [NSMutableArray new];
    __block NSUInteger limit = self.limit;
    __block NSUInteger offset = self.offset;
    [allPhotosResult enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger idx, BOOL *stop) {
        if (offset > 0) {
            offset--;
        } else if (limit > 0) {
            [outputAssetList addObject:asset];
            limit--;
        } else {
            *stop = YES;
        }
    }];

    return outputAssetList;
}

NSArray *_enumerateCollections()
{
    PHFetchOptions *userAlbumsOptions = [PHFetchOptions new];
    userAlbumsOptions.predicate = [NSPredicate predicateWithFormat:@"estimatedAssetCount > 0"];

    PHFetchResult *userAlbums = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAny options:userAlbumsOptions];

    NSMutableArray *outputArray = [NSMutableArray new];

    NSMutableDictionary *outputCollection = [NSMutableDictionary new];
    [outputCollection setObject:allImageAssetsKey   forKey:@"collectionKey"];
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

- (void)_enumeratePhotoAssets
{
    NSLog(@"fetchAssetsWithMediaType");
    PHFetchOptions *allPhotosOptions = [PHFetchOptions new];
    allPhotosOptions.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:YES]];

    PHFetchResult *allPhotosResult = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeImage options:allPhotosOptions];

    NSLog(@"fetchAssetsWithMediaType count=%lu", (unsigned long)allPhotosResult.count);
    __block int limit = 100;
    [allPhotosResult enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger idx, BOOL *stop) {
        NSLog(@"asset %@", asset);
        if (limit-- <= 0) {*stop = YES;}
    }];
}

NSUInteger _allPhotoAssetsCount()
{
    PHFetchOptions *allPhotosOptions = [PHFetchOptions new];
    allPhotosOptions.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:YES]];
    PHFetchResult *allPhotosResult = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeImage options:allPhotosOptions];
    return allPhotosResult.count;
}

@end
