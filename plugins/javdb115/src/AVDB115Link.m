#import "AVDB115Link.h"

@implementation AVDB115Link

+ (NSRegularExpression *)magnetRegex {
    static NSRegularExpression *r;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        r = [NSRegularExpression regularExpressionWithPattern:@"magnet:\\?xt=urn:btih:[0-9a-fA-F]{32,40}[^\\s\\\"'<>]*" options:NSRegularExpressionCaseInsensitive error:nil];
    });
    return r;
}

+ (NSRegularExpression *)ed2kRegex {
    static NSRegularExpression *r;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        r = [NSRegularExpression regularExpressionWithPattern:@"ed2k://\\|file\\|[^|]+\\|\\d{1,13}\\|[0-9a-fA-F]{32}\\|/?" options:NSRegularExpressionCaseInsensitive error:nil];
    });
    return r;
}

+ (BOOL)isOfflineResource:(NSString *)text {
    NSString *s = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (s.length == 0) return NO;
    NSString *low = s.lowercaseString;
    return [low hasPrefix:@"magnet:?xt=urn:btih:"] || [low hasPrefix:@"ed2k://|file|"];
}

+ (NSArray<NSString *> *)offlineResourcesIn:(NSString *)text {
    if (text.length == 0) return @[];
    NSMutableArray *out = [NSMutableArray array];
    NSString *s = text;
    void (^collect)(NSRegularExpression *) = ^(NSRegularExpression *r) {
        NSArray *matches = [r matchesInString:s options:0 range:NSMakeRange(0, s.length)];
        for (NSTextCheckingResult *m in matches) {
            [out addObject:[s substringWithRange:m.range]];
        }
    };
    collect(self.magnetRegex);
    collect(self.ed2kRegex);
    return out;
}

+ (NSString *)firstOfflineResourceIn:(NSString *)text {
    NSString *trim = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([self isOfflineResource:trim]) return trim;
    return [self offlineResourcesIn:text].firstObject;
}

+ (NSString *)infoHashFromMagnet:(NSString *)magnet {
    NSRegularExpression *r = [NSRegularExpression regularExpressionWithPattern:@"xt=urn:btih:([0-9a-fA-F]{32,40})" options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *m = [r firstMatchInString:magnet options:0 range:NSMakeRange(0, magnet.length)];
    if (!m || m.numberOfRanges < 2) return nil;
    return [magnet substringWithRange:[m rangeAtIndex:1]];
}

+ (NSString *)displayNameFromLink:(NSString *)link {
    NSRegularExpression *dn = [NSRegularExpression regularExpressionWithPattern:@"[?&]dn=([^&]+)" options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *m = [dn firstMatchInString:link options:0 range:NSMakeRange(0, link.length)];
    if (m && m.numberOfRanges >= 2) {
        NSString *raw = [link substringWithRange:[m rangeAtIndex:1]];
        return [raw stringByRemovingPercentEncoding] ?: raw;
    }
    if ([link.lowercaseString hasPrefix:@"ed2k://|file|"]) {
        NSArray *parts = [link componentsSeparatedByString:@"|"];
        if (parts.count >= 3) {
            NSString *name = parts[2];
            return [name stringByRemovingPercentEncoding] ?: name;
        }
    }
    return nil;
}

@end
