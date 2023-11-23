//
//  AnalyticsSender.m
//  iOS Analytics
//
//  Created by Vova Galchenko on 2/6/14.
//  Copyright (c) 2014 Vova Galchenko. All rights reserved.
//

#import "AnalyticsSender.h"
#import <libkern/OSAtomic.h>
#import "AnalyticsHelpers.h"
#import "CommonAnalyticsInfo.h"
#import "Analytics.h"
#import "AnalyticsSettings.h"
#import "zlib.h"

#define BUFFER_SIZE             (1<<15)     // 32 KB
#define ANALYTICS_POST_TIMEOUT  10.0

@interface AnalyticsSender()

@property (nonatomic, readwrite, assign) BOOL isSending;
@property (nonatomic, readwrite, strong) NSInputStream *currentLogFileStream;
@property (nonatomic, readwrite, strong) NSArray *logFiles;
@property (nonatomic, readwrite, assign) NSUInteger currentLogFileIndex;

@end

@implementation AnalyticsSender

#pragma mark - Singleton Management

static AnalyticsSender *sharedInstance = nil;

+ (AnalyticsSender *)sharedInstance
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
    NSAssert(!sharedInstance, @"Use the AnalyticsSender singleton!");
    if ((self = [super init]))
    {
    }
    return self;
}

#pragma mark - Public Interface Implementation

- (void)sendFlushedAnalytics
{
    @synchronized(self)
    {
        if (self.isSending)
        {
            return;
        }
        else
        {
            self.isSending = YES;
        }
    }
    
    NSError *error = nil;
    NSArray *allLogsToSend = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL fileURLWithPath:logsToSendDirectoryPath()]
                                                           includingPropertiesForKeys:nil
                                                                              options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                error:&error];
    if (error)
    {
        if (![error.domain isEqualToString:NSCocoaErrorDomain] || error.code != NSFileReadNoSuchFileError) {
            // No sense in printing out No Such File errors. That's normal behavior if the logs to send directory has not been created.
            NSLog(@"Unable to list contents of directory at path %@: %@", logsToSendDirectoryPath(), error);
        }
        self.isSending = NO;
        return;
    }
    
    // We'll be sending the logs in chronological order.
    NSMutableArray *sortedAllLogsToSend = [NSMutableArray arrayWithArray:allLogsToSend];
    [sortedAllLogsToSend sortUsingComparator:^(id obj1, id obj2) {
        NSURL *url1 = (NSURL *)obj1;
        NSURL *url2 = (NSURL *)obj2;
        NSString *filename1 = [url1 lastPathComponent];
        NSString *filename2 = [url2 lastPathComponent];
        return [filename1 compare:filename2];
    }];
    
    // Don't send too much out at once.
    NSMutableArray *logsToSend = [NSMutableArray array];
    NSUInteger toSend = 0;
    for (NSURL *fileURL in sortedAllLogsToSend)
    {
        unsigned long long fileSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:fileURL.path error:nil] fileSize];
        if (fileSize > ANALYTICS_ROUGH_LOG_FILE_SIZE_CAP)
        {
            [[NSFileManager defaultManager] removeItemAtPath:fileURL.path error:nil];
            NSAssert(NO, @"Attempted to send out a file larger than the log file size cap. This shouldn't ever happen.");
            continue;
        }
        
        if (toSend + fileSize > ANALYTICS_ROUGH_LOG_FILE_SIZE_CAP) break;
        
        [logsToSend addObject:fileURL];
        toSend += fileSize;
    }
    
    if (logsToSend.count > 0)
    {
        __weak AnalyticsSender *me = self;
        // Since we're going to be doing the sending in the background, have to begin a background task.
        __block UIBackgroundTaskIdentifier taskId = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^
        {
            me.isSending = NO;
            [[UIApplication sharedApplication] endBackgroundTask:taskId];
        }];
        
        long long contentLength = [self zipLogs:logsToSend toFileURL:[NSURL fileURLWithPath:zippedAnalyticsFilePath()]];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[[AnalyticsSettings sharedInstance] analyticsPostURL]
                                                               cachePolicy:NSURLRequestReloadIgnoringCacheData
                                                           timeoutInterval:ANALYTICS_POST_TIMEOUT];
        [request setHTTPMethod:@"POST"];
        [request setHTTPBodyStream:[NSInputStream inputStreamWithURL:[NSURL fileURLWithPath:zippedAnalyticsFilePath()]]];
        [request setValue:@"gzip" forHTTPHeaderField:@"Content-Encoding"];
        [request setValue:[@(contentLength) stringValue] forHTTPHeaderField:@"Content-Length"];
        [request setValue:[NSString stringWithFormat:@"iOS %@", appInstallationId()] forHTTPHeaderField:@"User-Agent"];
        [request setValue:appName() forHTTPHeaderField:@"Referer"];
        NSURLSession *session = [NSURLSession sharedSession];
        [[session dataTaskWithRequest:request
                    completionHandler:^(NSData * data, NSURLResponse * response, NSError * connectionError) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if ([httpResponse statusCode] == 204)
            {
        #ifdef VG_ANALYTICS_DEBUG
                NSLog(@"Sent analytics. Deleting local logs.");
        #endif
                for (NSURL *sentLogFile in logsToSend)
                {
                    [[NSFileManager defaultManager] removeItemAtURL:sentLogFile error:nil];
                }
            }
            else
            {
                NSLog(@"Failed sending analytics: %d\n%@\n%@", (int)[httpResponse statusCode], [httpResponse allHeaderFields], connectionError);
                if (connectionError)
                {
                    [[Analytics sharedInstance] logEventWithName:@"analytics_send_fail" type:AnalyticsEventTypeWarning attributes:errorInfo(connectionError)];
                }
                else
                {
                    [[Analytics sharedInstance] logEventWithName:@"analytics_send_fail" type:AnalyticsEventTypeWarning attributes:[httpResponse allHeaderFields]];
                }
            }
            me.isSending = NO;
            [[UIApplication sharedApplication] endBackgroundTask:taskId];
        }] resume];
    }
    else
    {
        self.isSending = NO;
    }
}

