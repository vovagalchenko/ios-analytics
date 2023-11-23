//
//  CommonAnalyticsInfo.h
//  iOS Analytics
//
//  Created by Vova Galchenko on 2/6/14.
//  Copyright (c) 2014 Vova Galchenko. All rights reserved.
//

#ifndef iOS_Analytics_CommonAnalyticsInfo_h
#define iOS_Analytics_CommonAnalyticsInfo_h

#include <sys/types.h>
#include <sys/sysctl.h>
#import <UIKit/UIKit.h>

#define INSTALLATION_ID_USER_DEFAULTS_KEY       @"installation_id"

static inline NSString *userTimeZone(void)
{
    [NSTimeZone resetSystemTimeZone];
    return [[NSTimeZone systemTimeZone] name];
}

static inline NSString *currentLanguage(void)
{
    NSArray *preferredLanguages = [NSLocale preferredLanguages];
    NSString *primaryLanguage = @"unknown_language";
    if ([preferredLanguages count] > 0)
    {
        primaryLanguage = preferredLanguages[0];
    }
    return primaryLanguage;
}

static inline NSString *modelId(void)
{
    NSString *model = @"";
    
    size_t size;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    char *machine = malloc(size);
    
    // check that machine was correctly allocated by malloc.
    if (machine != NULL)
    {
        sysctlbyname("hw.machine", machine, &size, NULL, 0);
        model = [NSString stringWithUTF8String:machine];
        free(machine);
    }
    
    return model;
}

static inline NSString *displayResolutionString(void)
{
    CGSize screenSizeInPoints = [[UIScreen mainScreen] bounds].size;
    CGFloat pixelsPerPoint = [[UIScreen mainScreen] scale];
    return [NSString stringWithFormat:@"%dx%d", (int) (screenSizeInPoints.width * pixelsPerPoint), (int) (screenSizeInPoints.height * pixelsPerPoint)];
}

static inline NSString *appInstallationId(void)
{
    NSString *installationId = [[NSUserDefaults standardUserDefaults] objectForKey:INSTALLATION_ID_USER_DEFAULTS_KEY];
    if (!installationId.length)
    {
        CFUUIDRef uuid = CFUUIDCreate(NULL);
        installationId = (NSString *)CFBridgingRelease(CFUUIDCreateString(NULL, uuid));
        CFRelease(uuid);
        [[NSUserDefaults standardUserDefaults] setObject:installationId forKey:INSTALLATION_ID_USER_DEFAULTS_KEY];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    return installationId;
}

static inline NSString *deviceIdForVendor(void)
{
    return [[[UIDevice currentDevice] identifierForVendor] UUIDString];
}

static inline NSString *userInterfaceIdiom(void)
{
    NSString *userInterfaceIdiom = @"unknown";
    switch (UI_USER_INTERFACE_IDIOM())
    {
        case UIUserInterfaceIdiomPad:
            userInterfaceIdiom = @"iPad";
            break;
        case UIUserInterfaceIdiomPhone:
            userInterfaceIdiom = @"iPhone";
            break;
        default:
            break;
    }
    return userInterfaceIdiom;
}

static inline NSString *appName(void) {
    return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifier"];
}

static inline NSDictionary *commonAttributes(void)
{
    return @{
             @"os" : [@"iOS " stringByAppendingString:[[UIDevice currentDevice] systemVersion]],
             @"user_locale" : [[NSLocale currentLocale] localeIdentifier],
             @"user_timezone" : userTimeZone(),
             @"user_language" : currentLanguage(),
             @"app_version" : [NSString stringWithFormat:@"%@:%@",
                               [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
                               [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]],
             @"platform" : @"iOS",
             @"analytics_version" : @"1",
             @"model_id" : modelId(),
             @"display_resolution" : displayResolutionString(),
             @"display_scale" : [NSString stringWithFormat:@"%.2f", [[UIScreen mainScreen] scale]],
             @"app_name" : [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifier"],
             @"installation_id" : appInstallationId(),
             @"device_id_for_vendor" : deviceIdForVendor(),
             @"device_name" : [[UIDevice currentDevice] name],
             @"user_interface_idiom" : userInterfaceIdiom()
             };
}

#endif
