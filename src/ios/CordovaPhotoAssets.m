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
@property NSString *currentAssetCollection;
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
    self.currentAssetCollection = nil;

    self.imageManager = [PHImageManager defaultManager];
    self.monitoredAssets = [NSMutableArray new];
    self.monitoredAssetsByKey = [NSMutableDictionary new];

    [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self]; //(id<PHPhotoLibraryChangeObserver>)

    //TODO: make a subdirectory and delete all files in it here, on init
    self.localStoragePath = [NSTemporaryDirectory() stringByStandardizingPath];
}

- (void)getAssetCollections:(CDVInvokedUrlCommand*)command
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

        NSMutableDictionary *results = [NSMutableDictionary new];
        [results setObject:[NSNumber numberWithLong:self.limit] forKey:@"limit"];
        [results setObject:[NSNumber numberWithLong:self.offset] forKey:@"offset"];
        [results setObject:[NSNumber numberWithLong:self.thumbnailQuality] forKey:@"thumbnailQuality"];
        [results setObject:[NSNumber numberWithLong:self.thumbnailSize] forKey:@"thumbnailSize"];
        [results setObject:self.currentAssetCollection forKey:@"currentAssetCollection"];

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

        // currentAssetCollection
        if ((nsString = [options objectForKey:@"currentAssetCollection"])) {
            if (nsString != self.currentAssetCollection) {
                thumbnailOptionsChanged = YES;
                self.currentAssetCollection = nsString;
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
 PRIVATE
 **************************************************/

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


// implement PHPhotoLibraryChangeObserver
- (void)photoLibraryDidChange:(PHChange *)changeInfo {
    NSLog(@"photoLibraryDidChange");
    [self.commandDelegate runInBackground:^{
        pthread_mutex_lock(&cordovaPhotoAssetsSingletonMutex);
        [self _updateThumbnailsAndThumbnailOptionsChanged:NO];
        pthread_mutex_unlock(&cordovaPhotoAssetsSingletonMutex);
    }];
}

NSMutableDictionary *assetsToAssetsByKey(NSArray *assets) {
    NSMutableDictionary *assetsByKey = [NSMutableDictionary new];
    [assets enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger idx, BOOL *stop) {
        [assetsByKey setObject:asset forKey:asset.localIdentifier];
    }];
    return assetsByKey;
}

- (void)_updateThumbnailsAndThumbnailOptionsChanged:(BOOL)thumbnailOptionsChanged
{
    NSMutableArray *newAssets;

    if (self.currentAssetCollection == allImageAssetsKey) {
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
    [self _createThumbnailsForAssets:addedAssets];

    self.monitoredAssets = newAssets;
    self.monitoredAssetsByKey = newAssetsByKey;
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
    return [NSString stringWithFormat:@"%@/thumbnail_%@.jpg", self.localStoragePath, asset.localIdentifier];
}

- (NSString *)_writeThumbnail:(UIImage *)image toFilePath:(NSString *)filePath
{
    NSData *data = UIImageJPEGRepresentation(image, self.thumbnailQuality/100.0f);

    NSError* err = nil;
    if (![data writeToFile:filePath options:NSAtomicWrite error:&err]) {
        NSLog(@"error writing thumbnail: %@ error: %@", filePath, [err localizedDescription]);
        return nil;
    }

    return [[NSURL fileURLWithPath:filePath] absoluteString];
}

- (void)_createThumbnailsForAssets:(NSArray *)assetList
{
    NSMutableArray *activeAssets = [NSMutableArray new];
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
                 [props setObject:filePath forKey:@"url"];
                 [props setObject:asset.localIdentifier forKey:@"key"];
                 [activeAssets addObject:props];
             }
         }];
    }];
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
    [outputCollection setObject:allImageAssetsKey   forKey:@"id"];
    [outputCollection setObject:@"Camera Roll"      forKey:@"title"];
    [outputCollection setObject:[NSNumber numberWithInteger:_allPhotoAssetsCount()] forKey:@"count"];
    [outputArray addObject:outputCollection];

    [userAlbums enumerateObjectsUsingBlock:^(PHAssetCollection *currentAssetCollection, NSUInteger idx, BOOL *stop) {
        NSMutableDictionary *outputCollection = [NSMutableDictionary new];
        [outputCollection setObject:currentAssetCollection.localIdentifier  forKey:@"id"];
        [outputCollection setObject:currentAssetCollection.localizedTitle   forKey:@"title"];
        [outputCollection setObject:[NSNumber numberWithInteger:currentAssetCollection.estimatedAssetCount] forKey:@"count"];
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
