//
//  LEANAppDelegate.m
//  LeanIOS
//
//  Created by Weiyin He on 2/10/14.
// Copyright (c) 2014 GoNative.io LLC. All rights reserved.
//

#import <OneSignal/OneSignal.h>
#import <FBSDKCoreKit/FBSDKCoreKit.h>
#import "LEANAppDelegate.h"
#import "GoNativeAppConfig.h"
#import "LEANWebViewIntercept.h"
#import "LEANUrlCache.h"
#import "LEANRootViewController.h"
#import "LEANConfigUpdater.h"
#import "LEANSimulator.h"
#import "GNRegistrationManager.h"
#import "GNInAppPurchase.h"

@interface LEANAppDelegate()
@property GNInAppPurchase *iap;
@end

@implementation LEANAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    GoNativeAppConfig *appConfig = [GoNativeAppConfig sharedAppConfig];
    
    // Register launch
    [LEANConfigUpdater registerEvent:@"launch" data:nil];
    
    // proxy handler to intercept HTML for custom CSS and viewport
    [LEANWebViewIntercept register];
    
    // OneSignal
    if (appConfig.oneSignalEnabled) {
        [OneSignal initWithLaunchOptions:launchOptions appId:appConfig.oneSignalAppId handleNotificationReceived:^(OSNotification *notification) {

            OSNotificationPayload *payload = notification.payload;
            NSString *message = [payload.body copy];
            NSString *title = notification.payload.title;
            
            NSString *urlString;
            NSURL *url;
            if (payload.additionalData) {
                urlString = payload.additionalData[@"u"];
                if (![urlString isKindOfClass:[NSString class]]) {
                    urlString = payload.additionalData[@"targetUrl"];
                }
                if ([urlString isKindOfClass:[NSString class]]) {
                    url = [NSURL URLWithString:urlString];
                }
            }
            
            BOOL webviewOnTop = NO;
            LEANRootViewController *rvc = (LEANRootViewController*) self.window.rootViewController;
            if (![rvc isKindOfClass:[LEANRootViewController class]]) {
                rvc = nil;
            } else {
                webviewOnTop = [rvc webviewOnTop];
            }
            
            if (notification.isAppInFocus) {
                // Show an alert, and include a "view" button if there is a url and the webview is currently the top view.
                
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
                if (url && webviewOnTop) {
                    [alert addAction:[UIAlertAction actionWithTitle:@"View" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                        [rvc loadUrl:url];
                    }]];
                }
                
                [rvc presentAlert:alert];
            }
        } handleNotificationAction:^(OSNotificationOpenedResult *result) {
            OSNotificationPayload *payload = result.notification.payload;
            
            NSString *urlString;
            NSURL *url;
            if (payload.additionalData) {
                urlString = payload.additionalData[@"u"];
                if (![urlString isKindOfClass:[NSString class]]) {
                    urlString = payload.additionalData[@"targetUrl"];
                }
                if ([urlString isKindOfClass:[NSString class]]) {
                    url = [NSURL URLWithString:urlString];
                }
            }
            
            BOOL webviewOnTop = NO;
            UIViewController *rvc = self.window.rootViewController;
            if ([rvc isKindOfClass:[LEANRootViewController class]]) {
                webviewOnTop = [(LEANRootViewController*)rvc webviewOnTop];
            }

            if (url && webviewOnTop) {
                // for when the app is launched from scratch from a push notification
                [(LEANRootViewController*)rvc setInitialUrl:url];
                
                // for when the app was backgrounded
                [(LEANRootViewController*)rvc loadUrl:url];
            }
        } settings:@{kOSSettingsKeyAutoPrompt: @false,
                     kOSSettingsKeyInFocusDisplayOption: [NSNumber numberWithInteger:OSNotificationDisplayTypeNone]}];
        
        if (appConfig.oneSignalAutoRegister) {
            [OneSignal registerForPushNotifications];
        }
    }
    
    // registration service
    GNRegistrationManager *registration = [GNRegistrationManager sharedManager];
    [registration processConfig:appConfig.registrationEndpoints];
    if (appConfig.oneSignalEnabled) {
        [OneSignal IdsAvailable:^(NSString *userId, NSString *pushToken) {
            [registration setOneSignalUserId:userId];
        }];
    }
    
    // download new config
    [[[LEANConfigUpdater alloc] init] updateConfig];
    
    [self configureApplication];
    
    // listen for reachability
    self.internetReachability = [Reachability reachabilityForInternetConnection];
    [self.internetReachability startNotifier];
    
    // Facebook SDK
    if (appConfig.facebookEnabled) {
        [[FBSDKApplicationDelegate sharedInstance] application:application
                                 didFinishLaunchingWithOptions:launchOptions];
    }
    
    // disable sleep if requested
    if (appConfig.keepScreenOn) {
        application.idleTimerDisabled = YES;
    }
    
    GNInAppPurchase *iap = [GNInAppPurchase sharedInstance];
    [[SKPaymentQueue defaultQueue] addTransactionObserver:iap];
    [iap initialize];
    
    return YES;
}

