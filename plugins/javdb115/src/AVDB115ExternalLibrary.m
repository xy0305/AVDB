#import "AVDB115ExternalLibrary.h"
#import <Security/Security.h>

NSString *const AVDB115ExternalLibraryErrorDomain = @"AVDB115ExternalLibrary";

static NSString *const kExtDefaultURL = @"http://163.47.40.207:8000";
static NSString *const kExtBaseURLKey = @"avdb115.externalLibrary.baseURL";
static NSString *const kExtEnabledKey = @"avdb115.externalLibrary.enabled";
static NSString *const kExtKeychainService = @"com.avdb115.plugin.external-library";
static NSString *const kExtKeychainAccount = @"api-token";

static NSError *AVDB115ExtError(AVDB115ExternalLibraryErrorCode code, NSInteger http) {
    NSString *msg = @"";
    switch (code) {
        case AVDB115ExternalLibraryErrorInvalidURL:
            msg = @"地址只能是 http/https 根域名或 IP 加端口，不能包含账号、路径、查询或片段。";
            break;
        case AVDB115ExternalLibraryErrorInvalidToken:
            msg = @"令牌不能包含空格、换行或非 ASCII 字符。";
            break;
        case AVDB115ExternalLibraryErrorEndpointNeedsToken:
            msg = @"更换服务器时请重新输入令牌，避免将原令牌发送给其他服务器。";
            break;
        case AVDB115ExternalLibraryErrorKeychain:
            msg = @"钥匙串操作失败，请解锁设备后重试。";
            break;
        case AVDB115ExternalLibraryErrorHTTP:
            msg = [NSString stringWithFormat:@"外部数据库请求失败（HTTP %ld）；重定向不被允许。", (long)http];
            break;
        case AVDB115ExternalLibraryErrorTransport:
            msg = @"外部数据库连接失败，请检查网络及服务器地址。";
            break;
        case AVDB115ExternalLibraryErrorSchema:
            msg = @"外部数据库响应格式无效。";
            break;
    }
    NSMutableDictionary *info = [@{NSLocalizedDescriptionKey: msg} mutableCopy];
    if (http > 0) info[@"http"] = @(http);
    return [NSError errorWithDomain:AVDB115ExternalLibraryErrorDomain code:code userInfo:info];
}

@implementation AVDB115ExternalLink

+ (instancetype)linkWithDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    id rawID = dict[@"id"];
    NSString *url = dict[@"download_url"];
    if (![url isKindOfClass:[NSString class]] || url.length == 0) return nil;
    NSInteger identifier = 0;
    if ([rawID isKindOfClass:[NSNumber class]]) identifier = [rawID integerValue];
    else if ([rawID isKindOfClass:[NSString class]]) identifier = [rawID integerValue];
    else return nil;
    AVDB115ExternalLink *link = [[AVDB115ExternalLink alloc] init];
    link->_identifier = identifier;
    link->_downloadURL = [url copy];
    if ([dict[@"title"] isKindOfClass:[NSString class]]) link->_title = dict[@"title"];
    if ([dict[@"size_mb"] isKindOfClass:[NSNumber class]]) link->_sizeMB = dict[@"size_mb"];
    if ([dict[@"seeders"] isKindOfClass:[NSNumber class]]) link->_seeders = dict[@"seeders"];
    if ([dict[@"chinese"] isKindOfClass:[NSNumber class]]) link->_chinese = dict[@"chinese"];
    if ([dict[@"uc"] isKindOfClass:[NSNumber class]]) link->_uncensored = dict[@"uc"];
    if ([dict[@"uhd"] isKindOfClass:[NSNumber class]]) link->_uhd = dict[@"uhd"];
    return link;
}

+ (NSArray<AVDB115ExternalLink *> *)linksFromEnvelopeJSON:(NSData *)data error:(NSError **)error {
    if (!data) {
        if (error) *error = AVDB115ExtError(AVDB115ExternalLibraryErrorSchema, 0);
        return nil;
    }
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![obj isKindOfClass:[NSDictionary class]]) {
        if (error) *error = AVDB115ExtError(AVDB115ExternalLibraryErrorSchema, 0);
        return nil;
    }
    id payload = obj[@"data"];
    if (payload == nil || payload == [NSNull null]) {
        if (error) *error = AVDB115ExtError(AVDB115ExternalLibraryErrorSchema, 0);
        return nil;
    }
    if (![payload isKindOfClass:[NSArray class]]) {
        if (error) *error = AVDB115ExtError(AVDB115ExternalLibraryErrorSchema, 0);
        return nil;
    }
    NSMutableArray *links = [NSMutableArray array];
    for (id item in payload) {
        AVDB115ExternalLink *link = [self linkWithDictionary:item];
        if (!link) {
            if (error) *error = AVDB115ExtError(AVDB115ExternalLibraryErrorSchema, 0);
            return nil;
        }
        [links addObject:link];
    }
    return links;
}

