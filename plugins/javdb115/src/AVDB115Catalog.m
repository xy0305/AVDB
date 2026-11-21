#include <stdlib.h>
#include <string.h>
#import "AVDB115Catalog.h"

static NSString *AVDB115FoldedCode(NSString *raw) {
    NSString *s = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return s.uppercaseString;
}

static NSTextCheckingResult *AVDB115FirstMatch(NSString *pattern, NSString *text) {
    if (text.length == 0) return nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    return [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
}

static NSString *AVDB115Group(NSTextCheckingResult *m, NSString *text, NSUInteger i) {
    if (!m || i >= m.numberOfRanges || [m rangeAtIndex:i].location == NSNotFound) return nil;
    return [text substringWithRange:[m rangeAtIndex:i]];
}

@implementation AVDB115CatalogNumber

+ (instancetype)parse:(NSString *)raw {
    NSString *s = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    NSTextCheckingResult *m = AVDB115FirstMatch(@"^([0-9]{0,4}[a-z]{2,10})-?0*([0-9]{1,6})$", s);
    if (!m) return nil;
    NSString *label = AVDB115Group(m, s, 1);
    NSInteger serial = AVDB115Group(m, s, 2).integerValue;
    if (label.length == 0 || serial <= 0 || [label hasPrefix:@"fc2"]) return nil;
    AVDB115CatalogNumber *n = [[AVDB115CatalogNumber alloc] init];
    n->_label = label;
    n->_serial = serial;
    return n;
}

+ (NSString *)identityKey:(NSString *)raw {
    NSString *text = AVDB115FoldedCode(raw);
    NSArray *patterns = @[
        @"^([A-Z]{1,4}[0-9]{1,4})[-_ ]([0-9]{2,10})$",
        @"^([0-9]{1,4}[A-Z]{2,12})[-_ ]?([0-9]{2,10})$",
        @"^([A-Z]{2,12})[-_ ]?([0-9]{2,10})$",
    ];
    for (NSString *pat in patterns) {
        NSTextCheckingResult *m = AVDB115FirstMatch(pat, text);
        if (!m) continue;
        NSString *prefix = AVDB115Group(m, text, 1);
        NSString *serial = AVDB115Group(m, text, 2);
        if ([prefix hasPrefix:@"FC2"]) return nil;
        unsigned long long n = strtoull(serial.UTF8String, NULL, 10);
        if (n == 0) return nil;
        return [NSString stringWithFormat:@"%@-%llu", prefix, n];
    }
    return nil;
}

+ (NSString *)keyWithoutLeadingDigits:(NSString *)raw {
    NSString *text = AVDB115FoldedCode(raw);
    NSArray *patterns = @[
        @"^([A-Z]{1,4}[0-9]{1,4})[-_ ]([0-9]{2,10})$",
        @"^([0-9]{1,4}[A-Z]{2,12})[-_ ]?([0-9]{2,10})$",
        @"^([A-Z]{2,12})[-_ ]?([0-9]{2,10})$",
    ];
    for (NSString *pat in patterns) {
        NSTextCheckingResult *m = AVDB115FirstMatch(pat, text);
        if (!m) continue;
        NSString *prefix = AVDB115Group(m, text, 1);
        NSString *serial = AVDB115Group(m, text, 2);
        if (prefix.length == 0 || ![[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[prefix characterAtIndex:0]]) {
            return nil;
        }
        NSUInteger i = 0;
        while (i < prefix.length && [[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[prefix characterAtIndex:i]]) i++;
        NSString *rest = [prefix substringFromIndex:i];
        return [self identityKey:[NSString stringWithFormat:@"%@-%@", rest, serial]];
    }
    return nil;
}

+ (BOOL)identity:(NSString *)candidate matches:(NSString *)wanted {
    NSString *a = [self identityKey:candidate];
    NSString *b = [self identityKey:wanted];
    if (!a || !b) return NO;
    if ([a isEqualToString:b]) return YES;
    NSString *ca = [self keyWithoutLeadingDigits:candidate];
    NSString *wb = [self keyWithoutLeadingDigits:wanted];
    return (ca && [ca isEqualToString:b]) || (wb && [wb isEqualToString:a]);
}

@end

static NSString *AVDB115Pad(NSInteger n, NSInteger width) {
    NSString *digits = [NSString stringWithFormat:@"%ld", (long)n];
    if ((NSInteger)digits.length >= width) return digits;
    return [[@"" stringByPaddingToLength:width - digits.length withString:@"0" startingAtIndex:0] stringByAppendingString:digits];
}

@implementation AVDB115DMMCoverURLs

+ (NSString *)awsHost { return @"https://awsimgsrc.dmm.co.jp/pics_dig"; }
+ (NSString *)picsHost { return @"https://pics.dmm.co.jp"; }

+ (NSString *)makePrefix:(NSString *)prefix label:(NSString *)label serial:(NSInteger)serial width:(NSInteger)width {
    return [NSString stringWithFormat:@"%@%@%@", prefix ?: @"", label, AVDB115Pad(serial, width)];
}

+ (NSArray<NSString *> *)cidCandidatesForNumber:(NSString *)number {
    AVDB115CatalogNumber *p = [AVDB115CatalogNumber parse:number];
    if (!p) return @[];
    NSMutableArray *out = [NSMutableArray array];
    void (^add)(NSString *) = ^(NSString *c) {
        if (c.length && ![out containsObject:c]) [out addObject:c];
    };
    NSDictionary *rule = AVDB115DMMSeedRuleForLabel(p.label);
    if (rule) {
        add([self makePrefix:rule[@"prefix"] ?: @"" label:p.label serial:p.serial width:[rule[@"width"] integerValue]]);
    }
    add([self makePrefix:@"" label:p.label serial:p.serial width:5]);
    add([self makePrefix:@"" label:p.label serial:p.serial width:3]);
    if (out.count > 4) return [out subarrayWithRange:NSMakeRange(0, 4)];
    return out;
}

+ (NSArray<NSString *> *)digitalURLsForCID:(NSString *)cid {
    NSString *aws = [self awsHost];
    return @[
        [NSString stringWithFormat:@"%@/digital/video/%@/%@ps.jpg", aws, cid, cid],
        [NSString stringWithFormat:@"%@/digital/video/%@/%@pl.jpg", aws, cid, cid],
    ];
}

+ (NSArray<NSString *> *)legacyURLsForCID:(NSString *)cid {
    NSString *pics = [self picsHost];
    return @[
        [NSString stringWithFormat:@"%@/digital/video/%@/%@pl.jpg", pics, cid, cid],
        [NSString stringWithFormat:@"%@/mono/movie/adult/%@/%@pl.jpg", pics, cid, cid],
    ];
}

+ (NSString *)cidFromImageURL:(NSString *)source {
    NSURL *url = [NSURL URLWithString:source];
    if (!url) return nil;
    NSString *path = url.path ?: @"";
    NSTextCheckingResult *m = AVDB115FirstMatch(@"/((?:digital/(?:video|amateur)|mono/movie(?:/adult|/japanese)?))/([a-z0-9_]+)/([a-z0-9_]+)(?:ps|pl|jp)\\.jpg$", path);
    if (!m) return nil;
    NSString *a = AVDB115Group(m, path, 2);
    NSString *b = AVDB115Group(m, path, 3);
    return [a isEqualToString:b] ? a : nil;
}

+ (NSArray<NSString *> *)upgradeImageURL:(NSString *)source {
    NSURL *url = [NSURL URLWithString:source];
    NSString *host = url.host.lowercaseString;
    if (![host isEqualToString:@"pics.dmm.co.jp"] && ![host isEqualToString:@"awsimgsrc.dmm.co.jp"]) return @[];
    NSString *path = url.path ?: @"";
    if ([host isEqualToString:@"awsimgsrc.dmm.co.jp"]) {
        if (![path hasPrefix:@"/pics_dig"]) return @[];
        path = [path substringFromIndex:@"/pics_dig".length];
    }
    NSTextCheckingResult *digital = AVDB115FirstMatch(@"^/digital/video/([a-z0-9_]+)/([a-z0-9_]+)(?:ps|pl)\\.jpg$", path);
    if (digital) {
        NSString *a = AVDB115Group(digital, path, 1);
        NSString *b = AVDB115Group(digital, path, 2);
        if ([a isEqualToString:b]) return [self digitalURLsForCID:a];
    }
    NSTextCheckingResult *mono = AVDB115FirstMatch(@"^/mono/movie/(?:adult/|japanese/)?([a-z0-9_]+)/([a-z0-9_]+)(?:ps|pl)\\.jpg$", path);
    if (mono) {
        NSString *a = AVDB115Group(mono, path, 1);
        NSString *b = AVDB115Group(mono, path, 2);
        if ([a isEqualToString:b]) {
            NSString *aws = [self awsHost];
            return @[
                [NSString stringWithFormat:@"%@/mono/movie/%@/%@ps.jpg", aws, a, a],
                [NSString stringWithFormat:@"%@/mono/movie/%@/%@pl.jpg", aws, a, a],
            ];
        }
    }
    return @[];
}

@end

@implementation AVDB115MGSCoverURLs

+ (NSDictionary<NSString *, NSString *> *)makers {
    return @{
        @"ABF": @"prestige",
        @"ABW": @"prestige",
        @"ABP": @"prestige",
        @"CHN": @"prestige",
        @"JUFE": @"prestige",
        @"MAAN": @"prestige",
        @"PPT": @"prestige",
        @"390JAC": @"jackson",
    };
}

+ (NSArray<NSString *> *)candidatesForNumber:(NSString *)number {
    NSString *raw = [number stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].uppercaseString;
    NSTextCheckingResult *m = AVDB115FirstMatch(@"^([A-Z]+|390JAC)-([0-9]{2,5})$", raw);
    if (!m) return @[];
    NSString *prefix = AVDB115Group(m, raw, 1);
    NSInteger index = AVDB115Group(m, raw, 2).integerValue;
    if (index <= 0) return @[];
    NSString *maker = [self makers][prefix];
    if (!maker) return @[];
    NSString *lower = prefix.lowercaseString;
    NSString *number3 = AVDB115Pad(index, 3);
    NSString *plain = [NSString stringWithFormat:@"%ld", (long)index];
    NSArray *numbers = [number3 isEqualToString:plain] ? @[plain] : @[plain, number3];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *digits in numbers) {
        NSString *base = [NSString stringWithFormat:@"https://image.mgstage.com/images/%@/%@/%@", maker, lower, digits];
        [out addObject:[NSString stringWithFormat:@"%@/pf_e_%@-%@.jpg", base, lower, digits]];
        [out addObject:[NSString stringWithFormat:@"%@/pf_o1_%@-%@.jpg", base, lower, digits]];
    }
    return out;
}

@end

@implementation AVDB115AmazonImage

+ (BOOL)allowedImage:(NSURL *)url {
    if (![url.scheme.lowercaseString isEqualToString:@"https"]) return NO;
    NSString *host = url.host.lowercaseString;
    if (![host isEqualToString:@"m.media-amazon.com"] && ![host isEqualToString:@"images-na.ssl-images-amazon.com"]) return NO;
    if (url.user || url.password || url.port || url.query || url.fragment) return NO;
    if ([url.absoluteString containsString:@"%"]) return NO;
    NSString *path = url.path ?: @"";
    if (AVDB115FirstMatch(@"^/images/I/[A-Za-z0-9+_.-]{1,150}\\.jpg$", path)) return YES;
    return AVDB115FirstMatch(@"^/images/P/[A-Z0-9]{10}\\.0[19]\\.MAIN\\._SCRM_\\.jpg$", path) != nil;
}

+ (NSURL *)originalImage:(NSURL *)url {
    if (![self allowedImage:url]) return nil;
    NSString *path = url.path ?: @"";
    NSTextCheckingResult *m = AVDB115FirstMatch(@"^(/images/I/[A-Za-z0-9+-]{1,100})\\._(?:AC_)?SL[1-9][0-9]{1,3}_\\.jpg$", path);
    if (!m) return url;
    NSString *stem = AVDB115Group(m, path, 1);
    NSURL *original = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@%@.jpg", url.host, stem]];
    return [self allowedImage:original] ? original : nil;
}

@end

@implementation AVDB115CoverPolicy

+ (BOOL)allowedPublicImageURL:(NSURL *)url {
    if (![url.scheme.lowercaseString isEqualToString:@"https"]) return NO;
    if (url.user || url.password || url.port || url.query || url.fragment) return NO;
    NSString *host = url.host.lowercaseString;
    NSString *p = url.path.lowercaseString ?: @"";
    if ([host isEqualToString:@"image.mgstage.com"]) {
        return [p hasPrefix:@"/images/"] && ([p containsString:@"/pf_e_"] || [p containsString:@"/pf_o1_"]) && [p hasSuffix:@".jpg"];
    }
    if ([host isEqualToString:@"awsimgsrc.dmm.co.jp"] || [host isEqualToString:@"pics.dmm.co.jp"]) {
        if ([host isEqualToString:@"awsimgsrc.dmm.co.jp"] && ![p hasPrefix:@"/pics_dig/"]) return NO;
        return [AVDB115DMMCoverURLs cidFromImageURL:url.absoluteString] != nil;
    }
    if ([host isEqualToString:@"m.media-amazon.com"] || [host isEqualToString:@"images-na.ssl-images-amazon.com"]) {
        return [AVDB115AmazonImage allowedImage:url];
    }
    if ([host isEqualToString:@"www.javbus.com"]) {
        return [self allowedJavBusCoverURL:url];
    }
    return NO;
}

+ (BOOL)allowedJavBusCoverURL:(NSURL *)url {
    if (![url.scheme.lowercaseString isEqualToString:@"https"]) return NO;
    if (![url.host.lowercaseString isEqualToString:@"www.javbus.com"]) return NO;
    if (url.user || url.password || url.port || url.query || url.fragment) return NO;
    // First-party large cover only (AVDB JavBusPoster): /pics/cover/*_b.jpg
    return AVDB115FirstMatch(@"^/pics/cover/[A-Za-z0-9._-]+_b\\.jpg$", url.path ?: @"") != nil;
}

+ (BOOL)eligiblePortraitWidth:(NSInteger)width height:(NSInteger)height {
    if (width < 360 || height < 500) return NO;
    double r = (double)width / (double)height;
    return r >= 0.5 && r <= 0.82;
}

+ (BOOL)htmlLooksLikeChallenge:(NSString *)html finalURL:(NSURL *)finalURL {
    NSString *u = finalURL.absoluteString.lowercaseString ?: @"";
    if ([u containsString:@"/doc/driver-verify"] || [u containsString:@"validatecaptcha"] || [u containsString:@"/cdn-cgi/challenge"]) {
        return YES;
    }
    NSString *low = html.lowercaseString ?: @"";
    NSArray *markers = @[
        @"validatecaptcha", @"/errors/validatecaptcha", @"cf-chl", @"just a moment",
        @"cf-challenge", @"driver-verify", @"checking your browser",
    ];
    for (NSString *m in markers) {
        if ([low containsString:m]) return YES;
    }
    return NO;
}

@end
