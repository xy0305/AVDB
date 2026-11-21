#include <stdlib.h>
#include <string.h>
#import "AVDB115CoverResolver.h"
#import "AVDB115Catalog.h"

static const NSInteger kAVDB115CoverTimeout = 8;
static const NSInteger kAVDB115CoverMaxBytes = 8 * 1024 * 1024;
static const NSInteger kAVDB115HTMLMaxBytes = 2 * 1024 * 1024;
static const NSInteger kAVDB115CoverCacheCap = 40;

@interface AVDB115CoverCandidate ()
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) NSString *source;
@property (nonatomic) BOOL probed;
@property (nonatomic) BOOL reachable;
@property (nonatomic, copy) NSString *message;
@property (nonatomic) NSInteger width;
@property (nonatomic) NSInteger height;
@property (nonatomic) BOOL eligiblePortrait;
@property (nonatomic, copy) NSString *cachePath;
@end

@implementation AVDB115CoverCandidate
@end

@interface AVDB115CoverResolveResult ()
@property (nonatomic, copy) NSString *number;
@property (nonatomic, copy) NSArray<AVDB115CoverCandidate *> *candidates;
@property (nonatomic, copy) NSArray<NSString *> *notes;
@end

@implementation AVDB115CoverResolveResult
@end

@interface AVDB115CoverAllowlistRedirect : NSObject <NSURLSessionTaskDelegate>
@end

@implementation AVDB115CoverAllowlistRedirect
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    (void)session; (void)task; (void)response;
    NSURL *url = request.URL;
    NSString *host = url.host.lowercaseString;
    NSArray *htmlHosts = @[@"www.avbase.net", @"www.javbus.com"];
    BOOL htmlOK = [htmlHosts containsObject:host] && [url.scheme.lowercaseString isEqualToString:@"https"];
    BOOL imageOK = [AVDB115CoverPolicy allowedPublicImageURL:url];
    // If the redirect itself is a challenge page, drop it (no bypass).
    if ([AVDB115CoverPolicy htmlLooksLikeChallenge:@"" finalURL:url]) {
        completionHandler(nil);
        return;
    }
    completionHandler((htmlOK || imageOK) ? request : nil);
}
@end

@interface AVDB115CoverResolver ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) AVDB115CoverAllowlistRedirect *redirects;
@property (nonatomic) NSUInteger generation;
@property (nonatomic, strong) NSMutableArray<NSURLSessionTask *> *tasks;
@end

@implementation AVDB115CoverResolver

+ (AVDB115CoverResolver *)shared {
    static AVDB115CoverResolver *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[AVDB115CoverResolver alloc] init]; });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _enableDMM = YES;
        _enableMGS = YES;
        _enableAvbase = YES;
        _enableJavBus = YES;
        _redirects = [[AVDB115CoverAllowlistRedirect alloc] init];
        _tasks = [NSMutableArray array];
        _generation = 0;
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
    config.timeoutIntervalForRequest = kAVDB115CoverTimeout;
    config.timeoutIntervalForResource = kAVDB115CoverTimeout + 2;
    self.session = [NSURLSession sessionWithConfiguration:config delegate:self.redirects delegateQueue:nil];
    return self.session;
}

- (void)cancel {
    @synchronized (self) {
        self.generation += 1;
        [self.session invalidateAndCancel];
        self.session = nil;
        [self.tasks removeAllObjects];
    }
}

+ (NSURL *)cacheRoot {
    NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    return [caches URLByAppendingPathComponent:@"avdb115/covers" isDirectory:YES];
}

- (void)clearCache {
    NSURL *root = [AVDB115CoverResolver cacheRoot];
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];
}

- (NSUInteger)cacheFileCount {
    NSURL *root = [AVDB115CoverResolver cacheRoot];
    NSArray *items = [NSFileManager.defaultManager contentsOfDirectoryAtPath:root.path error:nil];
    return items.count;
}

