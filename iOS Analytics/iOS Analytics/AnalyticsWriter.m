//
//  AnalyticsWriter.m
//  iOS Analytics
//
//  Created by Vova Galchenko on 2/6/14.
//  Copyright (c) 2014 Vova Galchenko. All rights reserved.
//

#import "AnalyticsWriter.h"
#import "CommonAnalyticsInfo.h"
#import "AnalyticsHelpers.h"

@implementation AnalyticsWriter

static AnalyticsWriter *sharedInstance = nil;

#pragma mark - Singleton Management

+ (AnalyticsWriter *)sharedInstance
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
    NSAssert(!sharedInstance, @"Use the AnalyticsWriter singleton!");
    if ((self = [super init]))
    {
        // Set up the analytics directory structure, if it hasn't been already
        BOOL isDir = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:logsToSendDirectoryPath() isDirectory:&isDir] || !isDir)
        {
            NSAssert(!isDir, @"The analytics framework needs %@. Give it back!", logsToSendDirectoryPath());
            NSError *error = nil;
            [[NSFileManager defaultManager] createDirectoryAtPath:logsToSendDirectoryPath()
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&error];
            NSAssert(error == nil, @"Unable to create the analytics directory.");
            if (error)
            {
                self = nil;
            }
        }
    }
    return self;
}

#pragma mark - Public Interface Implementation

- (void)write:(NSDictionary *)eventDictionary
{
    BOOL thisEventIsFirst = NO;
    NSOutputStream *currentLogFileStream = [self initializedCurrentLogFileStreamCreatingNewFileIfNecessary:YES
                                                                                            newFileCreated:&thisEventIsFirst];
    if (!currentLogFileStream)
    {
        NSAssert(NO, @"Unable to get an output stream to the current log file. Will proceed without logging.");
        return;
    }
    
    NSMutableData *eventData = [NSMutableData data];
    if (!thisEventIsFirst)
    {
        eventData = [NSMutableData dataWithBytes:"," length:1];
    }
    
    NSError *error = nil;
    NSData *eventMeatData = nil;
    @try
    {
        eventMeatData = [NSJSONSerialization dataWithJSONObject:eventDictionary
                                                        options:0
                                                          error:&error];
    }
    @catch (NSException *exception)
    {
        NSLog(@"Failed to serialize analytics event: %@", exception);
        return;
    }
    
    if (error)
    {
        NSAssert(NO, @"Unable to serialize event dictionary.");
        return;
    }
    [eventData appendData:eventMeatData];
    unsigned long long fileSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:currentLogFilePath()
                                                                                    error:nil] fileSize];
    if (eventData.length + fileSize >= ANALYTICS_ROUGH_LOG_FILE_SIZE_CAP)
    {
        [self flushCurrentLogFile];
        if (eventData.length < ANALYTICS_ROUGH_LOG_FILE_SIZE_CAP)
        {
            [self write:eventDictionary];
        }
        else
        {
            NSAssert(NO, @"Event data length exceeds the analytics log file size cap.");
        }
        return;
    }
    NSUInteger numBytesWritten = [currentLogFileStream write:eventData.bytes maxLength:eventData.length];
    if (numBytesWritten != eventData.length)
    {
        // The write failed and possibly corrupted the log file.
        [[NSFileManager defaultManager] removeItemAtPath:currentLogFilePath()
                                                   error:nil];
        [currentLogFileStream close];
        NSAssert(NO, @"Failed to write log event to current log file. Log file was possibly corrupted and deleted.");
    }
}

#pragma mark - Misc. Helpers

- (NSOutputStream *)initializedCurrentLogFileStreamCreatingNewFileIfNecessary:(BOOL)createNewFileIfNecessary newFileCreated:(BOOL *)logFileWasCreated
{
    @synchronized(self)
    {
        BOOL isDir = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:currentLogFilePath()
                                                  isDirectory:&isDir] && createNewFileIfNecessary)
        {
            NSError *error = nil;
            NSData *eventGroupData = [NSJSONSerialization dataWithJSONObject:commonAttributes()
                                                                     options:0
                                                                       error:&error];
            if (error)
            {
                NSAssert(error == nil, @"Unable to serialize event group attributes.");
                return nil;
            }
            NSMutableString *fileInitialContents = [[NSMutableString alloc] initWithBytes:eventGroupData.bytes
                                                                                   length:eventGroupData.length
                                                                                 encoding:NSUTF8StringEncoding];
            [fileInitialContents deleteCharactersInRange:NSMakeRange(fileInitialContents.length - 1, 1)];
            [fileInitialContents appendString:@",\"events\":["];
            NSData *dataToStartWith = [fileInitialContents dataUsingEncoding:NSUTF8StringEncoding];
            if (![[NSFileManager defaultManager] createFileAtPath:currentLogFilePath()
                                                         contents:dataToStartWith
                                                       attributes:@{NSFileProtectionKey : NSFileProtectionCompleteUnlessOpen}])
            {
                NSAssert(NO, @"Unable to initialize log file at path: %@", currentLogFilePath());
                return nil;
            }
            else if (logFileWasCreated != nil)
            {
                *logFileWasCreated = YES;
            }
        }
        else if (isDir)
        {
            NSAssert(NO, @"There is a directory where the current log file should be.");
            if (logFileWasCreated != nil)
            {
                *logFileWasCreated = NO;
            }
            return nil;
        }
        else if (logFileWasCreated != nil)
        {
            *logFileWasCreated = NO;
        }
        NSOutputStream *currentLogFileStream = nil;
        if ([[NSFileManager defaultManager] fileExistsAtPath:currentLogFilePath()
                                                 isDirectory:nil])
        {
            currentLogFileStream = [[NSOutputStream alloc] initWithURL:[NSURL fileURLWithPath:currentLogFilePath()]
                                         append:YES];
            [currentLogFileStream open];
        }
        return currentLogFileStream;
    }
}

- (void)flushCurrentLogFile
{
    @synchronized(self)
    {
        NSOutputStream *currentLogStream = [self initializedCurrentLogFileStreamCreatingNewFileIfNecessary:NO newFileCreated:nil];
        if (currentLogStream)
        {
            // There's some data to flush
            NSData *logFileEndCapData = [NSData dataWithBytes:"]}" length:2];
            NSUInteger numBytesWritten = [currentLogStream write:logFileEndCapData.bytes maxLength:logFileEndCapData.length];
            [currentLogStream close];
            if (numBytesWritten == logFileEndCapData.length)
            {
                NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
                NSString *flushedLogFileName = [NSString stringWithFormat:@"%llu", (unsigned long long)(now*1000000)];
                NSError *error = nil;
                [[NSFileManager defaultManager] moveItemAtPath:currentLogFilePath()
                                                        toPath:[logsToSendDirectoryPath() stringByAppendingPathComponent:flushedLogFileName]
                                                         error:&error];
                if (error)
                {
                    NSAssert(NO, @"Unable to move the current log file to the logs to send directory: %@", error);
                }
            }
            else
            {
                [[NSFileManager defaultManager] removeItemAtPath:currentLogFilePath() error:nil];
                NSLog(@"Failed to cap off the current log file with the ending JSON. The current log file got deleted.");
            }
        }
    }
}

@end
