//
//  LFStreamClient.m
//  LFClient
//
//  Created by zjj on 1/14/13.
//
//  Copyright (c) 2013 Livefyre
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.

#import "LFStreamClient.h"

static NSString *_stream = @"stream";

static dispatch_queue_t _modify_pollingCollections_queue;
static dispatch_queue_t modify_pollingCollections_queue() {
    if (_modify_pollingCollections_queue == NULL) 
        _modify_pollingCollections_queue = dispatch_queue_create("com.livefyre.SDK.pollingCollectionsQueue", NULL);
    
    return _modify_pollingCollections_queue;
}

@interface LFStreamClient()
// TODO, dumber stream client, polling in client. Better testing.
@property (strong) NSMutableArray *pollingCollections;
@end

@implementation LFStreamClient
@synthesize pollingCollections = _pollingCollections;

- (NSMutableArray *)pollingCollections
{
    if (!_pollingCollections)
        _pollingCollections = [[NSMutableArray alloc] init];
    
    return _pollingCollections;
}

- (void)setPollingCollections:(NSMutableArray *)pollingCollections
{
    self.pollingCollections = pollingCollections;
}

- (void)startStreamForCollection:(NSString *)collectionId
                                   fromEvent:(NSString *)eventId
                                   onNetwork:(NSString *)networkDomain
                                     success:(void (^)(NSDictionary *))success
                                     failure:(void (^)(NSError *))failure
{
    if (!eventId || !collectionId || !networkDomain) {
        failure([NSError errorWithDomain:kLFError code:400u userInfo:[NSDictionary dictionaryWithObject:@"Lacking necessary parameters to start stream."
                                                                                                 forKey:NSLocalizedDescriptionKey]]);
        return;
    }
    
    dispatch_sync(modify_pollingCollections_queue(), ^{
        if (![self.pollingCollections containsObject:collectionId])
            [self.pollingCollections addObject:collectionId];
    });
    NSString *host = [NSString stringWithFormat:@"%@.%@", _stream, networkDomain];
    NSString *eventlessPath = [NSString stringWithFormat:@"/v3.0/collection/%@/", collectionId];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [self pollForCollection:collectionId fromEvent:eventId withHost:host withPartialPath:eventlessPath success:success failure:failure];;
    });    
}

- (void)pollForCollection:(NSString *)collectionId
                fromEvent:(NSString *)eventId
                 withHost:(NSString *)host
          withPartialPath:(NSString *)partialPath
                  success:(void (^)(NSDictionary *))success
                  failure:(void (^)(NSError *))failure
{
    __block BOOL isPolling = YES;
    dispatch_sync(modify_pollingCollections_queue(), ^{
        if (![self.pollingCollections containsObject:collectionId])
            isPolling = NO;
    });
    if (!isPolling)
        return;
    
    NSString *path = [NSString stringWithFormat:@"%@/%@/", partialPath, eventId];
    NSURL *connectionURL = [[NSURL alloc] initWithScheme:kLFSDKScheme host:host path:path];
    NSURLRequest *streamReq = [NSURLRequest requestWithURL:connectionURL cachePolicy:NSURLCacheStorageNotAllowed timeoutInterval:60.0];
    NSURLResponse *resp = nil;
    NSError *err = nil;
    
    NSData *data = [NSURLConnection sendSynchronousRequest:streamReq returningResponse:&resp error:&err];
    //wait
    NSDictionary *payload = [LFClientBase handleResponse:resp WithError:err WithData:data WithFailure:failure];
    if (payload && [payload objectForKey:@"data"]) {
        NSDictionary *newData = [payload objectForKey:@"data"];
        success(payload);
        
        //update the head event
        eventId = [newData objectForKey:@"maxEventId"];
    }
    
    //if (payload && [payload objectForKey:@"timeout"]);
    //keep polling
    //NSLog(@"Polling for collection:%@", collectionId);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [self pollForCollection:collectionId fromEvent:eventId withHost:host withPartialPath:partialPath success:success failure:failure];
    });
}

- (void)stopStreamForCollection:(NSString *)collectionId
{
    dispatch_async(modify_pollingCollections_queue(), ^{
        [self.pollingCollections removeObject:collectionId];
    });
}

- (NSArray *)getStreamingCollections
{
    return [NSArray arrayWithArray:self.pollingCollections];
}
@end
