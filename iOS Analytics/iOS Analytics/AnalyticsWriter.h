//
//  AnalyticsWriter.h
//  iOS Analytics
//
//  Created by Vova Galchenko on 2/6/14.
//  Copyright (c) 2014 Vova Galchenko. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AnalyticsWriter : NSObject

+ (AnalyticsWriter *)sharedInstance;
- (void)write:(NSDictionary *)eventDictionary;
- (void)flushCurrentLogFile;

@end
