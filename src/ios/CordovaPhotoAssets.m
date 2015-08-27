#import <Cordova/CDV.h>
#import "CordovaPhotoAssets.h"
#import <Photos/Photos.h>
#import <pthread.h>

NSString *allImageAssetsKey = @"all";
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

    pthread_mutex_init(&cordovaPhotoAssetsSingletonMutex, NULL);

    self.offset = 0;
    self.limit = 100;
    self.thumbnailSize = 270; // big enough for max thumbnailQuality on iphone6+ at 4 per line (portrait) (iphone6+ device-pixel-width: 1080)
    self.thumbnailQuality = 95;
    self.currentCollectionKey = nil;

    self.imageManager = [PHImageManager defaultManager];
    self.monitoredAssets = [NSMutableArray new];
    self.monitoredAssetsByKey = [NSMutableDictionary new];

    [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self]; //(id<PHPhotoLibraryChangeObserver>)

    //TODO: make a subdirectory and delete all files in it here, on init
    self.localStoragePath = [NSTemporaryDirectory() stringByStandardizingPath];
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

- (void)setOptionsFromJavascript:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        pthread_mutex_lock(&cordovaPhotoAssetsSingletonMutex);
        NSDictionary* options = [[command arguments] objectAtIndex:0];

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
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
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
        NSLog(@"CordovaPhotoAssets DispatchEvent '%@': INTERNAL ERROR converting 'details' to json: %@", eventType, error);
        return;
    }

    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    NSLog(@"CordovaPhotoAssets DispatchEvent '%@': jsonString: %@", eventType, jsonString);

    NSString *javascript = [NSString stringWithFormat:@"document.dispatchEvent(new CustomEvent('%@', {detail:%@}));", eventType, jsonString];
    NSLog(@"CordovaPhotoAssets DispatchEvent '%@': invoking javascript: %@", eventType, javascript);

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
    [details setObject:_enumerateCollections()          forKey:@"collections"];
    [details setObject:[self _getOptionsAsDictionary]   forKey:@"options"];
    [details setObject:outputAssets                     forKey:@"assets"];

    [self _dispatchEventType:@"photoAssetsChanged" withDetails:details];
}

- (void)_updateThumbnailsAndThumbnailOptionsChanged:(BOOL)thumbnailOptionsChanged
{
    NSMutableArray *newAssets;

    if ([self.currentCollectionKey isEqualToString:allImageAssetsKey]) {
        newAssets = [self _enumerateAllAssets];
    } else {
        // follow specific assets, collectionKey must be a valid iOS localIdentifier
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

- (NSString *)_writeThumbnail:(UIImage *)image toFilePath:(NSString *)filePath
{
    NSData *data = UIImageJPEGRepresentation(image, self.thumbnailQuality/100.0f);

    if (!data) {
        NSLog(@"error generating jpg for thumbnail: width:%d height:%d filePath:%@", (int)image.size.width, (int)image.size.height, filePath);
        return nil;
    }

    NSError* err = nil;
    BOOL success = [data writeToFile:filePath options:NSAtomicWrite error:&err];
    if (!success) {
        NSLog(@"error writing thumbnail: %@ error: %@", filePath, [err localizedDescription]);
        return nil;
    }

    return [[NSURL fileURLWithPath:filePath] absoluteString];
}

- (NSMutableArray *)_createThumbnailsForAssets:(NSArray *)assetList
{
    NSMutableArray *outputAssets = [NSMutableArray new];
    CGSize size;
    size.height = size.width = self.thumbnailSize;
    [assetList enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger idx, BOOL *stop) {
        [self.imageManager
         requestImageForAsset: asset
         targetSize: size
         contentMode: PHImageContentModeAspectFill
         options:NULL
         resultHandler:^(UIImage *image, NSDictionary *info) {
             NSString *filePath = [self _writeThumbnail:image toFilePath:[self _thumbnailFilePathForAsset:asset]];
             if (filePath) {
                 NSMutableDictionary *props = [NSMutableDictionary new];
                 [props setObject:filePath              forKey:@"thumbnailUrl"];
                 [props setObject:asset.localIdentifier forKey:@"assetKey"];
                 [props setObject:[NSNumber numberWithInt:image.size.width] forKey:@"thumbnailPixelWidth"];
                 [props setObject:[NSNumber numberWithInt:image.size.height] forKey:@"thumbnailPixelHeight"];
                 [props setObject:[NSNumber numberWithInt:(int)asset.pixelWidth] forKey:@"originalPixelWidth"];
                 [props setObject:[NSNumber numberWithInt:(int)asset.pixelHeight] forKey:@"originalPixelHeight"];
//                 [props setObject:asset.creationDate forKey:@"creationDate"];
//                 [props setObject:asset.modificationDate forKey:@"modificationDate"];
                 [outputAssets addObject:props];
             }
         }];
    }];
    return outputAssets;
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

    __block NSMutableArray *outputArray = [NSMutableArray new];

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
    NSLog(@"outputArray: %@", outputArray);

    return outputArray;
}

- (void)_enumeratePhotoAssets
{
    NSLog(@"fetchAssetsWithMediaType");
    PHFetchOptions *allPhotosOptions = [PHFetchOptions new];
    allPhotosOptions.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:YES]];

    PHFetchResult *allPhotosResult = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeImage options:allPhotosOptions];

    NSLog(@"fetchAssetsWithMediaType count=%lu", allPhotosResult.count);
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
