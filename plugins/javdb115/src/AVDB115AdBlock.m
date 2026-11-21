#import "AVDB115AdBlock.h"
#import <objc/runtime.h>
#import <WebKit/WebKit.h>

static NSString *const kBlockAdsKey = @"avdb115.settings.blockAds";

@implementation AVDB115AdBlockSettings

+ (AVDB115AdBlockSettings *)shared {
    static AVDB115AdBlockSettings *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[AVDB115AdBlockSettings alloc] init]; });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
        _enabled = [d objectForKey:kBlockAdsKey] == nil ? YES : [d boolForKey:kBlockAdsKey];
    }
    return self;
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:kBlockAdsKey];
}

- (NSString *)status {
    if (!self.enabled) {
        return @"广告拦截已关闭。";
    }
    return @"已拦截可识别的原生广告请求（/api/v1/ads、/api/v1/ads/splash_log，仅 jdforrepam.com / letidi.com）。启动后短时间内会尝试通过 FlutterEngine ensureSemanticsEnabled 激活开屏广告上可识别的「跳过」按钮，不会跳过 SplashPage 的域名探测/更新检查/本机认证，也不会清空首屏。未经真机验证，不能声称开屏广告已被移除。未发现 AdMob、Unity、穿山甲/Pangle、广点通等第三方 SDK。首页/磁力页广告仍由 Flutter Dart Dio 绘制，走 dart:io TLS，原生层通常看不到，因此不能声称已屏蔽全部广告。不会修改会员或支付接口。";
}

@end

@implementation AVDB115AdBlockPolicy

+ (NSSet<NSString *> *)adAPIHosts {
    return [NSSet setWithArray:@[
        @"jdforrepam.com",
        @"www.jdforrepam.com",
        @"staging.letidi.com",
        @"letidi.com",
        @"www.letidi.com",
    ]];
}

+ (BOOL)host:(NSString *)host matches:(NSSet<NSString *> *)allowed {
    host = host.lowercaseString;
    if ([allowed containsObject:host]) return YES;
    for (NSString *base in allowed) {
        if ([host hasSuffix:[@"." stringByAppendingString:base]]) return YES;
    }
    return NO;
}

+ (BOOL)isAdRequestURLObject:(NSURL *)url {
    if (!url) return NO;
    NSString *scheme = url.scheme.lowercaseString;
    if (![scheme isEqualToString:@"https"] && ![scheme isEqualToString:@"http"]) return NO;
    if (![self host:url.host matches:[self adAPIHosts]]) return NO;
    NSString *path = url.path ?: @"";
    if ([path isEqualToString:@"/api/v1/ads"]) return YES;
    if ([path hasPrefix:@"/api/v1/ads/"]) return YES;
    return NO;
}

+ (BOOL)isAdRequestURL:(NSString *)urlString {
    if (urlString.length == 0) return NO;
    return [self isAdRequestURLObject:[NSURL URLWithString:urlString]];
}

+ (BOOL)isProtectedURL:(NSString *)urlString {
    if (urlString.length == 0) return NO;
    NSURL *url = [NSURL URLWithString:urlString];
    NSString *host = url.host.lowercaseString ?: @"";
    NSString *path = url.path ?: @"";
    // Payment / membership / auth — never block.
    if ([path hasPrefix:@"/api/v1/auth"] || [path hasPrefix:@"/api/v1/sessions"] ||
        [path hasPrefix:@"/api/v1/wallets"] || [path hasPrefix:@"/api/v2/plans"] ||
        [path hasPrefix:@"/api/v3/plans"] || [path hasPrefix:@"/api/v4/plans"] ||
        [path hasPrefix:@"/api/v2/plans/"] || [path hasPrefix:@"/api/v3/plans/"] ||
        [path hasPrefix:@"/api/v4/plans/"]) {
        return YES;
    }
    // Normal JavDB APIs and cover/playback/HQ sources.
    if ([path hasPrefix:@"/api/v1/movies"] || [path hasPrefix:@"/api/v2/movies"] ||
        [path hasPrefix:@"/api/v4/movies"] || [path hasPrefix:@"/api/v1/search"] ||
        [path hasPrefix:@"/api/v2/search"] || [path hasPrefix:@"/api/v1/advanced_search"] ||
        [path hasPrefix:@"/api/v1/startup"] || [path hasPrefix:@"/api/v1/magnet"]) {
        return YES;
    }
    if ([host hasSuffix:@"jdbstatic.com"] || [host isEqualToString:@"jdbstatic.com"]) return YES;
    if ([host hasSuffix:@"dmm.co.jp"] || [host hasSuffix:@"mgstage.com"] ||
        [host hasSuffix:@"avbase.net"] || [host hasSuffix:@"javbus.com"] ||
        [host hasSuffix:@"115.com"] || [host hasSuffix:@"anxia.com"] ||
        [host hasSuffix:@"115cdn.net"]) {
        return YES;
    }
    return NO;
}