- (BOOL)isMagnet {
    return [self.downloadURL.lowercaseString hasPrefix:@"magnet:"];
}

- (BOOL)isED2K {
    return [self.downloadURL.lowercaseString hasPrefix:@"ed2k:"];
}

@end

@implementation AVDB115ExternalLibrarySettings

+ (AVDB115ExternalLibrarySettings *)shared {
    static AVDB115ExternalLibrarySettings *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[AVDB115ExternalLibrarySettings alloc] init]; });
    return instance;
}

+ (NSString *)defaultBaseURL { return kExtDefaultURL; }

- (instancetype)init {
    if (self = [super init]) {
        _baseURL = [[NSUserDefaults standardUserDefaults] stringForKey:kExtBaseURLKey] ?: kExtDefaultURL;
        _enabled = [[NSUserDefaults standardUserDefaults] boolForKey:kExtEnabledKey];
        _revision = 0;
        NSError *err = nil;
        NSString *token = [self tokenWithError:&err];
        _hasToken = token.length > 0 && err == nil;
    }
    return self;
}

+ (NSString *)normalizedURL:(NSString *)raw error:(NSError **)error {
    NSString *value = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSURLComponents *p = [NSURLComponents componentsWithString:value];
    NSString *scheme = p.scheme.lowercaseString;
    BOOL bad = !p || !scheme || !([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]);
    bad = bad || p.host.length == 0 || p.user || p.password || p.query || p.fragment;
    bad = bad || !((p.path.length == 0) || [p.path isEqualToString:@"/"]);
    if (p.port) {
        NSInteger port = p.port.integerValue;
        if (port < 1 || port > 65535) bad = YES;
    }
    if (bad || !p.URL.host) {
        if (error) *error = AVDB115ExtError(AVDB115ExternalLibraryErrorInvalidURL, 0);
        return nil;
    }
    p.scheme = scheme;
    p.path = @"";
    NSString *result = p.URL.absoluteString;
    if (result.length == 0) {
        if (error) *error = AVDB115ExtError(AVDB115ExternalLibraryErrorInvalidURL, 0);
        return nil;
    }
    return result;
}

+ (BOOL)isValidToken:(NSString *)token {
    if (token.length == 0) return YES; // empty means "keep existing"
    const char *utf8 = token.UTF8String;
    if (!utf8) return NO;
    for (const unsigned char *c = (const unsigned char *)utf8; *c; c++) {
        if (*c < 33 || *c > 126) return NO;
    }
    return YES;
}

+ (NSDictionary *)keychainQuery {
    return @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kExtKeychainService,
        (__bridge id)kSecAttrAccount: kExtKeychainAccount,
    };
}

- (NSString *)tokenWithError:(NSError **)error {
    NSMutableDictionary *query = [[[self class] keychainQuery] mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status == errSecItemNotFound) return nil;
    if (status != errSecSuccess) {
        if (error) *error = AVDB115ExtError(AVDB115ExternalLibraryErrorKeychain, 0);
        return nil;
    }
    NSData *data = (__bridge_transfer NSData *)result;
    NSString *value = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!value) {
        if (error) *error = AVDB115ExtError(AVDB115ExternalLibraryErrorKeychain, 0);
        return nil;
    }
    return value;
}

- (BOOL)writeToken:(NSString *)token error:(NSError **)error {
    SecItemDelete((__bridge CFDictionaryRef)[[self class] keychainQuery]);
    if (token.length == 0) return YES;
    NSDictionary *add = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kExtKeychainService,
        (__bridge id)kSecAttrAccount: kExtKeychainAccount,
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        (__bridge id)kSecValueData: [token dataUsingEncoding:NSUTF8StringEncoding],
    };
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    if (status != errSecSuccess) {
        if (error) *error = AVDB115ExtError(AVDB115ExternalLibraryErrorKeychain, 0);
        return NO;
    }
    return YES;
}

- (BOOL)saveBaseURL:(NSString *)raw enabled:(BOOL)enabled replacementToken:(NSString *)replacementToken error:(NSError **)error {
    NSString *url = [[self class] normalizedURL:raw error:error];
    if (!url) return NO;
    NSString *token = replacementToken ?: @"";
    if (![[self class] isValidToken:token]) {
        if (error) *error = AVDB115ExtError(AVDB115ExternalLibraryErrorInvalidToken, 0);
        return NO;
    }
    if (![url isEqualToString:self.baseURL] && token.length == 0) {
        NSError *readErr = nil;
        NSString *existing = [self tokenWithError:&readErr];
        if (readErr) {
            if (error) *error = readErr;
            return NO;
        }
        if (existing != nil) {
            if (error) *error = AVDB115ExtError(AVDB115ExternalLibraryErrorEndpointNeedsToken, 0);
            return NO;
        }
    }
    if (token.length > 0) {
        if (![self writeToken:token error:error]) return NO;
    }
    _baseURL = url;
    _enabled = enabled;
    [[NSUserDefaults standardUserDefaults] setObject:url forKey:kExtBaseURLKey];
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kExtEnabledKey];
    _revision += 1;
    NSError *tokErr = nil;
    NSString *stored = [self tokenWithError:&tokErr];
    _hasToken = stored.length > 0 && tokErr == nil;
    [AVDB115ExternalLibraryClient.shared cancelRequests];
    return YES;
}

