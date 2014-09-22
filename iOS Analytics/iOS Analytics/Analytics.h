//
//  Analytics.h
//  iOS Analytics
//
//  Created by Vova Galchenko on 2/6/14.
//  Copyright (c) 2014 Vova Galchenko. All rights reserved.
//

#import <Foundation/Foundation.h>

#define ANALYTICS   [Analytics sharedInstance]

typedef enum AnalyticsEventType
{
    AnalyticsEventTypeUserAction = 1,
    AnalyticsEventTypeViewChange,
    AnalyticsEventTypeAppLifecycle,
    AnalyticsEventTypeDebug,
    AnalyticsEventTypeNetwork,
    AnalyticsEventTypeWarning,
    AnalyticsEventTypeIssue,
    AnalyticsEventTypeCrash,
} AnalyticsEventType;

@interface Analytics : NSObject

+ (Analytics *)sharedInstance;
- (void)logEventWithName:(NSString *)eventName
                    type:(AnalyticsEventType)eventType
              attributes:(NSDictionary *)attributes;
- (void)sendAnalytics;

@end

static inline void logEvent(NSString *eventName, AnalyticsEventType eventType, NSDictionary *eventAttributes)
{
    [[Analytics sharedInstance] logEventWithName:eventName
                                            type:eventType
                                      attributes:eventAttributes];
}

static inline void logUserAction(NSString *eventName, NSDictionary *eventAttributes)
{
    logEvent(eventName, AnalyticsEventTypeUserAction, eventAttributes);
}

static inline void logAppLifecycleEvent(NSString *eventName, NSDictionary *eventAttributes)
{
    logEvent(eventName, AnalyticsEventTypeAppLifecycle, eventAttributes);
}

static inline void logDebug(NSString *eventName, NSDictionary *eventAttributes)
{
    logEvent(eventName, AnalyticsEventTypeDebug, eventAttributes);
}

static inline void logNetworkEvent(NSString *eventName, NSDictionary *attrs)
{
    logEvent(eventName, AnalyticsEventTypeNetwork, attrs);
}

static inline void logWarning(NSString *eventName, NSDictionary *attrs)
{
    logEvent(eventName, AnalyticsEventTypeWarning, attrs);
}

static inline void logIssue(NSString *eventName, NSDictionary *eventAttributes)
{
    logEvent(eventName, AnalyticsEventTypeIssue, eventAttributes);
}

static inline void logViewChange(NSString *eventName, NSDictionary *eventAttributes)
{
    logEvent(eventName, AnalyticsEventTypeViewChange, eventAttributes);
}

static inline void logCrash(NSString *eventName, NSDictionary *eventAttributes)
{
    logEvent(eventName, AnalyticsEventTypeCrash, eventAttributes);
}