#pragma mark - Misc. Helpers

- (long long)zipLogs:(NSArray *)logsToZip toFileURL:(NSURL *)fileURLToZipTo
{
    self.logFiles = logsToZip;
    self.currentLogFileIndex = 0;
    z_stream zippedStream; // This struct represents the stream of zipped data that's being produced
    bzero(&zippedStream, sizeof(z_stream));
    zippedStream.data_type = Z_TEXT;
    
    int status = deflateInit2(
                              &zippedStream,        /* stream */
                              Z_BEST_COMPRESSION,    /* compression level */
                              Z_DEFLATED,            /* method: only Z_DEFLATED is allowed */
                              (15 + 16),            /* windowBits */
                              8,                    /* mem. level: 8 is default */
                              Z_DEFAULT_STRATEGY    /* strategy */
                              );
    if (status != Z_OK)
    {
        NSAssert(NO, @"Unable to initialize the deflator using deflateInit(): %d", status);
        return -1;
    }
    
    uint8_t uncompressedDataBuffer[BUFFER_SIZE];
    // The buffer size for compressed output oddly needs to be larger than input.
    // Documentation says it needs to be 0.1% plus 12 bytes larger than input.
    unsigned long compressedDataBufferLength = ceil(BUFFER_SIZE * 1.001) + 12;
    Bytef compressedDataBuffer[compressedDataBufferLength];
    
    NSOutputStream *zippedLogsOutputStream = [[NSOutputStream alloc] initWithURL:fileURLToZipTo append:NO];
    if (!zippedLogsOutputStream)
    {
        NSAssert(NO, @"Unable to open output stream to file: %@", fileURLToZipTo);
        return -1;
    }
    [zippedLogsOutputStream open];
    
    int numBytesRead = 0;
    long long contentLength = 0;
    do
    {
        BOOL lastChunk = NO;
        numBytesRead = [self fillBuffer:uncompressedDataBuffer lastChunk:&lastChunk];
        if (numBytesRead < 0)
        {
            [zippedLogsOutputStream close];
            NSAssert(NO, @"Error attempting to fill the uncompressed data buffer");
            return -1;
        }

        // The buffer is filled. We'll zip what's in the buffer and write it to the output stream.
        zippedStream.next_in = uncompressedDataBuffer;
        zippedStream.avail_in = numBytesRead;
        // If we're compressing the last chunk use Z_FINISH, otherwise don't flush.
        int flush = (lastChunk)? Z_FINISH : Z_SYNC_FLUSH;
        do
        {
            bzero(compressedDataBuffer, compressedDataBufferLength);
            zippedStream.next_out = compressedDataBuffer;
            zippedStream.avail_out = (uInt) compressedDataBufferLength;
            status = deflate(&zippedStream, flush);
            NSInteger numCompressedBytesToWrite = compressedDataBufferLength - zippedStream.avail_out;
            if (numCompressedBytesToWrite > 0)
            {
                NSInteger bytesWritten = [zippedLogsOutputStream write:compressedDataBuffer maxLength:numCompressedBytesToWrite];
                if (bytesWritten != numCompressedBytesToWrite)
                {
                    deflateEnd(&zippedStream);
                    NSAssert(NO, @"Error writing to the output stream: %@", zippedLogsOutputStream.streamError);
                    [zippedLogsOutputStream close];
                    return -1;
                }
                contentLength += bytesWritten;
            }
        }
        // If avail_out != 0, we might still have data left in the compressedDataBuffer and need to flush more output out.
        while (zippedStream.avail_out == 0);
        
        if (status != Z_STREAM_END && status != Z_OK)
        {
            NSAssert(NO, @"libz error: %d (avail_in = %d; avail_out = %d)", status, zippedStream.avail_in, zippedStream.avail_out);
            deflateEnd(&zippedStream);
            [zippedLogsOutputStream close];
            zippedLogsOutputStream = nil;
            return -1;
        }
    }
    while (numBytesRead == BUFFER_SIZE);
    // If avail_out != 0, we might still have some data left in compressedDataBuffer and still need to flush more output out.
    
    deflateEnd(&zippedStream);
    [zippedLogsOutputStream close];
    return contentLength;
}