- (BOOL)clearTokenWithError:(NSError **)error {
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)[[self class] keychainQuery]);
    if (status != errSecSuccess && status != errSecItemNotFound) {
        if (error) *error = AVDB115ExtError(AVDB115ExternalLibraryErrorKeychain, 0);
        return NO;
    }
    _hasToken = NO;
    _revision += 1;
    [AVDB115ExternalLibraryClient.shared cancelRequests];
    return YES;
}

@end

@interface AVDB115ExternalRedirectBlocker : NSObject <NSURLSessionTaskDelegate>
@end

@implementation AVDB115ExternalRedirectBlocker
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    // Reject ALL redirects, including same-origin ones (AVDB ExternalRedirectBlocker).
    (void)session; (void)task; (void)response; (void)request;
    completionHandler(nil);
}
@end

@interface AVDB115ExternalLibraryClient ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) AVDB115ExternalRedirectBlocker *blocker;
@property (nonatomic, strong) NSMutableArray<NSURLSessionDataTask *> *tasks;
@end

@implementation AVDB115ExternalLibraryClient

+ (AVDB115ExternalLibraryClient *)shared {
    static AVDB115ExternalLibraryClient *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[AVDB115ExternalLibraryClient alloc] init]; });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _blocker = [[AVDB115ExternalRedirectBlocker alloc] init];
        _tasks = [NSMutableArray array];
    }
    return self;
}

- (NSURLSession *)transport {
    if (self.session) return self.session;
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.URLCache = nil;
    config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    config.HTTPShouldSetCookies = NO;
    config.HTTPCookieStorage = nil;
    config.URLCredentialStorage = nil;
    // Do not attach the 115 cookie or any shared cookie jar.
    self.session = [NSURLSession sessionWithConfiguration:config delegate:self.blocker delegateQueue:nil];
    return self.session;
}

- (void)cancelRequests {
    @synchronized (self) {
        [self.session invalidateAndCancel];
        self.session = nil;
        [self.tasks removeAllObjects];
    }
}

- (void)fetchLinksForNumber:(NSString *)number completion:(AVDB115ExternalLibraryCompletion)completion {
    AVDB115ExternalLibrarySettings *settings = AVDB115ExternalLibrarySettings.shared;
    NSString *keyword = [number stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!settings.enabled || keyword.length == 0) {
        completion(@[], nil);
        return;
    }
    NSError *tokErr = nil;
    NSString *token = [settings tokenWithError:&tokErr];
    if (tokErr) {
        completion(nil, tokErr);
        return;
    }
    if (token.length == 0) {
        completion(@[], nil);
        return;
    }
    NSUInteger generation = settings.revision;
    NSError *urlErr = nil;
    NSString *base = [AVDB115ExternalLibrarySettings normalizedURL:settings.baseURL error:&urlErr];
    if (!base) {
        completion(nil, urlErr);
        return;
    }
    NSURLComponents *parts = [NSURLComponents componentsWithString:[base stringByAppendingString:@"/api/v1/articles/torrents"]];
    parts.queryItems = @[[NSURLQueryItem queryItemWithName:@"keyword" value:keyword]];
    NSURL *url = parts.URL;
    if (!url) {
        completion(nil, AVDB115ExtError(AVDB115ExternalLibraryErrorInvalidURL, 0));
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20];
    [request setValue:token forHTTPHeaderField:@"X-API-Key"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    // Never log the token or put it in the URL.
    NSURLSessionDataTask *task = [[self transport] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (generation != AVDB115ExternalLibrarySettings.shared.revision || error.code == NSURLErrorCancelled) {
            completion(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
            return;
        }
        if (error) {
            completion(nil, AVDB115ExtError(AVDB115ExternalLibraryErrorTransport, 0));
            return;
        }
        if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
            completion(nil, AVDB115ExtError(AVDB115ExternalLibraryErrorTransport, 0));
            return;
        }
        NSInteger status = ((NSHTTPURLResponse *)response).statusCode;
        if (status != 200) {
            completion(nil, AVDB115ExtError(AVDB115ExternalLibraryErrorHTTP, status));
            return;
        }
        NSError *schema = nil;
        NSArray *links = [AVDB115ExternalLink linksFromEnvelopeJSON:data error:&schema];
        if (!links) {
            completion(nil, schema);
            return;
        }
        completion(links, nil);
    }];
    [task resume];
}

@end
