//
//  Analytics.m
//  iOS Analytics
//
//  Created by Vova Galchenko on 2/6/14.
//  Copyright (c) 2014 Vova Galchenko. All rights reserved.
//

#import "Analytics.h"
#import "AnalyticsWriter.h"
#import "AnalyticsSender.h"
#import <UIKit/UIKit.h>
#import <stdatomic.h>

#define ANALYTICS_SESSION_ID_USER_DEFAULTS_KEY                      @"analytics_session_id"
#define ANALYTICS_DATE_OF_FIRST_EVENT_IN_SESSION_USER_DEFAULTS_KEY  @"analytics_first_date_in_session"
#define ANALYTICS_DATE_OF_LAST_EVENT_IN_SESSION_USER_DEFAULTS_KEY   @"analytics_last_date_in_session"
#define ANALYTICS_FIRST_SESSION_ID                                  (@1)
#define ANALYTICS_MAX_IDLE_TIME_IN_SESSION                          (30*60)

#define ANALYTICS_EVENT_NAME_KEY                                    @"event_name"
#define ANALYTICS_EVENT_TYPE_KEY                                    @"event_type"
#define ANALYTICS_SESSION_ID_KEY                                    @"session_id"



@interface Analytics()

- (void)persistSessionInformation;

@property (nonatomic, readwrite, strong) NSNumber *sessionId;
@property (nonatomic, readwrite, strong) NSDate *dateOfFirstEventInSession;
@property (nonatomic, readwrite, strong) NSDate *dateOfLastEventInSession;

@end

static Analytics *sharedInstance = nil;

#pragma mark - Crash Handlers

#include <execinfo.h>
#include <libkern/OSAtomic.h>
volatile atomic_int signalsCaught = 0;
const int32_t maxCaughtSignals = 10;

void exceptionHandler(NSException *exception) {
    NSString *eventName = nil;
    if([[UIApplication sharedApplication] applicationState] == UIApplicationStateActive)
    {
        eventName = @"uncaught_exception";
    }
    else
    {
        eventName = @"bg_uncaught_exception";
    }

    [sharedInstance logEventWithName:eventName type:AnalyticsEventTypeCrash attributes:@{
        @"exception_reason" : [exception reason],
        @"stack" : [exception callStackSymbols],
    }];
    [sharedInstance persistSessionInformation];
}

void handleSignal(int sig){
    int32_t exceptionCount = atomic_fetch_add(&signalsCaught, 1);
    if (exceptionCount > maxCaughtSignals)
        return;
    
    if(sig == SIGALRM && [[UIApplication sharedApplication] applicationState] == UIApplicationStateInactive)
    {
        [sharedInstance logEventWithName:@"sigalrm_in_bg" type:AnalyticsEventTypeCrash attributes:nil];
        return;
    }
    void *backtraceFrames[128];
    int frameCount = backtrace(backtraceFrames, 128);
    char **symbols = backtrace_symbols(backtraceFrames, frameCount);
    NSMutableArray *stackTrace = [NSMutableArray array];
    for(int i = 0; i < frameCount; i++)
    {
        [stackTrace addObject:[NSString stringWithFormat:@"%s", symbols[i]]];
    }
    free(symbols);
    
    [sharedInstance logEventWithName:@"signal_caught" type:AnalyticsEventTypeCrash attributes:@{
                                                                                                @"signal" : [NSNumber numberWithInt:sig],
                                                                                                @"signal_name" : [NSString stringWithFormat:@"%s", strsignal(sig)],
                                                                                                @"stack" : stackTrace,
                                                                                                }];
    [sharedInstance persistSessionInformation];
    exit(128+sig);
}

@implementation Analytics

#pragma mark - Singleton Management

+ (Analytics *)sharedInstance
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        sharedInstance = [[self alloc] init];
        
        NSSetUncaughtExceptionHandler(&exceptionHandler);
        signal(SIGABRT, handleSignal);
        signal(SIGILL, handleSignal);
        signal(SIGSEGV, handleSignal);
        signal(SIGFPE, handleSignal);
        signal(SIGBUS, handleSignal);
        signal(SIGPIPE, handleSignal);
        
        [sharedInstance sendAnalytics];
    });
    return sharedInstance;
}

static inline NSDate *getSpecialDateOrCurrent(NSString *specialDateUserDefaultsKey)
{
    NSDate *date = [[NSUserDefaults standardUserDefaults] objectForKey:specialDateUserDefaultsKey];
    if (!date)
    {
        date = [NSDate date];
    }
    return date;
}

