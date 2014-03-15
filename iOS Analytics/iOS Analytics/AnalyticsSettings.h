//
//  AnalyticsSettings.h
//  iOS Analytics
//
//  Created by Vova Galchenko on 3/15/14.
//  Copyright (c) 2014 Vova Galchenko. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AnalyticsSettings : NSObject

+ (AnalyticsSettings *)sharedInstance;
@property (nonatomic, readonly) NSURL *analyticsPostURL;

@end
