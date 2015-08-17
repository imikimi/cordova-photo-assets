#import <Cordova/CDV.h>
#import "CordovaPhotoAssets.h"

@implementation CordovaPhotoAssets

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