+ (NSString *)numberKey:(NSString *)number {
    return [AVDB115CatalogNumber identityKey:number] ?: [[number lowercaseString] stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
}

+ (NSArray<NSDictionary *> *)deterministicCandidatesForNumber:(NSString *)number
                                                       enableDMM:(BOOL)dmm
                                                       enableMGS:(BOOL)mgs {
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    void (^add)(NSString *, NSString *) = ^(NSString *url, NSString *source) {
        NSURL *parsed = [NSURL URLWithString:url];
        if (![AVDB115CoverPolicy allowedPublicImageURL:parsed]) return;
        if ([seen containsObject:url]) return;
        [seen addObject:url];
        [out addObject:@{@"url": url, @"source": source}];
    };
    if (mgs) {
        for (NSString *url in [AVDB115MGSCoverURLs candidatesForNumber:number]) add(url, @"MGS");
    }
    if (dmm) {
        NSArray *cids = [AVDB115DMMCoverURLs cidCandidatesForNumber:number];
        for (NSString *cid in cids) {
            for (NSString *url in [AVDB115DMMCoverURLs digitalURLsForCID:cid]) add(url, @"DMM");
        }
        // pics.dmm.co.jp pl as same-CID fallback (AVDB DMMCoverURLs.legacy), after awsimgsrc.
        for (NSString *cid in cids) {
            NSArray *legacy = [AVDB115DMMCoverURLs legacyURLsForCID:cid];
            if (legacy.count) add(legacy.firstObject, @"DMM");
        }
    }
    return out;
}

+ (BOOL)readJPEGSize:(NSData *)data width:(NSInteger *)width height:(NSInteger *)height {
    const unsigned char *b = data.bytes;
    NSUInteger len = data.length;
    if (len < 4 || b[0] != 0xFF || b[1] != 0xD8) return NO;
    NSUInteger i = 2;
    while (i + 9 < len) {
        if (b[i] != 0xFF) { i++; continue; }
        unsigned char marker = b[i + 1];
        if (marker == 0xD8 || marker == 0xD9 || (marker >= 0xD0 && marker <= 0xD7)) { i += 2; continue; }
        if (i + 3 >= len) break;
        unsigned int seglen = (b[i + 2] << 8) | b[i + 3];
        if (seglen < 2 || i + 2 + seglen > len) break;
        // SOF0 / SOF1 / SOF2
        if (marker == 0xC0 || marker == 0xC1 || marker == 0xC2) {
            if (width) *width = (b[i + 7] << 8) | b[i + 8];
            if (height) *height = (b[i + 5] << 8) | b[i + 6];
            return YES;
        }
        i += 2 + seglen;
    }
    return NO;
}

- (NSString *)cachePathForURL:(NSString *)url number:(NSString *)number {
    const char *bytes = url.UTF8String ?: "";
    unsigned long hash = 5381;
    for (const unsigned char *p = (const unsigned char *)bytes; *p; p++) hash = ((hash << 5) + hash) + *p;
    NSString *key = [AVDB115CoverResolver numberKey:number];
    NSURL *dir = [[AVDB115CoverResolver cacheRoot] URLByAppendingPathComponent:key isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir URLByAppendingPathComponent:[NSString stringWithFormat:@"%lx.jpg", hash]].path;
}

- (void)trimCacheIfNeeded {
    NSURL *root = [AVDB115CoverResolver cacheRoot];
    NSArray *keys = [NSFileManager.defaultManager contentsOfDirectoryAtPath:root.path error:nil] ?: @[];
    if (keys.count <= kAVDB115CoverCacheCap) return;
    NSMutableArray *dated = [NSMutableArray array];
    for (NSString *key in keys) {
        NSString *path = [root URLByAppendingPathComponent:key].path;
        NSDate *m = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil][NSFileModificationDate];
        [dated addObject:@{@"path": path, @"date": m ?: [NSDate distantPast]}];
    }
    [dated sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"date"] compare:b[@"date"]];
    }];
    NSInteger drop = (NSInteger)dated.count - kAVDB115CoverCacheCap;
    for (NSInteger i = 0; i < drop; i++) {
        [NSFileManager.defaultManager removeItemAtPath:dated[i][@"path"] error:nil];
    }
}

