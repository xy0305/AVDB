// Generated from AVDB DMMLabelSeed (feat/avfan-hd-covers-354 / Build 282).
// Public CID prefix table only. Do not edit by hand.
#import "AVDB115Catalog.h"

typedef struct { const char *label; const char *prefix; int width; } AVDB115DMMRule;
static const AVDB115DMMRule kAVDB115DMMRules[] = {
    {"abp", "118", 5},
    {"ang", "1", 5},
    {"baku", "h_086", 5},
    {"bskc", "", 3},
    {"chn", "118", 5},
    {"chuc", "h_491", 5},
    {"ddh", "", 3},
    {"debz", "", 3},
    {"dldss", "1", 5},
    {"docd", "h_1711", 5},
    {"drpt", "1", 5},
    {"dvdes", "1", 5},
    {"embm", "h_1650", 5},
    {"faleno", "1", 5},
    {"fcdss", "1", 5},
    {"fera", "h_086", 5},
    {"fgan", "h_1440", 5},
    {"flav", "1", 5},
    {"fns", "1", 5},
    {"fsbk", "h_491", 5},
    {"fsdss", "1", 5},
    {"fsnf", "1", 5},
    {"ftbd", "5533", 5},
    {"fthtd", "1", 5},
    {"ftkd", "1", 5},
    {"gass", "71", 5},
    {"goji", "h_1729", 5},
    {"gshrb", "h_346", 5},
    {"gsumk", "h_1780", 5},
    {"gvh", "13", 5},
    {"hmdnc", "", 3},
    {"hnamh", "1", 5},
    {"hnbr", "h_1664", 5},
    {"hodv", "5642", 5},
    {"hrsm", "h_1745", 5},
    {"hskvr", "h_1840", 5},
    {"hzgd", "h_1100", 5},
    {"iro", "h_086", 5},
    {"jera", "1", 5},
    {"jimmy", "1", 5},
    {"jrze", "h_086", 5},
    {"jura", "h_086", 5},
    {"lkb", "1", 5},
    {"lock", "h_491", 5},
    {"maan", "h_1711", 5},
    {"marn", "5050", 5},
    {"mbd", "433", 5},
    {"meko", "h_1160", 5},
    {"mfcw", "", 3},
    {"milk", "h_1240", 5},
    {"murikuri", "1", 5},
    {"mxgs", "h_068", 5},
    {"nacr", "h_237", 5},
    {"neo", "433", 5},
    {"nhdtc", "1", 5},
    {"nmsl", "h_1814", 5},
    {"nsm", "h_1342", 5},
    {"okk", "1", 5},
    {"oreco", "", 3},
    {"ozk", "1", 5},
    {"pts", "h_021", 5},
    {"rebd", "h_346", 5},
    {"rebdb", "h_346", 5},
    {"san", "h_796", 5},
    {"sbgvr", "1", 5},
    {"sbkd", "", 3},
    {"sdde", "1", 5},
    {"sdmu", "1", 5},
    {"skmj", "h_1324", 5},
    {"sods", "1", 5},
    {"spz", "h_1664", 5},
    {"ss", "h_113", 5},
    {"star", "1", 5},
    {"stars", "1", 5},
    {"start", "1", 5},
    {"sw", "1", 5},
    {"tmavr", "55", 5},
    {"totk", "h_1133", 5},
    {"tsds", "5013", 5},
    {"umd", "125", 5},
    {"wawa", "1", 5},
    {"wsa", "2", 5},
};
static const size_t kAVDB115DMMRuleCount = sizeof(kAVDB115DMMRules) / sizeof(kAVDB115DMMRules[0]);

NSDictionary<NSString *, NSDictionary *> *AVDB115DMMSeedTable(void) {
    static NSDictionary *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *m = [NSMutableDictionary dictionaryWithCapacity:kAVDB115DMMRuleCount];
        for (size_t i = 0; i < kAVDB115DMMRuleCount; i++) {
            NSString *label = [NSString stringWithUTF8String:kAVDB115DMMRules[i].label];
            m[label] = @{
                @"prefix": [NSString stringWithUTF8String:kAVDB115DMMRules[i].prefix],
                @"width": @(kAVDB115DMMRules[i].width),
            };
        }
        table = [m copy];
    });
    return table;
}

NSDictionary *AVDB115DMMSeedRuleForLabel(NSString *label) {
    if (label.length == 0) return nil;
    return AVDB115DMMSeedTable()[label.lowercaseString];
}

