#import "AVDB115MagnetJSON.h"
#import "AVDB115MagnetCache.h"
#import "AVDB115VisibleMagnets.h"
#import "AVDB115Link.h"
#import "AVDB115DartRowHook.h"

static NSUInteger gHttpCaptures = 0;
static NSUInteger gFileHarvest = 0;
static NSUInteger gPlaintextHarvest = 0;
static NSUInteger gDartObjectScan = 0;
static BOOL gURLSessionHook = NO;
static BOOL gURLProtocol = NO;

@implementation AVDB115MagnetJSON

+ (BOOL)isMagnetListURLString:(NSString *)text {
    if (text.length == 0) return NO;
    NSString *s = text.lowercaseString;
    if ([s containsString:@"/magnets"]) return YES;
    if ([s containsString:@"/search_magnet"]) return YES;
    return NO;
}

+ (BOOL)isMagnetListURL:(NSURL *)url {
    if (!url) return NO;
    NSString *path = url.path.lowercaseString ?: @"";
    if ([path containsString:@"/magnets"]) return YES;
    if ([path containsString:@"/search_magnet"]) return YES;
    return [self isMagnetListURLString:url.absoluteString];
}

+ (NSUInteger)ingestOneDictionary:(NSDictionary *)d catalogHint:(NSString *)hint {
    if (![d isKindOfClass:NSDictionary.class]) return 0;
    id hashV = d[@"hash"];
    id nameV = d[@"name"] ?: d[@"title"];
    id typeV = d[@"type"];
    id urlV = d[@"url"];
    NSString *hash = [hashV isKindOfClass:NSString.class] ? hashV : nil;
    NSString *name = [nameV isKindOfClass:NSString.class] ? nameV : nil;
    NSString *type = [typeV isKindOfClass:NSString.class] ? typeV : nil;
    NSString *url = [urlV isKindOfClass:NSString.class] ? urlV : nil;
    NSString *link = [AVDB115VisibleMagnets linkFromMagnetHash:hash name:name type:type url:url];
    if (link.length == 0) return 0;
    NSString *catalog = hint.length ? hint : name;
    [[AVDB115MagnetCache shared] addLink:link catalogHint:catalog];
    return 1;
}

+ (NSUInteger)walk:(id)obj catalogHint:(NSString *)hint depth:(NSInteger)depth {
    if (depth > 8 || !obj || obj == (id)NSNull.null) return 0;
    NSUInteger n = 0;
    if ([obj isKindOfClass:NSDictionary.class]) {
        NSDictionary *d = obj;
        n += [self ingestOneDictionary:d catalogHint:hint];
        // Common envelopes: { "data": [ Magnets ] } or { "data": { "magnets": [...] } }.
        for (id key in d) {
            id child = d[key];
            if ([child isKindOfClass:NSDictionary.class] || [child isKindOfClass:NSArray.class]) {
                n += [self walk:child catalogHint:hint depth:depth + 1];
            }
        }
    } else if ([obj isKindOfClass:NSArray.class]) {
        for (id child in (NSArray *)obj) {
            n += [self walk:child catalogHint:hint depth:depth + 1];
        }
    }
    return n;
}

+ (NSUInteger)ingestRegexUTF8:(NSString *)text catalogHint:(NSString *)hint {
    if (text.length == 0) return 0;
    static NSRegularExpression *hashRe;
    static NSRegularExpression *ed2kRe;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        hashRe = [NSRegularExpression regularExpressionWithPattern:@"\"hash\"\\s*:\\s*\"([0-9a-fA-F]{32,40})\"" options:0 error:nil];
        ed2kRe = [NSRegularExpression regularExpressionWithPattern:@"\"url\"\\s*:\\s*\"(ed2k://[^\"]{10,400})\"" options:NSRegularExpressionCaseInsensitive error:nil];
    });
    NSUInteger added = 0;
    NSArray<NSTextCheckingResult *> *hashes = [hashRe matchesInString:text options:0 range:NSMakeRange(0, text.length)];
    for (NSTextCheckingResult *m in hashes) {
        NSInteger start = (NSInteger)m.range.location - 500;
        if (start < 0) start = 0;
        NSInteger end = (NSInteger)NSMaxRange(m.range) + 500;
        if (end > (NSInteger)text.length) end = (NSInteger)text.length;
        NSString *window = [text substringWithRange:NSMakeRange((NSUInteger)start, (NSUInteger)(end - start))];
        NSString *(^field)(NSString *) = ^NSString *(NSString *key) {
            NSString *pat = [NSString stringWithFormat:@"\"%@\"\\s*:\\s*\"([^\"]{0,400})\"", key];
            NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pat options:0 error:nil];
            NSTextCheckingResult *mm = [re firstMatchInString:window options:0 range:NSMakeRange(0, window.length)];
            if (!mm || mm.numberOfRanges < 2) return nil;
            return [window substringWithRange:[mm rangeAtIndex:1]];
        };
        NSString *link = [AVDB115VisibleMagnets linkFromMagnetHash:field(@"hash")
                                                             name:(field(@"name") ?: field(@"title"))
                                                             type:field(@"type")
                                                              url:field(@"url")];
        if (link.length == 0) continue;
        [[AVDB115MagnetCache shared] addLink:link catalogHint:(hint.length ? hint : field(@"name"))];
        added++;
    }
    NSArray<NSTextCheckingResult *> *ed2ks = [ed2kRe matchesInString:text options:0 range:NSMakeRange(0, text.length)];
    for (NSTextCheckingResult *m in ed2ks) {
        if (m.numberOfRanges < 2) continue;
        NSString *url = [text substringWithRange:[m rangeAtIndex:1]];
        NSInteger start = (NSInteger)m.range.location - 500;
        if (start < 0) start = 0;
        NSInteger end = (NSInteger)NSMaxRange(m.range) + 500;
        if (end > (NSInteger)text.length) end = (NSInteger)text.length;
        NSString *window = [text substringWithRange:NSMakeRange((NSUInteger)start, (NSUInteger)(end - start))];
        NSString *(^field)(NSString *) = ^NSString *(NSString *key) {
            NSString *pat = [NSString stringWithFormat:@"\"%@\"\\s*:\\s*\"([^\"]{0,400})\"", key];
            NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pat options:0 error:nil];
            NSTextCheckingResult *mm = [re firstMatchInString:window options:0 range:NSMakeRange(0, window.length)];
            if (!mm || mm.numberOfRanges < 2) return nil;
            return [window substringWithRange:[mm rangeAtIndex:1]];
        };
        NSString *link = [AVDB115VisibleMagnets linkFromMagnetHash:nil
                                                             name:field(@"name")
                                                             type:(field(@"type") ?: @"ed2k")
                                                              url:url];
        if (link.length == 0) continue;
        [[AVDB115MagnetCache shared] addLink:link catalogHint:(hint.length ? hint : field(@"name"))];
        added++;
    }
    return added;
}

