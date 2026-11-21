#import "AVDB115Settings.h"
#import <Security/Security.h>

static NSString *const kLegacyCookieDefaultsKey = @"avdb115.plugin.cookie";
static NSString *const kFolderKey = @"avdb115.plugin.folderCID";
static NSString *const kKeychainService = @"com.avdb115.plugin";
static NSString *const kKeychainAccount = @"115-cookie";

@implementation AVDB115Settings

+ (AVDB115Settings *)shared {
    static AVDB115Settings *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[AVDB115Settings alloc] init]; });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        NSString *fromKeychain = [AVDB115Settings keychainCookie];
        NSString *legacy = [[NSUserDefaults standardUserDefaults] stringForKey:kLegacyCookieDefaultsKey];
        if (fromKeychain.length) {
            _cookie = fromKeychain;
            if (legacy.length) {
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:kLegacyCookieDefaultsKey];
            }
        } else if (legacy.length) {
            _cookie = [AVDB115Settings normalizeCookie:legacy];
            [AVDB115Settings writeKeychainCookie:_cookie];
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:kLegacyCookieDefaultsKey];
        } else {
            _cookie = @"";
        }
        _folderCID = [[NSUserDefaults standardUserDefaults] stringForKey:kFolderKey] ?: @"";
    }
    return self;
}

- (void)setCookie:(NSString *)cookie {
    _cookie = [AVDB115Settings normalizeCookie:cookie] ?: @"";
    [AVDB115Settings writeKeychainCookie:_cookie];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kLegacyCookieDefaultsKey];
}

- (void)setFolderCID:(NSString *)folderCID {
    _folderCID = [folderCID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    [[NSUserDefaults standardUserDefaults] setObject:_folderCID forKey:kFolderKey];
}

- (BOOL)isConfigured {
    NSString *c = [AVDB115Settings normalizeCookie:self.cookie];
    return [c containsString:@"UID="] && [c containsString:@"CID="] && [c containsString:@"SEID="]
        && self.folderCID.length > 0;
}

- (NSString *)missingHint {
    NSString *c = [AVDB115Settings normalizeCookie:self.cookie];
    NSMutableArray *miss = [NSMutableArray array];
    if (![c containsString:@"UID="]) [miss addObject:@"UID"];
    if (![c containsString:@"CID="]) [miss addObject:@"Cookie 里的 CID"];
    if (![c containsString:@"SEID="]) [miss addObject:@"SEID"];
    if (self.folderCID.length == 0) [miss addObject:@"离线目录 CID"];
    if (miss.count == 0) return @"";
    return [@"请先在 115 插件面板填写：" stringByAppendingString:[miss componentsJoinedByString:@"、"]];
}

+ (NSString *)normalizeCookie:(NSString *)raw {
    NSString *s = raw ?: @"";
    s = [s stringByReplacingOccurrencesOfString:@"\r\n" withString:@" "];
    s = [s stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    NSRegularExpression *semi = [NSRegularExpression regularExpressionWithPattern:@"\\s*;\\s*" options:0 error:nil];
    s = [semi stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"; "];
    NSRegularExpression *sp = [NSRegularExpression regularExpressionWithPattern:@"[ \\t]{2,}" options:0 error:nil];
    s = [sp stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@" "];
    return [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

+ (NSString *)extractUIDFromCookie:(NSString *)cookie {
    NSString *c = [self normalizeCookie:cookie];
    NSRegularExpression *r = [NSRegularExpression regularExpressionWithPattern:@"(?:^|;\\s*)UID=(\\d+)" options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *m = [r firstMatchInString:c options:0 range:NSMakeRange(0, c.length)];
    if (!m || m.numberOfRanges < 2 || [m rangeAtIndex:1].location == NSNotFound) return nil;
    return [c substringWithRange:[m rangeAtIndex:1]];
}

+ (NSDictionary *)keychainQuery {
    return @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kKeychainService,
        (__bridge id)kSecAttrAccount: kKeychainAccount,
    };
}

+ (NSString *)keychainCookie {
    NSMutableDictionary *query = [[self keychainQuery] mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || !result) return @"";
    NSData *data = (__bridge_transfer NSData *)result;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

+ (void)writeKeychainCookie:(NSString *)cookie {
    SecItemDelete((__bridge CFDictionaryRef)[self keychainQuery]);
    if (cookie.length == 0) return;
    NSDictionary *add = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kKeychainService,
        (__bridge id)kSecAttrAccount: kKeychainAccount,
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        (__bridge id)kSecValueData: [cookie dataUsingEncoding:NSUTF8StringEncoding],
    };
    SecItemAdd((__bridge CFDictionaryRef)add, NULL);
}

@end
