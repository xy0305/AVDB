#import "AVDB115HttpIntercept.h"
#import "AVDB115MagnetJSON.h"
#import <objc/runtime.h>

static BOOL gInstalled = NO;

static void AVDB115Swizzle(Class cls, SEL original, SEL replacement) {
    if (!cls) return;
    Method originalMethod = class_getInstanceMethod(cls, original);
    Method swizzledMethod = class_getInstanceMethod(cls, replacement);
    if (!originalMethod || !swizzledMethod) return;
    if (class_addMethod(cls, original, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod))) {
        class_replaceMethod(cls, replacement, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}

static void AVDB115IngestResponse(NSURL *url, NSData *data) {
    if (data.length == 0) return;
    // Only parse bodies for the magnet-list path the app already requested.
    // Never start a new getMovieMagnets / signed request.
    if (url && ![AVDB115MagnetJSON isMagnetListURL:url]) {
        // Some cache files / stripped URLResponses may lose the path; only
        // fall through when the body itself clearly looks like magnet JSON.
        NSString *probe = [[NSString alloc] initWithBytes:data.bytes
                                                   length:MIN((NSUInteger)128, data.length)
                                                 encoding:NSUTF8StringEncoding];
        if (![probe containsString:@"\"hash\""] && ![probe.lowercaseString containsString:@"ed2k://"]) {
            return;
        }
        if (![probe containsString:@"\"name\""] && ![probe containsString:@"\"type\""]) return;
    }
    NSUInteger n = [AVDB115MagnetJSON ingestData:data url:url catalogHint:nil];
    if (n) [AVDB115MagnetJSON addHttpCaptureCount:n];
}

@interface AVDB115MagnetURLProtocol : NSURLProtocol <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDataTask *task;
@property (nonatomic, strong) NSMutableData *buf;
@property (nonatomic, strong) NSURLResponse *resp;
@end

@implementation AVDB115MagnetURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([NSURLProtocol propertyForKey:@"AVDB115MagnetURLProtocol" inRequest:request]) return NO;
    return [AVDB115MagnetJSON isMagnetListURL:request.URL];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSMutableURLRequest *req = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"AVDB115MagnetURLProtocol" inRequest:req];
    self.buf = [NSMutableData data];
    NSURLSession *s = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration
                                                    delegate:self
                                               delegateQueue:nil];
    self.session = s;
    self.task = [s dataTaskWithRequest:req];
    [self.task resume];
}

- (void)stopLoading {
    [self.task cancel];
    self.task = nil;
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    self.resp = response;
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    if (completionHandler) completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    if (data.length) [self.buf appendData:data];
    [self.client URLProtocol:self didLoadData:data];
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    if (error) {
        [self.client URLProtocol:self didFailWithError:error];
    } else {
        AVDB115IngestResponse(self.resp.URL ?: task.currentRequest.URL ?: self.request.URL, self.buf);
        [self.client URLProtocolDidFinishLoading:self];
    }
    [session finishTasksAndInvalidate];
}

@end

@implementation NSURLSession (AVDB115HttpIntercept)

- (NSURLSessionDataTask *)avdb115_harvest_dataTaskWithRequest:(NSURLRequest *)request
                                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (!err && data.length) {
            AVDB115IngestResponse(resp.URL ?: request.URL, data);
        }
        if (completionHandler) completionHandler(data, resp, err);
    };
    // Calls the previous IMP (ad-block swizzle or the real method) via exchange.
    return [self avdb115_harvest_dataTaskWithRequest:request completionHandler:wrapped];
}

@end

@implementation AVDB115HttpIntercept

+ (BOOL)isInstalled { return gInstalled; }

+ (void)install {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        @try {
            AVDB115Swizzle(NSURLSession.class,
                           @selector(dataTaskWithRequest:completionHandler:),
                           @selector(avdb115_harvest_dataTaskWithRequest:completionHandler:));
            [AVDB115MagnetJSON setURLSessionHookInstalled:YES];
            gInstalled = YES;
        } @catch (NSException *ex) {
            [AVDB115MagnetJSON setURLSessionHookInstalled:NO];
        }
        @try {
            BOOL ok = [NSURLProtocol registerClass:AVDB115MagnetURLProtocol.class];
            [AVDB115MagnetJSON setURLProtocolRegistered:ok];
            if (ok) gInstalled = YES;
        } @catch (NSException *ex) {
            [AVDB115MagnetJSON setURLProtocolRegistered:NO];
        }
        NSLog(@"[AVDB115] HTTP intercept installed=%d (NSURLSession / NSURLProtocol; dart:io TLS may be invisible)", (int)gInstalled);
    });
}

@end