+ (NSUInteger)ingestJSONObject:(id)obj catalogHint:(NSString *)hint {
    NSUInteger n = 0;
    @try {
        n = [self walk:obj catalogHint:hint depth:0];
    } @catch (NSException *ex) {
        n = 0;
    }
    return n;
}

+ (NSUInteger)ingestData:(NSData *)data url:(NSURL *)url catalogHint:(NSString *)hint {
    if (data.length == 0) return 0;
    if (data.length > 2 * 1024 * 1024) return 0;
    NSString *hint2 = hint;
    if (hint2.length == 0 && url.path.length) hint2 = url.path;
    NSUInteger n = 0;
    id json = nil;
    @try {
        json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:nil];
    } @catch (NSException *ex) {
        json = nil;
    }
    if (json) n += [self ingestJSONObject:json catalogHint:hint2];
    if (n == 0) {
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (text.length) n += [self ingestRegexUTF8:text catalogHint:hint2];
    }
    return n;
}

+ (NSUInteger)ingestUTF8Bytes:(const void *)bytes length:(NSUInteger)length catalogHint:(NSString *)hint {
    if (!bytes || length < 16 || length > 2 * 1024 * 1024) return 0;
    NSData *data = [NSData dataWithBytes:bytes length:length];
    return [self ingestData:data url:nil catalogHint:hint];
}

+ (void)addHttpCaptureCount:(NSUInteger)n { if (n) gHttpCaptures += n; }
+ (void)setFileHarvestCount:(NSUInteger)n { gFileHarvest = n; }
+ (void)setPlaintextHarvestCount:(NSUInteger)n { gPlaintextHarvest = n; }
+ (void)setDartObjectScanCount:(NSUInteger)n { gDartObjectScan = n; }
+ (void)setURLSessionHookInstalled:(BOOL)ok { gURLSessionHook = ok; }
+ (void)setURLProtocolRegistered:(BOOL)ok { gURLProtocol = ok; }

+ (NSDictionary<NSString *, id> *)diagnosticSnapshot {
    BOOL dartHooks = NO;
    @try { dartHooks = [AVDB115DartRowHook isInstalled]; } @catch (NSException *ex) { dartHooks = NO; }
    NSUInteger cacheN = 0;
    @try {
        cacheN = [[AVDB115MagnetCache shared] linksForCatalog:nil].count;
    } @catch (NSException *ex) {
        cacheN = 0;
    }
    return @{
        @"urlSessionHook": gURLSessionHook ? @"1" : @"0",
        @"urlProtocol": gURLProtocol ? @"1" : @"0",
        @"httpCache": @(gHttpCaptures),
        @"fileCache": @(gFileHarvest),
        @"plaintextScan": @(gPlaintextHarvest),
        @"objectScan": @(gDartObjectScan),
        @"usableCache": @(cacheN),
        @"dartAppHooks": dartHooks ? @"1" : @"0",
    };
}

+ (NSString *)diagnosticLine {
    NSDictionary *s = [self diagnosticSnapshot];
    BOOL dart = [s[@"dartAppHooks"] isEqualToString:@"1"];
    return [NSString stringWithFormat:
            @"[诊断] NSURL钩子=%@ 协议=%@ 拦截缓存=%@ 文件缓存=%@ 明文扫描=%@ 对象扫描=%@ 可用缓存=%@ App.framework钩子=%@。不会请求带签名的磁力接口。",
            [s[@"urlSessionHook"] isEqualToString:@"1"] ? @"已安装" : @"未安装",
            [s[@"urlProtocol"] isEqualToString:@"1"] ? @"已注册" : @"未注册",
            s[@"httpCache"], s[@"fileCache"], s[@"plaintextScan"], s[@"objectScan"], s[@"usableCache"],
            dart ? @"已安装" : @"未安装"];
}

@end
