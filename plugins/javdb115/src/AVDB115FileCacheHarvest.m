#import "AVDB115FileCacheHarvest.h"
#import "AVDB115MagnetJSON.h"
#import "AVDB115MagnetCache.h"

static const unsigned long long kMaxFile = 2ull * 1024ull * 1024ull;
static const unsigned long long kMaxTotal = 8ull * 1024ull * 1024ull;
static const NSUInteger kMaxFiles = 80;

@implementation AVDB115FileCacheHarvest

+ (BOOL)shouldSkipName:(NSString *)name {
    NSString *l = name.lowercaseString;
    for (NSString *ext in @[@"jpg", @"jpeg", @"png", @"gif", @"webp", @"mp4", @"m4v", @"mov", @"heic", @"ico"]) {
        if ([l hasSuffix:ext]) return YES;
    }
    return NO;
}

+ (NSUInteger)harvestDirectory:(NSString *)root total:(unsigned long long *)total files:(NSUInteger *)files {
    if (root.length == 0) return 0;
    NSUInteger added = 0;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSDirectoryEnumerator *en = [fm enumeratorAtPath:root];
    NSString *rel;
    while ((rel = [en nextObject])) {
        if (*files >= kMaxFiles || *total >= kMaxTotal) break;
        NSString *name = rel.lastPathComponent;
        if ([self shouldSkipName:name]) continue;
        NSString *full = [root stringByAppendingPathComponent:rel];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:full isDirectory:&isDir] || isDir) continue;
        NSDictionary *attr = [fm attributesOfItemAtPath:full error:nil];
        unsigned long long sz = [attr[NSFileSize] unsignedLongLongValue];
        if (sz == 0 || sz > kMaxFile) continue;
        NSData *data = [NSData dataWithContentsOfFile:full options:NSDataReadingMappedIfSafe | NSDataReadingUncached error:nil];
        if (data.length < 16) continue;
        *total += data.length;
        (*files)++;
        // Accept FileCacheStore metadata/body if it mentions magnets or hash fields.
        NSString *probe = [[NSString alloc] initWithBytes:data.bytes
                                                   length:MIN((NSUInteger)256, data.length)
                                                 encoding:NSUTF8StringEncoding];
        BOOL interesting = [AVDB115MagnetJSON isMagnetListURLString:full] ||
                           [AVDB115MagnetJSON isMagnetListURLString:probe] ||
                           [probe containsString:@"\"hash\""] ||
                           [probe.lowercaseString containsString:@"ed2k://"] ||
                           [probe containsString:@"/magnets"] ||
                           [name.lowercaseString containsString:@"http_cache"] ||
                           [name.lowercaseString containsString:@"dio_cache"];
        // Also search later in the file for /magnets in metadata JSON.
        if (!interesting && data.length > 256) {
            NSString *more = [[NSString alloc] initWithBytes:data.bytes
                                                      length:MIN((NSUInteger)4096, data.length)
                                                    encoding:NSUTF8StringEncoding];
            if ([more containsString:@"/magnets"] || [more containsString:@"\"hash\""] ||
                [more.lowercaseString containsString:@"ed2k://"]) {
                interesting = YES;
            }
        }
        if (!interesting) {
            if ([probe containsString:@"\"number\""] || [probe containsString:@"\"code\""]) {
                interesting = YES;
            }
        }
        if (!interesting) continue;
        NSDate *mtime = attr[NSFileModificationDate];
        NSUInteger got = [AVDB115MagnetJSON ingestData:data url:nil catalogHint:nil];
        added += got;
        if (got) {
            NSString *win = [[NSString alloc] initWithBytes:data.bytes
                                                     length:MIN((NSUInteger)65536, data.length)
                                                   encoding:NSISOLatin1StringEncoding];
            NSString *mid = [AVDB115MagnetCache movieIdFromURLString:win];
            if (mid.length) [[AVDB115MagnetCache shared] noteMagnetsMovieId:mid seenAt:mtime];
        } else {
            [AVDB115MagnetJSON ingestMovieIndexFromData:data];
        }
    }
    return added;
}

+ (NSUInteger)harvest {
    NSUInteger added = 0;
    @try {
        unsigned long long total = 0;
        NSUInteger files = 0;
        NSMutableArray<NSString *> *roots = [NSMutableArray array];
        NSString *home = NSHomeDirectory();
        if (home.length) [roots addObject:home];
        NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
        [roots addObjectsFromArray:dirs];
        dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        [roots addObjectsFromArray:dirs];
        dirs = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        [roots addObjectsFromArray:dirs];
        NSString *tmp = NSTemporaryDirectory();
        if (tmp.length) [roots addObject:tmp];

        NSFileManager *fm = NSFileManager.defaultManager;
        NSMutableSet<NSString *> *visited = [NSMutableSet set];
        for (NSString *root in roots) {
            if (root.length == 0 || [visited containsObject:root]) continue;
            [visited addObject:root];
            // Prefer .../http_cache (pp+0x3180) and leftover hive files.
            NSDirectoryEnumerator *en = [fm enumeratorAtPath:root];

            NSString *rel;
            NSUInteger listed = 0;
            while ((rel = [en nextObject])) {
                if (listed++ > 4000) break;
                NSString *base = rel.lastPathComponent.lowercaseString;
                NSString *full = [root stringByAppendingPathComponent:rel];
                if ([base isEqualToString:@"http_cache"] || [rel.lowercaseString containsString:@"/http_cache"]) {
                    BOOL isDir = NO;
                    if ([fm fileExistsAtPath:full isDirectory:&isDir] && isDir) {
                        added += [self harvestDirectory:full total:&total files:&files];
                        [en skipDescendants];
                    }
                } else if ([base hasPrefix:@"dio_cache.hive"] || [base isEqualToString:@"dio_cache.lock"] ||
                           [base isEqualToString:@"dio_cache.hivec"]) {
                    BOOL isDir = NO;
                    if ([fm fileExistsAtPath:full isDirectory:&isDir] && !isDir) {
                        NSData *data = [NSData dataWithContentsOfFile:full options:NSDataReadingMappedIfSafe error:nil];
                        if (data.length && data.length <= kMaxFile) {
                            added += [AVDB115MagnetJSON ingestData:data url:nil catalogHint:nil];
                            [AVDB115MagnetJSON ingestMovieIndexFromData:data];
                            files++;
                            total += data.length;
                        }
                    }
                }
                if (files >= kMaxFiles || total >= kMaxTotal) break;
            }
        }
    } @catch (NSException *ex) {
        added = 0;
    }
    [AVDB115MagnetJSON setFileHarvestCount:added];
    return added;
}

@end