- (NSData *)GET:(NSString *)urlString maxBytes:(NSInteger)maxBytes finalURL:(NSURL **)finalURL status:(NSInteger *)status error:(NSError **)error generation:(NSUInteger)generation {
    if (generation != self.generation) {
        if (error) *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil];
        return nil;
    }
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return nil;
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:kAVDB115CoverTimeout];
    [req setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15" forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"*/*" forHTTPHeaderField:@"Accept"];
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSData *outData = nil;
    __block NSError *outErr = nil;
    __block NSURL *outURL = nil;
    __block NSInteger outStatus = 0;
    NSURLSessionDataTask *task = [[self transport] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *err) {
        outErr = err;
        outURL = response.URL;
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) outStatus = ((NSHTTPURLResponse *)response).statusCode;
        if (data.length > (NSUInteger)maxBytes) {
            outData = [data subdataWithRange:NSMakeRange(0, (NSUInteger)maxBytes)];
        } else {
            outData = data;
        }
        dispatch_semaphore_signal(sem);
    }];
    @synchronized (self) { [self.tasks addObject:task]; }
    [task resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)((kAVDB115CoverTimeout + 2) * NSEC_PER_SEC)));
    if (finalURL) *finalURL = outURL;
    if (status) *status = outStatus;
    if (error) *error = outErr;
    return outData;
}

- (void)probeCandidate:(AVDB115CoverCandidate *)item number:(NSString *)number generation:(NSUInteger)generation {
    if (generation != self.generation) {
        item.probed = YES;
        item.reachable = NO;
        item.message = @"已取消";
        return;
    }
    NSString *cached = [self cachePathForURL:item.url number:number];
    NSData *cachedData = [NSData dataWithContentsOfFile:cached];
    if (cachedData.length > 32) {
        NSInteger w = 0, h = 0;
        [AVDB115CoverResolver readJPEGSize:cachedData width:&w height:&h];
        item.probed = YES;
        item.reachable = YES;
        item.width = w;
        item.height = h;
        item.eligiblePortrait = [AVDB115CoverPolicy eligiblePortraitWidth:w height:h];
        item.cachePath = cached;
        item.message = item.eligiblePortrait ? @"缓存（高清候选）" : @"缓存";
        return;
    }
    NSURL *finalURL = nil;
    NSInteger status = 0;
    NSError *err = nil;
    NSData *data = [self GET:item.url maxBytes:kAVDB115CoverMaxBytes finalURL:&finalURL status:&status error:&err generation:generation];
    item.probed = YES;
    if (generation != self.generation) {
        item.reachable = NO;
        item.message = @"已取消";
        return;
    }
    if (err) {
        item.reachable = NO;
        item.message = (err.code == NSURLErrorTimedOut || err.code == NSURLErrorCancelled) ? @"超时或已取消" : @"请求失败";
        return;
    }
    if (status == 403 || status == 429 || status == 503) {
        item.reachable = NO;
        item.message = [NSString stringWithFormat:@"HTTP %ld（不绕过）", (long)status];
        return;
    }
    if (status != 200 || data.length < 32) {
        item.reachable = NO;
        item.message = [NSString stringWithFormat:@"HTTP %ld", (long)status];
        return;
    }
    if (finalURL && ![AVDB115CoverPolicy allowedPublicImageURL:finalURL]) {
        item.reachable = NO;
        item.message = @"跳转到非允许封面域（已拒绝）";
        return;
    }
    NSInteger w = 0, h = 0;
    if (![AVDB115CoverResolver readJPEGSize:data width:&w height:&h]) {
        item.reachable = NO;
        item.message = @"不是有效 JPEG";
        return;
    }
    item.reachable = YES;
    item.width = w;
    item.height = h;
    item.eligiblePortrait = [AVDB115CoverPolicy eligiblePortraitWidth:w height:h];
    [data writeToFile:cached atomically:YES];
    item.cachePath = cached;
    item.message = item.eligiblePortrait ? [NSString stringWithFormat:@"%ld×%ld 高清候选", (long)w, (long)h]
                                        : [NSString stringWithFormat:@"%ld×%ld", (long)w, (long)h];
    [self trimCacheIfNeeded];
}

+ (NSArray<NSString *> *)javBusCoversFromHTML:(NSString *)html {
    if (html.length == 0) return @[];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"https://www\\.javbus\\.com/pics/cover/[A-Za-z0-9._-]+_b\\.jpg" options:0 error:nil];
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    [re enumerateMatchesInString:html options:0 range:NSMakeRange(0, html.length) usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags flags, BOOL *stop) {
        (void)flags; (void)stop;
        NSString *url = [html substringWithRange:m.range];
        if (![seen containsObject:url] && [AVDB115CoverPolicy allowedJavBusCoverURL:[NSURL URLWithString:url]]) {
            [seen addObject:url];
            [out addObject:url];
        }
    }];
    return out;
}

+ (id)avbasePageProps:(NSString *)html {
    if (html.UTF8String == NULL) return nil;
    if (strlen(html.UTF8String) > (size_t)kAVDB115HTMLMaxBytes) return nil;
    NSRegularExpression *script = [NSRegularExpression regularExpressionWithPattern:@"<script\\b([^>]*)>(.*?)</script\\s*>" options:NSRegularExpressionDotMatchesLineSeparators error:nil];
    NSArray *blocks = [script matchesInString:html options:0 range:NSMakeRange(0, html.length)];
    NSTextCheckingResult *hit = nil;
    NSRegularExpression *idRe = [NSRegularExpression regularExpressionWithPattern:@"(?:^|\\s)id\\s*=\\s*[\"']__NEXT_DATA__[\"']" options:0 error:nil];
    for (NSTextCheckingResult *m in blocks) {
        if (m.numberOfRanges < 3) continue;
        NSString *attrs = [html substringWithRange:[m rangeAtIndex:1]];
        if ([idRe firstMatchInString:attrs options:0 range:NSMakeRange(0, attrs.length)]) {
            if (hit) return nil; // must be unique
            hit = m;
        }
    }
    if (!hit) return nil;
    NSString *json = [html substringWithRange:[hit rangeAtIndex:2]];
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    id root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![root isKindOfClass:[NSDictionary class]]) return nil;
    id props = root[@"props"];
    if (![props isKindOfClass:[NSDictionary class]]) return nil;
    id page = props[@"pageProps"];
    return [page isKindOfClass:[NSDictionary class]] ? page : nil;
}

+ (NSArray<NSDictionary *> *)avbaseImagesFromHTML:(NSString *)html number:(NSString *)number {
    NSDictionary *page = [self avbasePageProps:html];
    if (!page) return @[];
    NSArray *rows = nil;
    if ([page[@"work"] isKindOfClass:[NSDictionary class]]) rows = @[page[@"work"]];
    else if ([page[@"works"] isKindOfClass:[NSArray class]]) rows = page[@"works"];
    else return @[];
    NSString *wantedKey = [AVDB115CatalogNumber identityKey:number];
    if (!wantedKey) return @[];
    NSMutableArray *pool = [NSMutableArray array];
    for (id work in rows) {
        if (![work isKindOfClass:[NSDictionary class]]) continue;
        NSString *wid = [work[@"work_id"] isKindOfClass:[NSString class]] ? work[@"work_id"] : nil;
        if (wid && [AVDB115CatalogNumber identity:wid matches:number]) [pool addObject:work];
    }
    if (pool.count == 0) return @[];
    NSMutableSet *keys = [NSMutableSet set];
    for (NSDictionary *work in pool) {
        NSString *k = [AVDB115CatalogNumber identityKey:work[@"work_id"]];
        if (k) [keys addObject:k];
    }
    if (keys.count != 1) return @[];
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    void (^consider)(NSString *) = ^(NSString *raw) {
        if (![raw isKindOfClass:[NSString class]]) return;
        NSURL *url = [NSURL URLWithString:raw];
        if (!url) return;
        NSArray *upgraded = [AVDB115DMMCoverURLs upgradeImageURL:raw];
        NSArray *list = upgraded.count ? upgraded : @[raw];
        for (NSString *item in list) {
            NSURL *parsed = [NSURL URLWithString:item];
            if (![AVDB115CoverPolicy allowedPublicImageURL:parsed]) continue;
            if ([seen containsObject:item]) continue;
            [seen addObject:item];
            NSString *source = @"Avbase";
            NSString *host = parsed.host.lowercaseString;
            if ([host containsString:@"dmm.co.jp"]) source = @"Avbase/DMM";
            else if ([host containsString:@"mgstage.com"]) source = @"Avbase/MGS";
            else if ([host containsString:@"amazon"]) source = @"Avbase/Amazon";
            [out addObject:@{@"url": item, @"source": source}];
        }
    };
    for (NSDictionary *work in pool) {
        NSArray *products = [work[@"products"] isKindOfClass:[NSArray class]] ? work[@"products"] : @[];
        for (id product in products) {
            if (![product isKindOfClass:[NSDictionary class]]) continue;
            NSString *pid = [product[@"product_id"] isKindOfClass:[NSString class]] ? product[@"product_id"] : nil;
            BOOL matched = pid && [AVDB115CatalogNumber identity:pid matches:number];
            // Also accept a DMM product id that already appears as the image CID path; never synthesize a CID.
            NSString *image = [product[@"image_url"] isKindOfClass:[NSString class]] ? product[@"image_url"] : nil;
            NSString *thumb = [product[@"thumbnail_url"] isKindOfClass:[NSString class]] ? product[@"thumbnail_url"] : nil;
            if (matched) {
                consider(image);
                consider(thumb);
            } else if (image) {
                NSString *cid = [AVDB115DMMCoverURLs cidFromImageURL:image];
                if (cid && pid && [cid isEqualToString:pid.lowercaseString] && [AVDB115CatalogNumber identity:pid matches:number]) {
                    consider(image);
                    consider(thumb);
                }
            }
        }
    }
    return out;
}

- (AVDB115CoverCandidate *)itemWithURL:(NSString *)url source:(NSString *)source {
    AVDB115CoverCandidate *item = [[AVDB115CoverCandidate alloc] init];
    item.url = url;
    item.source = source;
    return item;
}

- (AVDB115CoverResolveResult *)snapshot:(NSString *)number items:(NSArray *)items notes:(NSArray *)notes {
    AVDB115CoverResolveResult *r = [[AVDB115CoverResolveResult alloc] init];
    r.number = number;
    r.candidates = [items copy];
    r.notes = [notes copy];
    return r;
}

- (void)resolveNumber:(NSString *)number progress:(AVDB115CoverProgress)progress completion:(AVDB115CoverCompletion)completion {
    NSString *keyword = [number stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (keyword.length == 0) {
        completion(nil, [NSError errorWithDomain:@"AVDB115Cover" code:1 userInfo:@{NSLocalizedDescriptionKey: @"请填写番号"}]);
        return;
    }
    [self cancel];
    NSUInteger generation = self.generation; // cancel bumped it; use the new value? Wait: cancel increments, so current generation is the new one. Good - we cancelled old, generation is fresh. But we need to set this request's gen AFTER cancel. cancel already incremented. We'll use current generation as ours, and future cancel will increment past it.
    NSUInteger gen = self.generation;
    BOOL enableDMM = self.enableDMM;
    BOOL enableMGS = self.enableMGS;
    BOOL enableAvbase = self.enableAvbase;
    BOOL enableJavBus = self.enableJavBus;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray<AVDB115CoverCandidate *> *items = [NSMutableArray array];
        NSMutableArray *notes = [NSMutableArray array];
        [notes addObject:@"高清封面仅在本插件面板预览与缓存，不替换 JavDB 原首页或详情封面。JavDB Flutter 封面 CDN 地址通常不含番号，无法可靠做全局图片替换。"];
        [notes addObject:@"不会把 115 Cookie 带到外部封面站。失败的源会跳过并回退，不绕过验证码或封禁。"];

        NSArray *seed = [AVDB115CoverResolver deterministicCandidatesForNumber:keyword enableDMM:enableDMM enableMGS:enableMGS];
        for (NSDictionary *row in seed) {
            [items addObject:[self itemWithURL:row[@"url"] source:row[@"source"]]];
        }
        if (items.count == 0 && !enableAvbase && !enableJavBus) {
            [notes addObject:@"没有可构造的公开封面 URL（番号可能不是标准厂牌格式）。"];
        }

        void (^emit)(void) = ^{
            if (!progress) return;
            AVDB115CoverResolveResult *snap = [self snapshot:keyword items:items notes:notes];
            dispatch_async(dispatch_get_main_queue(), ^{ progress(snap); });
        };
        emit();

        // Probe deterministic URLs first (deduped already). Timeout / cancel / fallback.
        for (AVDB115CoverCandidate *item in items) {
            if (gen != self.generation) break;
            [self probeCandidate:item number:keyword generation:gen];
            emit();
        }

        if (enableAvbase && gen == self.generation) {
            NSString *q = [keyword stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
            NSString *page = [NSString stringWithFormat:@"https://www.avbase.net/works?q=%@", q ?: @""];
            NSURL *finalURL = nil;
            NSInteger status = 0;
            NSError *err = nil;
            NSData *data = [self GET:page maxBytes:kAVDB115HTMLMaxBytes finalURL:&finalURL status:&status error:&err generation:gen];
            NSString *html = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
            if (err && err.code == NSURLErrorCancelled) {
                [notes addObject:@"Avbase：已取消"];
            } else if (status == 403 || status == 429 || status == 503) {
                [notes addObject:[NSString stringWithFormat:@"Avbase：HTTP %ld，已跳过（不绕过封禁）", (long)status]];
            } else if (err) {
                [notes addObject:@"Avbase：连接失败，已跳过"];
            } else if ([AVDB115CoverPolicy htmlLooksLikeChallenge:html finalURL:finalURL]) {
                [notes addObject:@"Avbase：页面为验证/挑战，已跳过（不绕过）"];
            } else if (status != 200) {
                [notes addObject:[NSString stringWithFormat:@"Avbase：HTTP %ld，已跳过", (long)status]];
            } else {
                NSArray *found = [AVDB115CoverResolver avbaseImagesFromHTML:html number:keyword];
                if (found.count == 0) {
                    [notes addObject:@"Avbase：可达但未解析到与该番号匹配的公开封面 URL"];
                } else {
                    NSMutableSet *have = [NSMutableSet set];
                    for (AVDB115CoverCandidate *c in items) [have addObject:c.url];
                    NSMutableArray *fresh = [NSMutableArray array];
                    for (NSDictionary *row in found) {
                        if ([have containsObject:row[@"url"]]) continue;
                        AVDB115CoverCandidate *item = [self itemWithURL:row[@"url"] source:row[@"source"]];
                        [items addObject:item];
                        [fresh addObject:item];
                    }
                    [notes addObject:[NSString stringWithFormat:@"Avbase：解析到 %lu 条新候选", (unsigned long)fresh.count]];
                    emit();
                    for (AVDB115CoverCandidate *item in fresh) {
                        if (gen != self.generation) break;
                        [self probeCandidate:item number:keyword generation:gen];
                        emit();
                    }
                }
            }
            emit();
        }

        if (enableJavBus && gen == self.generation) {
            NSString *path = [keyword stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
            NSString *page = [NSString stringWithFormat:@"https://www.javbus.com/%@", path ?: @""];
            NSURL *finalURL = nil;
            NSInteger status = 0;
            NSError *err = nil;
            NSData *data = [self GET:page maxBytes:kAVDB115HTMLMaxBytes finalURL:&finalURL status:&status error:&err generation:gen];
            NSString *html = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
            if (err && err.code == NSURLErrorCancelled) {
                [notes addObject:@"JavBus：已取消"];
            } else if (status == 403 || status == 429 || status == 503) {
                [notes addObject:[NSString stringWithFormat:@"JavBus：HTTP %ld，已跳过（不绕过封禁）", (long)status]];
            } else if (err) {
                [notes addObject:@"JavBus：连接失败，已跳过"];
            } else if ([AVDB115CoverPolicy htmlLooksLikeChallenge:html finalURL:finalURL] || [finalURL.path.lowercaseString containsString:@"/doc/driver-verify"]) {
                [notes addObject:@"JavBus：触发 driver-verify / 挑战页，已跳过（不绕过）"];
            } else if (status != 200) {
                [notes addObject:[NSString stringWithFormat:@"JavBus：HTTP %ld，已跳过", (long)status]];
            } else {
                NSArray *found = [AVDB115CoverResolver javBusCoversFromHTML:html];
                if (found.count == 0) {
                    [notes addObject:@"JavBus：可达但未找到第一方 /pics/cover/*_b.jpg"];
                } else {
                    NSMutableSet *have = [NSMutableSet set];
                    for (AVDB115CoverCandidate *c in items) [have addObject:c.url];
                    NSMutableArray *fresh = [NSMutableArray array];
                    for (NSString *url in found) {
                        if ([have containsObject:url]) continue;
                        AVDB115CoverCandidate *item = [self itemWithURL:url source:@"JavBus"];
                        [items addObject:item];
                        [fresh addObject:item];
                    }
                    [notes addObject:[NSString stringWithFormat:@"JavBus：解析到 %lu 条第一方封面", (unsigned long)fresh.count]];
                    emit();
                    for (AVDB115CoverCandidate *item in fresh) {
                        if (gen != self.generation) break;
                        [self probeCandidate:item number:keyword generation:gen];
                        emit();
                    }
                }
            }
            emit();
        }

        if (gen != self.generation) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:@{NSLocalizedDescriptionKey: @"已取消"}]);
            });
            return;
        }
        AVDB115CoverResolveResult *result = [self snapshot:keyword items:items notes:notes];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(result, nil); });
    });
}

@end
