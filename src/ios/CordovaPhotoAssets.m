#import <Cordova/CDV.h>
#import "CordovaPhotoAssets.h"
#import <Photos/Photos.h>

NSString *allImageAssetsKey = @"all";

@interface CordovaPhotoAssets ()
@property NSUInteger offset;
@property NSUInteger limit;
@property NSString *selectedCollectionKey;
@end

@implementation CordovaPhotoAssets

- (void)pluginInitialize {
    self.offset = 0;
    self.limit = 100;
    self.selectedCollectionKey = NULL;
}

- (void)echoBackHello:(CDVInvokedUrlCommand*)command
{
    NSString* callbackId = [command callbackId];
    NSString* name = [[command arguments] objectAtIndex:0];
    NSString* msg = [NSString stringWithFormat: @"Hello, %@\nCongratulations!\nCordovaPhotoAssets is properly installed.", name];

    CDVPluginResult* result = [CDVPluginResult
                               resultWithStatus:CDVCommandStatus_OK
                               messageAsString:msg];

    [self.commandDelegate sendPluginResult:result callbackId:callbackId];
    //    [self _enumeratePhotoAssets];
    [self _enumerateCollections];
}

- (void)selectAssetCollection:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        NSString* collectionKey = [[command arguments] objectAtIndex:0];

        [self _startMonitoringCollection:collectionKey];

        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];

    }];

}

- (void)getAssetCollections:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{

        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:[self _enumerateCollections]];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];

    }];

}

/**************************************************
 PRIVATE
 **************************************************/

/*
 TODO:
 - set offset and limit
 - generate thumbnails
 - do call back when thumbnails are ready
 - register changes listener ->
    - first generate missing thumbnails
    - second do callback with updates
    - finally, delete old thumbnails
 */

- (void)_startMonitoringCollection:(NSString*)assetCollectionKey
{
    if (assetCollectionKey == allImageAssetsKey) {
        // follow all local photo assets
    } else {
        // follow specific assets, collectionKey must be a valid iOS localIdentifier
    }

}

- (NSArray *)_enumerateCollections
{
    PHFetchOptions *userAlbumsOptions = [PHFetchOptions new];
    userAlbumsOptions.predicate = [NSPredicate predicateWithFormat:@"estimatedAssetCount > 0"];

    PHFetchResult *userAlbums = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAny options:userAlbumsOptions];

    __block NSMutableArray *outputArray = [NSMutableArray new];

    NSMutableDictionary *outputCollection = [NSMutableDictionary new];
    [outputCollection setObject:allImageAssetsKey   forKey:@"id"];
    [outputCollection setObject:@"Camera Roll"      forKey:@"title"];
    [outputCollection setObject:[NSNumber numberWithInteger:[self _allPhotoAssetsCount]] forKey:@"count"];
    [outputArray addObject:outputCollection];

    [userAlbums enumerateObjectsUsingBlock:^(PHAssetCollection *collection, NSUInteger idx, BOOL *stop) {
        NSMutableDictionary *outputCollection = [NSMutableDictionary new];
        [outputCollection setObject:collection.localIdentifier  forKey:@"id"];
        [outputCollection setObject:collection.localizedTitle   forKey:@"title"];
        [outputCollection setObject:[NSNumber numberWithInteger:collection.estimatedAssetCount] forKey:@"count"];
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

- (NSUInteger)_allPhotoAssetsCount
{
    PHFetchOptions *allPhotosOptions = [PHFetchOptions new];
    allPhotosOptions.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:YES]];
    PHFetchResult *allPhotosResult = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeImage options:allPhotosOptions];
    return allPhotosResult.count;
}

@end