+ (BOOL)shouldBlockURL:(NSURL *)url {
    if (!AVDB115AdBlockSettings.shared.enabled) return NO;
    if ([self isProtectedURL:url.absoluteString]) return NO;
    return [self isAdRequestURLObject:url];
}

+ (void)swizzle:(Class)cls sel:(SEL)orig with:(SEL)rep {
    if (!cls) return;
    Method a = class_getInstanceMethod(cls, orig);
    Method b = class_getInstanceMethod(cls, rep);
    if (!a || !b) return;
    method_exchangeImplementations(a, b);
}

+ (void)installNativeHooks {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [self swizzle:NSURLSession.class sel:@selector(dataTaskWithRequest:) with:@selector(avdb115_dataTaskWithRequest:)];
        [self swizzle:NSURLSession.class sel:@selector(dataTaskWithRequest:completionHandler:) with:@selector(avdb115_dataTaskWithRequest:completionHandler:)];
        [self swizzle:NSURLSession.class sel:@selector(downloadTaskWithRequest:) with:@selector(avdb115_downloadTaskWithRequest:)];
        Class wk = NSClassFromString(@"WKWebView");
        if (wk) {
            [self swizzle:wk sel:@selector(loadRequest:) with:@selector(avdb115_loadRequest:)];
        }
    });
}

@end

@implementation NSURLSession (AVDB115AdBlock)

- (NSURLSessionDataTask *)avdb115_dataTaskWithRequest:(NSURLRequest *)request {
    if ([AVDB115AdBlockPolicy shouldBlockURL:request.URL]) {
        return [self avdb115_dataTaskWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"about:blank"]]];
    }
    return [self avdb115_dataTaskWithRequest:request];
}

- (NSURLSessionDataTask *)avdb115_dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if ([AVDB115AdBlockPolicy shouldBlockURL:request.URL]) {
        if (completionHandler) {
            NSError *err = [NSError errorWithDomain:@"AVDB115AdBlock" code:1 userInfo:@{NSLocalizedDescriptionKey: @"blocked identified ad request"}];
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ completionHandler(nil, nil, err); });
        }
        return [self avdb115_dataTaskWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"about:blank"]] completionHandler:nil];
    }
    return [self avdb115_dataTaskWithRequest:request completionHandler:completionHandler];
}

- (NSURLSessionDownloadTask *)avdb115_downloadTaskWithRequest:(NSURLRequest *)request {
    if ([AVDB115AdBlockPolicy shouldBlockURL:request.URL]) {
        return [self avdb115_downloadTaskWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"about:blank"]]];
    }
    return [self avdb115_downloadTaskWithRequest:request];
}

@end

@implementation WKWebView (AVDB115AdBlock)

- (WKNavigation *)avdb115_loadRequest:(NSURLRequest *)request {
    if ([AVDB115AdBlockPolicy shouldBlockURL:request.URL]) {
        return nil;
    }
    return [self avdb115_loadRequest:request];
}

@end
