#import "AVDB115MagnetJSON.h"
#import "AVDB115MagnetCache.h"
#import "AVDB115VisibleMagnets.h"
#import "AVDB115Link.h"
#import "AVDB115DartRowHook.h"
#import "AVDB115DetailActions.h"

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

+ (NSString *)stringValue:(id)v {
    if ([v isKindOfClass:NSString.class]) {
        NSString *s = [(NSString *)v stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        return s.length ? s : nil;
    }
    if ([v isKindOfClass:NSNumber.class]) return [((NSNumber *)v) stringValue];
    return nil;
}

+ (NSString *)catalogFromObject:(id)obj {
    if ([obj isKindOfClass:NSDictionary.class]) {
        NSDictionary *d = obj;
        // Only official number/code fields, never a magnet file name
        // (clear-sis-01 must not become SIS-01 for the whole movie).
        for (NSString *key in @[@"number", @"code"]) {
            NSString *v = [self stringValue:d[key]];
            NSString *n = [AVDB115DetailPagePolicy catalogNumberInText:v];
            if (n.length) return n;
        }
    } else if ([obj isKindOfClass:NSArray.class]) {
        for (id child in (NSArray *)obj) {
            NSString *n = [self catalogFromObject:child];
            if (n.length) return n;
        }
    }
    return nil;
}

+ (void)bindMovieIndexIfPresent:(NSDictionary *)d {
    if (![d isKindOfClass:NSDictionary.class]) return;
    // Magnet rows have hash/url and their own id; do not treat that id as a movie id.
    if (d[@"hash"] || ([self stringValue:d[@"url"]].length &&
                       [[self stringValue:d[@"url"]].lowercaseString hasPrefix:@"ed2k://"])) {
        return;
    }
    NSString *mid = [self stringValue:d[@"id"]] ?: [self stringValue:d[@"movie_id"]];
    if ([AVDB115MagnetCache movieIdFromURLString:mid]) {
        // mid itself is a path; extract.
        mid = [AVDB115MagnetCache movieIdFromURLString:mid];
    }
    if (mid.length == 0) return;
    if ([mid containsString:@"/"]) mid = [AVDB115MagnetCache movieIdFromURLString:mid];
    mid = [AVDB115MagnetCache movieIdFromURLString:
           [NSString stringWithFormat:@"/api/v2/movies/%@/magnets", mid ?: @""]];
    if (mid.length == 0) return;
    if ([mid containsString:@"/"] || mid.length < 2 || mid.length > 64) return;
    NSString *number = [self catalogFromObject:d];
    if (number.length) {
        [[AVDB115MagnetCache shared] bindMovieId:mid toCatalog:number];
    }
}

+ (NSUInteger)ingestOneDictionary:(NSDictionary *)d catalogHint:(NSString *)hint movieId:(NSString *)movieId {
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
    NSString *mid = movieId.length ? movieId : [AVDB115MagnetCache movieIdFromURLString:url];
    [[AVDB115MagnetCache shared] addLink:link catalogHint:catalog movieId:mid];
    return 1;
}

+ (NSUInteger)walk:(id)obj catalogHint:(NSString *)hint movieId:(NSString *)movieId depth:(NSInteger)depth {
    if (depth > 8 || !obj || obj == (id)NSNull.null) return 0;
    NSUInteger n = 0;
    if ([obj isKindOfClass:NSDictionary.class]) {
        NSDictionary *d = obj;
        [self bindMovieIndexIfPresent:d];
        NSString *unitNumber = [self catalogFromObject:d];
        NSString *childHint = hint;
        if (unitNumber.length) childHint = hint.length ? hint : unitNumber;
        NSString *unitId = [self stringValue:d[@"id"]] ?: [self stringValue:d[@"movie_id"]];
        if (d[@"hash"] || ([self stringValue:d[@"url"]].length &&
                           [[self stringValue:d[@"url"]].lowercaseString hasPrefix:@"ed2k://"])) {
            unitId = nil; // magnet row id is not a movie id
        }
        if (unitId.length) {
            NSString *checked = [AVDB115MagnetCache movieIdFromURLString:
                                 [NSString stringWithFormat:@"/api/v2/movies/%@/magnets", unitId]];
            unitId = checked;
        }
        NSString *childId = movieId.length ? movieId : unitId;
        n += [self ingestOneDictionary:d catalogHint:childHint movieId:childId];
        // Common envelopes: { "data": [ Magnets ] } or { "data": { "magnets": [...] } }.
        for (id key in d) {
            id child = d[key];
            if ([child isKindOfClass:NSDictionary.class] || [child isKindOfClass:NSArray.class]) {
                n += [self walk:child catalogHint:childHint movieId:childId depth:depth + 1];
            } else if ([child isKindOfClass:NSString.class]) {
                NSString *fromURL = [AVDB115MagnetCache movieIdFromURLString:child];
                if (fromURL.length && !childId.length) childId = fromURL;
            }
        }
        (void)childId;
    } else if ([obj isKindOfClass:NSArray.class]) {
        // If any row in this magnets array already carries the 番号, attribute
        // the whole batch (siblings may omit it in `name`).
        NSString *batchHint = hint ?: [self catalogFromObject:obj];
        for (id child in (NSArray *)obj) {
            n += [self walk:child catalogHint:batchHint movieId:movieId depth:depth + 1];
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
        [[AVDB115MagnetCache shared] addLink:link catalogHint:(hint.length ? hint : field(@"name")) movieId:[AVDB115MagnetCache movieIdFromURLString:hint]];
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
        [[AVDB115MagnetCache shared] addLink:link catalogHint:(hint.length ? hint : field(@"name")) movieId:[AVDB115MagnetCache movieIdFromURLString:hint]];
        added++;
    }
    return added;
}

+ (NSUInteger)ingestJSONObject:(id)obj catalogHint:(NSString *)hint {
    NSUInteger n = 0;
    @try {
        n = [self walk:obj catalogHint:hint movieId:[AVDB115MagnetCache movieIdFromURLString:hint] depth:0];
    } @catch (NSException *ex) {
        n = 0;
    }
    return n;
}

+ (NSString *)utf8Prefix:(NSData *)data limit:(NSUInteger)limit {
    if (data.length == 0) return nil;
    NSUInteger n = MIN(limit, data.length);
    return [[NSString alloc] initWithBytes:data.bytes length:n encoding:NSUTF8StringEncoding];
}

+ (NSUInteger)ingestMovieIndexFromData:(NSData *)data {
    if (data.length < 16 || data.length > 2 * 1024 * 1024) return 0;
    id json = nil;
    @try {
        json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:nil];
    } @catch (NSException *ex) {
        json = nil;
    }
    if (!json) return 0;
    NSUInteger before = 0; // bind-only; count objects visited with a bind attempt
    @try {
        [self walkMovieIndex:json depth:0 count:&before];
    } @catch (NSException *ex) {
    }
    return before;
}

+ (void)walkMovieIndex:(id)obj depth:(NSInteger)depth count:(NSUInteger *)count {
    if (depth > 8 || !obj || obj == (id)NSNull.null) return;
    if ([obj isKindOfClass:NSDictionary.class]) {
        NSDictionary *d = obj;
        NSUInteger was = *count;
        [self bindMovieIndexIfPresent:d];
        // bindMovieIndexIfPresent does not report; bump when both id and number exist and it is not a magnet row.
        if (!d[@"hash"] && ([self catalogFromObject:d].length) && (d[@"id"] || d[@"movie_id"])) {
            *count = was + 1;
        }
        for (id key in d) {
            id child = d[key];
            if ([child isKindOfClass:NSDictionary.class] || [child isKindOfClass:NSArray.class]) {
                [self walkMovieIndex:child depth:depth + 1 count:count];
            }
        }
    } else if ([obj isKindOfClass:NSArray.class]) {
        for (id child in (NSArray *)obj) [self walkMovieIndex:child depth:depth + 1 count:count];
    }
}

+ (NSUInteger)ingestData:(NSData *)data url:(NSURL *)url catalogHint:(NSString *)hint {
    if (data.length == 0) return 0;
    if (data.length > 2 * 1024 * 1024) return 0;
    NSString *probe = [self utf8Prefix:data limit:8192] ?: @"";
    if (probe.length == 0 && data.length > 0) {
        // Binary / mixed cache file: still search a latin-1 window for the path.
        probe = [[NSString alloc] initWithBytes:data.bytes
                                         length:MIN((NSUInteger)8192, data.length)
                                       encoding:NSISOLatin1StringEncoding] ?: @"";
    }
    NSString *movieId = [AVDB115MagnetCache movieIdFromURLString:url.absoluteString] ?:
                        [AVDB115MagnetCache movieIdFromURLString:url.path] ?:
                        [AVDB115MagnetCache movieIdFromURLString:hint] ?:
                        [AVDB115MagnetCache movieIdFromURLString:probe];
    // Full-file scan for /api/vN/movies/{id}/magnets if the header window missed it.
    if (!movieId.length && data.length > 8192) {
        NSString *more = [[NSString alloc] initWithBytes:data.bytes
                                                  length:MIN((NSUInteger)65536, data.length)
                                                encoding:NSISOLatin1StringEncoding];
        movieId = [AVDB115MagnetCache movieIdFromURLString:more];
    }
    if (movieId.length) {
        NSDate *now = [NSDate date];
        [[AVDB115MagnetCache shared] noteMagnetsMovieId:movieId seenAt:now];
    }
    NSString *hint2 = hint;
    if (hint2.length == 0 && movieId.length) hint2 = nil; // do not key by the raw path
    else if (hint2.length == 0 && url.path.length && ![AVDB115MagnetCache movieIdFromURLString:url.path]) {
        hint2 = url.path;
    }
    @try { [self ingestMovieIndexFromData:data]; } @catch (NSException *ex) {}
    NSUInteger n = 0;
    id json = nil;
    @try {
        json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:nil];
    } @catch (NSException *ex) {
        json = nil;
    }
    if (json) {
        NSString *walkHint = hint2;
        n += [self walk:json catalogHint:walkHint movieId:movieId depth:0];
    }
    if (n == 0) {
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSString *regexHint = hint2;
        if (regexHint.length == 0 && movieId.length) {
            regexHint = [NSString stringWithFormat:@"/api/v2/movies/%@/magnets", movieId];
        }
        if (text.length) n += [self ingestRegexUTF8:text catalogHint:regexHint];
    }
    if (n && movieId.length) {
        [[AVDB115MagnetCache shared] bindMovieIdToContextIfNamesMatch:movieId];
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
    return [self diagnosticLineForCatalog:nil];
}

+ (NSString *)diagnosticLineForCatalog:(NSString *)number {
    NSDictionary *s = [self diagnosticSnapshot];
    BOOL dart = [s[@"dartAppHooks"] isEqualToString:@"1"];
    NSString *base = [NSString stringWithFormat:
            @"[诊断] NSURL钩子=%@ 协议=%@ 拦截缓存=%@ 文件缓存=%@ 明文扫描=%@ 对象扫描=%@ 可用缓存=%@ App.framework钩子=%@。不会请求带签名的磁力接口。",
            [s[@"urlSessionHook"] isEqualToString:@"1"] ? @"已安装" : @"未安装",
            [s[@"urlProtocol"] isEqualToString:@"1"] ? @"已注册" : @"未注册",
            s[@"httpCache"], s[@"fileCache"], s[@"plaintextScan"], s[@"objectScan"], s[@"usableCache"],
            dart ? @"已安装" : @"未安装"];
    if (number.length == 0) return base;
    NSString *extra = nil;
    @try {
        extra = [[AVDB115MagnetCache shared] attributionDiagnosticForCatalog:number];
    } @catch (NSException *ex) {
        extra = nil;
    }
    if (extra.length == 0) return base;
    // Insert attribution before the closing promise so a mismatch is obvious.
    return [NSString stringWithFormat:@"[诊断] NSURL钩子=%@ 协议=%@ 拦截缓存=%@ 文件缓存=%@ 明文扫描=%@ 对象扫描=%@ 可用缓存=%@ %@ App.framework钩子=%@。不会请求带签名的磁力接口。",
            [s[@"urlSessionHook"] isEqualToString:@"1"] ? @"已安装" : @"未安装",
            [s[@"urlProtocol"] isEqualToString:@"1"] ? @"已注册" : @"未注册",
            s[@"httpCache"], s[@"fileCache"], s[@"plaintextScan"], s[@"objectScan"], s[@"usableCache"],
            extra,
            dart ? @"已安装" : @"未安装"];
}

@end
