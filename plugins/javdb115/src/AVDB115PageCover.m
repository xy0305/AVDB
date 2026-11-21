#import "AVDB115PageCover.h"
#import "AVDB115Catalog.h"
#import "AVDB115CoverResolver.h"

static NSString *const kReplaceKey = @"avdb115.pageCover.replaceEnabled";

@implementation AVDB115PageCoverSettings

+ (AVDB115PageCoverSettings *)shared {
    static AVDB115PageCoverSettings *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[AVDB115PageCoverSettings alloc] init]; });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
        if ([d objectForKey:kReplaceKey] == nil) {
            _replaceEnabled = YES; // default on, as requested
        } else {
            _replaceEnabled = [d boolForKey:kReplaceKey];
        }
    }
    return self;
}

- (void)setReplaceEnabled:(BOOL)replaceEnabled {
    _replaceEnabled = replaceEnabled;
    [NSUserDefaults.standardUserDefaults setBool:replaceEnabled forKey:kReplaceKey];
}

- (BOOL)hookArmed {
    // JavDB 1.9.41 loads covers through Dart Dio (IOHttpClientAdapter / dart:io
    // SecureSocket). Flutter.framework in this IPA has no NSURLSession symbols.
    // Cover URLs are https://c0.jdbstatic.com/covers/{xx}/{uid}.jpg and do not
    // contain a catalog number. No narrow native hook can rewrite the original
    // home/list/detail images without a global Dart TLS MITM, which is not installed.
    return NO;
}

- (NSString *)hookStatus {
    if (!self.replaceEnabled) {
        return @"原页封面替换已关闭。插件面板的高清预览仍可用。JavDB 首页/列表/详情封面保持原样。";
    }
    return @"原页封面替换开关为开，但当前无法对 JavDB 原页生效：封面由 Flutter Dart Dio / dart:io TLS 加载（非 NSURLSession/UIImage），API 需要 jdsignature，且 c0.jdbstatic.com/covers/{uid}.jpg 不含番号。未安装全局网络 hook。失败时会继续显示原封面。请在「高清封面源」面板按番号预览。";
}

@end

@implementation AVDB115PageCoverPolicy

+ (NSURL *)url:(NSString *)urlString {
    if (urlString.length == 0) return nil;
    return [NSURL URLWithString:urlString];
}

+ (BOOL)isJavDBCoverHost:(NSString *)host {
    host = host.lowercaseString;
    if ([host isEqualToString:@"jdbstatic.com"]) return YES;
    if ([host hasSuffix:@".jdbstatic.com"]) return YES;
    return NO;
}

+ (BOOL)isJavDBCoverURL:(NSString *)urlString {
    NSURL *url = [self url:urlString];
    if (![url.scheme.lowercaseString isEqualToString:@"https"]) return NO;
    if (url.user || url.password) return NO;
    if (![self isJavDBCoverHost:url.host]) return NO;
    NSString *path = url.path ?: @"";
    // First-party cover only, not /images logo or /samples stills.
    return [path rangeOfString:@"^/covers/[A-Za-z0-9]{2}/[A-Za-z0-9]+\\.(jpg|jpeg|webp)$" options:NSRegularExpressionSearch].location != NSNotFound;
}

+ (BOOL)isJavDBSampleURL:(NSString *)urlString {
    NSURL *url = [self url:urlString];
    if (![url.scheme.lowercaseString isEqualToString:@"https"]) return NO;
    if (![self isJavDBCoverHost:url.host]) return NO;
    NSString *path = url.path ?: @"";
    return [path rangeOfString:@"^/samples/" options:NSRegularExpressionSearch].location != NSNotFound;
}

+ (NSString *)movieUIDFromCoverURL:(NSString *)urlString {
    if (![self isJavDBCoverURL:urlString]) return nil;
    NSURL *url = [self url:urlString];
    NSString *base = url.lastPathComponent.stringByDeletingPathExtension;
    return base.length ? base : nil;
}

+ (NSString *)normalizedNumber:(id)raw {
    if (![raw isKindOfClass:[NSString class]]) return nil;
    NSString *s = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (s.length == 0) return nil;
    // Accept only values that parse as a catalog identity, never a free-text title.
    if (![AVDB115CatalogNumber identityKey:s] && ![AVDB115CatalogNumber parse:s]) return nil;
    return s;
}

