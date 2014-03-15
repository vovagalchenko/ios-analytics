//
//  AnalyticsSettings.m
//  iOS Analytics
//
//  Created by Vova Galchenko on 3/15/14.
//  Copyright (c) 2014 Vova Galchenko. All rights reserved.
//

#import "AnalyticsSettings.h"

@interface AnalyticsSettings()

@property (nonatomic, readwrite, strong) NSURL *analyticsPostURL;

@end

@implementation AnalyticsSettings

static AnalyticsSettings *sharedInstance = nil;

#pragma mark - Singleton Management

+ (AnalyticsSettings *)sharedInstance
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (id)init
{
    NSAssert(!sharedInstance, @"Never create an instance of AnalyticsSettings directly. Use the singleton.");
    if (self = [super init])
    {
        NSDictionary *analyticsSettings = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"IANSettings"];
        NSAssert(analyticsSettings && [analyticsSettings isKindOfClass:[NSDictionary class]], @"You are missing the analytics settings dictionary under the 'IANSettings' key in your Info.plist");
        NSString *analyticsPostURLString = [analyticsSettings objectForKey:@"PostURL"];
        NSAssert(analyticsPostURLString.length, @"You are missing the URL to post analytics to under the 'PostURL' key of your analytics settings dictionary in your Info.plist");
        self.analyticsPostURL = [NSURL URLWithString:analyticsPostURLString];
    }
    return sharedInstance;
}

@end