- (id)init
{
    NSAssert(!sharedInstance, @"Never create an instance of Analytics directly. Use the singleton.");
    if ((self = [super init]))
    {
        self.sessionId = [[NSUserDefaults standardUserDefaults] objectForKey:ANALYTICS_SESSION_ID_USER_DEFAULTS_KEY];
        if (!self.sessionId)
        {
            self.sessionId = @1;
        }
        self.dateOfFirstEventInSession = getSpecialDateOrCurrent(ANALYTICS_DATE_OF_FIRST_EVENT_IN_SESSION_USER_DEFAULTS_KEY);
        self.dateOfLastEventInSession = getSpecialDateOrCurrent(ANALYTICS_DATE_OF_LAST_EVENT_IN_SESSION_USER_DEFAULTS_KEY);
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleDidEnterBackgroundNotification)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma - Public Interface Implementation

- (void)logEventWithName:(NSString *)eventName
                    type:(AnalyticsEventType)eventType
              attributes:(NSDictionary *)attributes
{
    NSAssert(eventName.length, @"Each analytics event must have a name.");
    [self addNewEventToSession];
    
    NSMutableDictionary *eventDictionary = [NSMutableDictionary dictionaryWithDictionary:attributes];
    [eventDictionary setObject:eventName forKey:ANALYTICS_EVENT_NAME_KEY];
#ifdef VG_ANALYTICS_DEBUG
    NSLog(@"<%@|%@> %@", eventTypeStringForEventType(eventType), eventName, eventDictionary);
#endif
    [eventDictionary setObject:eventTypeStringForEventType(eventType) forKey:ANALYTICS_EVENT_TYPE_KEY];
    [eventDictionary setObject:self.sessionId forKey:ANALYTICS_SESSION_ID_KEY];
    NSDictionary *supplementalDataFromDelegate = [self.delegate supplementalData];
    if (supplementalDataFromDelegate.count) {
        for (NSString *key in supplementalDataFromDelegate.allKeys) {
            if ([eventDictionary objectForKey:key]) {
                NSLog(@"WARNING: Your delegate is providing a value for key <%@> which will override the value set by the event", key);
            }
            [eventDictionary setObject:[supplementalDataFromDelegate objectForKey:key] forKey:key];
        }
    }
    [self write:eventDictionary];
}

- (void)sendAnalytics
{
    [[AnalyticsWriter sharedInstance] flushCurrentLogFile];
    [[AnalyticsSender sharedInstance] sendFlushedAnalytics];
}

#pragma mark - Session Management

- (void)addNewEventToSession
{
    @synchronized(self)
    {
        NSDate *newLastEventInSession = [NSDate date];
        if ([newLastEventInSession timeIntervalSinceDate:self.dateOfLastEventInSession] > ANALYTICS_MAX_IDLE_TIME_IN_SESSION)
        {
            // This session has ended
            NSTimeInterval sessionDuration = [self.dateOfLastEventInSession timeIntervalSinceDate:self.dateOfFirstEventInSession];
            // Write the end of the session
            NSDictionary *sessionInfo = @{
                                          ANALYTICS_EVENT_NAME_KEY : @"session_end",
                                          ANALYTICS_EVENT_TYPE_KEY : eventTypeStringForEventType(AnalyticsEventTypeAppLifecycle),
                                          @"duration" : [NSNumber numberWithDouble:sessionDuration],
                                          ANALYTICS_SESSION_ID_KEY : self.sessionId,
                                          };
            [self write:sessionInfo];
            self.dateOfFirstEventInSession = newLastEventInSession;
            self.dateOfLastEventInSession = newLastEventInSession;
            self.sessionId = [NSNumber numberWithUnsignedLongLong:[self.sessionId unsignedLongLongValue] + 1];
            [self persistSessionInformation];
            
            if ([self.delegate respondsToSelector:@selector(analyticsStartedNewSession)]) {
                [self.delegate analyticsStartedNewSession];
            }
        }
        self.dateOfLastEventInSession = newLastEventInSession;
    }
}

- (void)persistSessionInformation
{
    NSAssert(self.sessionId && self.dateOfLastEventInSession && self.dateOfFirstEventInSession,
             @"Attempting to persist analytics session information without having created it.");
    [[NSUserDefaults standardUserDefaults] setObject:self.sessionId forKey:ANALYTICS_SESSION_ID_USER_DEFAULTS_KEY];
    [[NSUserDefaults standardUserDefaults] setObject:self.dateOfFirstEventInSession forKey:ANALYTICS_DATE_OF_FIRST_EVENT_IN_SESSION_USER_DEFAULTS_KEY];
    [[NSUserDefaults standardUserDefaults] setObject:self.dateOfLastEventInSession forKey:ANALYTICS_DATE_OF_LAST_EVENT_IN_SESSION_USER_DEFAULTS_KEY];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - Event Handling

- (void)handleDidEnterBackgroundNotification
{
    [self persistSessionInformation];
    [self sendAnalytics];
}

#pragma mark - Writing To Local Files

- (void)write:(NSDictionary *)eventDictionary
{
    NSMutableDictionary *finalDictionary = [NSMutableDictionary dictionaryWithDictionary:eventDictionary];
    [finalDictionary setObject:[NSNumber numberWithInteger:(NSInteger)[[NSDate date] timeIntervalSince1970]] forKey:@"timestamp"];
    [[AnalyticsWriter sharedInstance] write:finalDictionary];
}

#pragma mark - Misc Helpers

static inline NSString *eventTypeStringForEventType(AnalyticsEventType eventType)
{
    NSString *eventTypeString = @"unknown_event_type";
    switch (eventType)
    {
        case AnalyticsEventTypeAppLifecycle:
            eventTypeString = @"app_lifecycle";
            break;
        case AnalyticsEventTypeCrash:
            eventTypeString = @"crash";
            break;
        case AnalyticsEventTypeDebug:
            eventTypeString = @"debug";
            break;
        case AnalyticsEventTypeNetwork:
            eventTypeString = @"network";
            break;
        case AnalyticsEventTypeWarning:
            eventTypeString = @"warning";
            break;
        case AnalyticsEventTypeIssue:
            eventTypeString = @"issue";
            break;
        case AnalyticsEventTypeUserAction:
            eventTypeString = @"user_action";
            break;
        case AnalyticsEventTypeViewChange:
            eventTypeString = @"view_change";
            break;
        default:
            NSCAssert(NO, @"Unknown event type.");
            break;
    }
    return eventTypeString;
}

@end
