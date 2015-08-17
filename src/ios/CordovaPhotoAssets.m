#import <Cordova/CDV.h>
#import "CordovaPhotoAssets.h"

@implementation CordovaPhotoAssets

// http://stackoverflow.com/questions/25981374/ios-8-photos-framework-get-a-list-of-all-albums-with-ios8
- (void)echoBackHello:(CDVInvokedUrlCommand*)command
{
    NSString* callbackId = [command callbackId];
    NSString* name = [[command arguments] objectAtIndex:0];
    NSString* msg = [NSString stringWithFormat: @"Hello, %@\nCongratulations!\nCordovaPhotoAssets is properly installed.", name];

    CDVPluginResult* result = [CDVPluginResult
                               resultWithStatus:CDVCommandStatus_OK
                               messageAsString:msg];

    [self.commandDelegate sendPluginResult:result callbackId:callbackId];
}

@end
