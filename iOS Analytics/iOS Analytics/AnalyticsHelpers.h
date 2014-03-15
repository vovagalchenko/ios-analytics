//
//  AnalyticsHelpers.h
//  iOS Analytics
//
//  Created by Vova Galchenko on 2/6/14.
//  Copyright (c) 2014 Vova Galchenko. All rights reserved.
//

#ifndef iOS_Analytics_AnalyticsHelpers_h
#define iOS_Analytics_AnalyticsHelpers_h

#define ANALYTICS_ROUGH_LOG_FILE_SIZE_CAP       (1<<20) // 1 MB

static inline NSString *rootAnalyticsDirectoryPath()
{
    NSURL *documentsDirectory = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    return [[documentsDirectory path] stringByAppendingPathComponent:@"analytics"];
}

static inline NSString *currentLogFilePath()
{
    return [rootAnalyticsDirectoryPath() stringByAppendingPathComponent:@"current_log"];
}

static inline NSString *logsToSendDirectoryPath()
{
    return [rootAnalyticsDirectoryPath() stringByAppendingPathComponent:@"logs_to_send"];
}

static inline NSString *zippedAnalyticsFilePath()
{
    return [rootAnalyticsDirectoryPath() stringByAppendingPathComponent:@"zipped_logs"];
}

static inline NSDictionary *errorInfo(NSError *error)
{
    return @{
             @"error_code" : [NSNumber numberWithInteger:error.code],
             @"error_domain" : error.domain,
             @"error_description" : error.localizedDescription,
             @"error_info" : [error.userInfo description],
             };
}

#endif