+ (NSString *)numberFromUnit:(NSDictionary *)unit {
    if (![unit isKindOfClass:[NSDictionary class]]) return nil;
    // Prefer explicit number/code fields from the app binary; origin_title only if it is a number.
    for (NSString *key in @[@"number", @"code", @"origin_title", @"id"]) {
        NSString *value = [self normalizedNumber:unit[key]];
        if (value) {
            // `id` is often the opaque movie UID (AqXeXO), not a catalog number — skip UIDs.
            if ([key isEqualToString:@"id"] && ![value containsString:@"-"] && ![AVDB115CatalogNumber parse:value]) {
                continue;
            }
            if ([key isEqualToString:@"id"] && ![AVDB115CatalogNumber identityKey:value]) continue;
            return value;
        }
    }
    return nil;
}

+ (NSString *)coverURLFromUnit:(NSDictionary *)unit {
    if (![unit isKindOfClass:[NSDictionary class]]) return nil;
    for (NSString *key in @[@"cover_url", @"coverUrl", @"thumb_url", @"image_url", @"imageUrl", @"cover"]) {
        id raw = unit[key];
        if ([raw isKindOfClass:[NSString class]] && [self isJavDBCoverURL:raw]) return raw;
    }
    return nil;
}

+ (NSString *)numberBoundToCoverURL:(NSString *)urlString inUnit:(NSDictionary *)unit {
    if (![self isJavDBCoverURL:urlString]) return nil;
    NSString *unitCover = [self coverURLFromUnit:unit];
    if (!unitCover) return nil;
    NSURL *a = [self url:urlString];
    NSURL *b = [self url:unitCover];
    // Same UID / same path. Query strings are ignored.
    NSString *uidA = [self movieUIDFromCoverURL:urlString];
    NSString *uidB = [self movieUIDFromCoverURL:unitCover];
    if (!uidA || !uidB || ![uidA.lowercaseString isEqualToString:uidB.lowercaseString]) return nil;
    if (![a.host.lowercaseString isEqualToString:b.host.lowercaseString]) return nil;
    return [self numberFromUnit:unit];
}

+ (NSArray<NSString *> *)hqCandidatesIfRewritable:(NSString *)urlString
                                           unit:(NSDictionary *)unit
                                        enabled:(BOOL)enabled {
    if (!enabled) return nil;
    if ([self isJavDBSampleURL:urlString]) return nil;
    NSString *number = [self numberBoundToCoverURL:urlString inUnit:unit];
    if (number.length == 0) return nil;
    NSArray *rows = [AVDB115CoverResolver deterministicCandidatesForNumber:number enableDMM:YES enableMGS:YES];
    if (rows.count == 0) return nil;
    NSMutableArray *urls = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        if ([row[@"url"] isKindOfClass:[NSString class]]) [urls addObject:row[@"url"]];
    }
    return urls.count ? urls : nil;
}

+ (NSArray<NSDictionary *> *)unitsFromHomepageHTML:(NSString *)html {
    if (html.length == 0) return @[];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:
        @"<div class=\"item\">\\s*<a href=\"(/v/([^\"]+))\"[^>]*>.*?<img[^>]+src=\"(https://[^\"]+jdbstatic\\.com/covers/[^\"]+)\"[^>]*>.*?<strong>([^<]+)</strong>"
        options:NSRegularExpressionDotMatchesLineSeparators error:nil];
    NSMutableArray *out = [NSMutableArray array];
    [re enumerateMatchesInString:html options:0 range:NSMakeRange(0, html.length) usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags flags, BOOL *stop) {
        (void)flags; (void)stop;
        if (m.numberOfRanges < 5) return;
        NSString *uid = [html substringWithRange:[m rangeAtIndex:2]];
        NSString *cover = [html substringWithRange:[m rangeAtIndex:3]];
        NSString *number = [html substringWithRange:[m rangeAtIndex:4]];
        if (![self isJavDBCoverURL:cover]) return;
        if (![self normalizedNumber:number]) return;
        [out addObject:@{@"id": uid, @"cover_url": cover, @"number": number}];
    }];
    return out;
}

@end