- (int)fillBuffer:(uint8_t *)buffer lastChunk:(BOOL *)lastChunk
{
    
    return [self fillBuffer:buffer numBytesAlreadyRead:0 lastChunk:lastChunk];
}

- (unsigned int)fillBuffer:(uint8_t *)buffer numBytesAlreadyRead:(unsigned int)numBytesRead lastChunk:(BOOL *)lastChunk
{
    if (lastChunk != NULL)
    {
        *lastChunk = NO;
    }
    if (!self.currentLogFileStream)
    {
        if (self.currentLogFileIndex >= self.logFiles.count)
        {
            // Append a closing bracket.
            buffer[numBytesRead++] = ']';
            if (lastChunk != NULL)
            {
                *lastChunk = YES;
            }
            return numBytesRead;
        }
        self.currentLogFileStream = [NSInputStream inputStreamWithURL:self.logFiles[self.currentLogFileIndex]];
        if (!self.currentLogFileStream)
        {
            NSAssert(NO, @"Unable to open stream to a log file at url: %@", self.logFiles[self.currentLogFileIndex]);
            return -1;
        }
        char logFileDelimitter = (self.currentLogFileIndex == 0)? '[' : ',';
        buffer[numBytesRead++] = logFileDelimitter;
        if (numBytesRead == BUFFER_SIZE)
        {
            // The buffer is filled.
            return numBytesRead;
        }
        self.currentLogFileIndex++;
        [self.currentLogFileStream open];
    }
    
    NSInteger numBytesToRead = BUFFER_SIZE - numBytesRead;
    NSInteger numBytesReadThisTime = [self.currentLogFileStream read:(buffer + numBytesRead) maxLength:numBytesToRead];
    if (numBytesReadThisTime < 0) {
        return (unsigned int) numBytesReadThisTime;
    }
    
    if (numBytesReadThisTime < numBytesToRead)
    {
        // Done with the file
        [self.currentLogFileStream close];
        self.currentLogFileStream = nil;
    }
    numBytesRead += numBytesReadThisTime;
    
    if (numBytesRead == BUFFER_SIZE)
    {
        // We're done filling up the buffer
        return numBytesRead;
    }
    else if (numBytesRead < BUFFER_SIZE)
    {
        // Have to continue filling up the buffer
        return [self fillBuffer:buffer numBytesAlreadyRead:numBytesRead lastChunk:lastChunk];
    }
    else
    {
        // This is a bogus situation.
        NSAssert(NO, @"Overfilled the uncompressed data buffer.");
        return -1;
    }
}

@end