- (void)configureApplication
{
    GoNativeAppConfig *appConfig = [GoNativeAppConfig sharedAppConfig];

    // tint color from app config
    if (appConfig.tintColor) {
        self.window.tintColor = appConfig.tintColor;
    }
    
    // start cast controller
    if (appConfig.enableChromecast) {
        self.castController = [[LEANCastController alloc] init];
        [self.castController performScan:YES];
    } else {
        [self.castController performScan:NO];
        self.castController = nil;
    }
    
    [LEANSimulator checkStatus];
}

- (void)application:(UIApplication *)app didFailToRegisterForRemoteNotificationsWithError:(NSError *)err {
    NSLog(@"Error registering for push notifications: %@", err);
}


- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    if ([LEANSimulator openURL:url]) {
        return YES;
    }
    
    // Facebook SDK
    if ([GoNativeAppConfig sharedAppConfig].facebookEnabled) {
        return [[FBSDKApplicationDelegate sharedInstance] application:application
                                                              openURL:url
                                                    sourceApplication:sourceApplication
                                                           annotation:annotation];
    }
    return NO;
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    if ([GoNativeAppConfig sharedAppConfig].isSimulator) {
        [LEANSimulator checkSimulatorSetting];
    }
    
    if ([GoNativeAppConfig sharedAppConfig].facebookEnabled) {
        [FBSDKAppEvents activateApp];
    }
}

- (void)application:(UIApplication *)application didChangeStatusBarOrientation:(UIInterfaceOrientation)oldStatusBarOrientation
{
    [LEANSimulator didChangeStatusBarOrientation];
}

- (UIInterfaceOrientationMask)application:(UIApplication *)application
  supportedInterfaceOrientationsForWindow:(UIWindow *)window
{
    GoNativeScreenOrientation orientation = [GoNativeAppConfig sharedAppConfig].forceScreenOrientation;
    if (orientation == GoNativeScreenOrientationPortrait) {
        return UIInterfaceOrientationMaskPortrait;
    }
    else if (orientation == GoNativeScreenOrientationLandscape) {
        return UIInterfaceOrientationMaskLandscape;
    }
    else return UIInterfaceOrientationMaskAllButUpsideDown;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

- (BOOL)application:(UIApplication *)application continueUserActivity:(NSUserActivity *)userActivity restorationHandler:(void (^)(NSArray * _Nullable))restorationHandler
{
    if ([userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb]) {
        UIViewController *rvc = self.window.rootViewController;
        if ([rvc isKindOfClass:[LEANRootViewController class]]) {
            LEANRootViewController *vc = (LEANRootViewController*)rvc;
            [vc loadUrl:userActivity.webpageURL];
            return YES;
        }
    }
    
    return NO;
}
@end
