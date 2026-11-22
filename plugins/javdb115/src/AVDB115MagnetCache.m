#import "AVDB115MagnetCache.h"
#import "AVDB115VisibleMagnets.h"
#import "AVDB115Link.h"
#import "AVDB115Catalog.h"
#import "AVDB115DetailActions.h"

#import <mach/mach.h>
#import <string.h>
#import <stdlib.h>

// Verified from Magnets.toJson / detailLink / MagnetListItem.build on JavDB 1.9.41.
static const uint32_t kCidMagnets = 2678;
static const uint32_t kCidMagnetListItem = 4158;
static const uint32_t kCidOneByte = 94;
static const uint32_t kCidTwoByte = 95;
static const uint32_t kMagnetsSizeTag = 7;
static const size_t kMagnetsSize = 0x70;
static const int kOffItemMagnets = 0x0f; // tagged
static const NSUInteger kMaxChars = 512;

@implementation AVDB115MagnetCache {
    NSMutableArray<NSDictionary *> *_rows; // @{@"link":, @"hint":}
    NSLock *_lock;
}

+ (instancetype)shared {
    static AVDB115MagnetCache *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [[AVDB115MagnetCache alloc] init]; });
    return inst;
}

- (instancetype)init {
    if ((self = [super init])) {
        _rows = [NSMutableArray array];
        _lock = [[NSLock alloc] init];
    }
    return self;
}

- (void)addLink:(NSString *)link catalogHint:(NSString *)hint {
    if (![AVDB115Link isOfflineResource:link]) return;
    NSString *key = hint.length ? hint : ([AVDB115DetailPagePolicy catalogNumberInText:link] ?:
                                          [AVDB115CatalogNumber identityKey:[AVDB115Link displayNameFromLink:link]] ?:
                                          @"");
    [_lock lock];
    for (NSDictionary *r in _rows) {
        if ([r[@"link"] isEqualToString:link]) {
            [_lock unlock];
            return;
        }
    }
    if (_rows.count > 256) {
        [_rows removeObjectsInRange:NSMakeRange(0, _rows.count - 192)];
    }
    [_rows addObject:@{@"link": link, @"hint": key ?: @""}];
    [_lock unlock];
}

- (NSArray<NSString *> *)linksForCatalog:(NSString *)number {
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    [_lock lock];
    NSArray *snap = [_rows copy];
    [_lock unlock];
    for (NSDictionary *r in snap) {
        NSString *link = r[@"link"];
        NSString *hint = r[@"hint"];
        if (![AVDB115Link isOfflineResource:link]) continue;
        BOOL match = YES;
        if (number.length) {
            match = [AVDB115VisibleMagnets text:link matchesCatalog:number] ||
                    [AVDB115VisibleMagnets text:[AVDB115Link displayNameFromLink:link] matchesCatalog:number] ||
                    [AVDB115VisibleMagnets text:hint matchesCatalog:number];
        }
        if (!match) continue;
        if ([seen containsObject:link]) continue;
        [seen addObject:link];
        [out addObject:link];
    }
    return out;
}

static BOOL AVDB115SafeRead(uint64_t addr, void *dst, size_t n) {
    if (!dst || n == 0 || addr < 0x10000ull) return NO;
    if (addr + n < addr) return NO;
    uint8_t *out = dst;
    while (n) {
        // Read at most one 16K window so we never ask vm_read_overwrite
        // to span an unmapped hole.
        size_t chunk = n < 4096 ? n : 4096;
        vm_size_t got = 0;
        kern_return_t kr = vm_read_overwrite(mach_task_self(),
                                             (vm_address_t)addr,
                                             (vm_size_t)chunk,
                                             (vm_address_t)out,
                                             &got);
        if (kr != KERN_SUCCESS || got == 0) return NO;
        if (got > chunk) return NO;
        out += got;
        addr += got;
        n -= got;
    }
    return YES;
}

static uint32_t AVDB115CidOfHeader(uint64_t header) {
    return (uint32_t)((header >> 12) & 0xFFFFF);
}

static uint32_t AVDB115SizeTagOfHeader(uint64_t header) {
    return (uint32_t)((header >> 8) & 0xF);
}

static BOOL AVDB115SmiLen(uint64_t word, uint64_t *n) {
    if ((word & 1ull) != 0ull) return NO;
    uint64_t v = word >> 1;
    if (v == 0 || v > kMaxChars) return NO;
    *n = v;
    return YES;
}

static NSString *AVDB115SafeString(uint64_t tagged) {
    if ((tagged & 1ull) != 1ull || tagged < 0x10001ull) return nil;
    uint64_t untagged = tagged - 1;
    uint64_t hdrLen[2] = {0, 0};
    if (!AVDB115SafeRead(untagged, hdrLen, 16)) return nil;
    uint32_t cid = AVDB115CidOfHeader(hdrLen[0]);
    uint64_t n = 0;
    if (!AVDB115SmiLen(hdrLen[1], &n)) return nil;
    BOOL latin1 = (cid == kCidOneByte || cid == 93);
    BOOL utf16 = (cid == kCidTwoByte);
    if (!latin1 && !utf16) return nil;
    size_t nbytes = latin1 ? (size_t)n : (size_t)n * 2;
    if (nbytes == 0 || nbytes > kMaxChars * 2) return nil;
    uint8_t buf[1024 + 8];
    if (nbytes > sizeof(buf)) return nil;
    if (!AVDB115SafeRead(untagged + 0x10, buf, nbytes)) return nil;
    if (latin1) {
        for (size_t i = 0; i < nbytes; i++) if (buf[i] < 0x09) return nil;
        return [[NSString alloc] initWithBytes:buf length:nbytes encoding:NSISOLatin1StringEncoding];
    }
    if (nbytes % 2) return nil;
    return [[NSString alloc] initWithBytes:buf length:nbytes encoding:NSUTF16LittleEndianStringEncoding];
}

- (void)captureTaggedMagnets:(uint64_t)tagged {
    if ((tagged & 1ull) != 1ull || tagged < 0x10001ull) return;
    uint8_t obj[0x70];
    memset(obj, 0, sizeof(obj));
    if (!AVDB115SafeRead(tagged - 1, obj, kMagnetsSize)) return;
    uint64_t header = 0;
    memcpy(&header, obj, 8);
    if (AVDB115CidOfHeader(header) != kCidMagnets) return;
    uint32_t stag = AVDB115SizeTagOfHeader(header);
    if (stag != kMagnetsSizeTag && stag != 0) return;
    uint64_t nameT = 0, hashT = 0, typeT = 0, urlT = 0;
    memcpy(&nameT, obj + 0x18, 8);
    memcpy(&hashT, obj + 0x20, 8);
    memcpy(&typeT, obj + 0x60, 8);
    memcpy(&urlT,  obj + 0x68, 8);
    NSString *name = AVDB115SafeString(nameT);
    NSString *hash = AVDB115SafeString(hashT);
    NSString *type = AVDB115SafeString(typeT);
    NSString *url  = AVDB115SafeString(urlT);
    NSString *link = [AVDB115VisibleMagnets linkFromMagnetHash:hash name:name type:type url:url];
    if (![AVDB115Link isOfflineResource:link]) return;
    NSString *hint = [AVDB115DetailPagePolicy catalogNumberInText:name] ?:
                     [AVDB115CatalogNumber identityKey:name] ?:
                     name;
    [self addLink:link catalogHint:hint];
}

- (void)captureTaggedMagnetListItem:(uint64_t)taggedItem {
    if ((taggedItem & 1ull) != 1ull || taggedItem < 0x10001ull) return;
    // Widget size 0x28: header + key + magnets + two more fields.
    uint8_t obj[0x28];
    memset(obj, 0, sizeof(obj));
    if (!AVDB115SafeRead(taggedItem - 1, obj, sizeof(obj))) return;
    uint64_t header = 0, magnets = 0;
    memcpy(&header, obj, 8);
    if (AVDB115CidOfHeader(header) != kCidMagnetListItem) return;
    // tagged #0x0f is untagged+0x10.
    memcpy(&magnets, obj + 0x10, 8);
    [self captureTaggedMagnets:magnets];
}

@end

void AVDB115CacheCaptureMagnets(uint64_t tagged) {
    @try {
        [[AVDB115MagnetCache shared] captureTaggedMagnets:tagged];
    } @catch (NSException *ex) {
    }
}

void AVDB115CacheCaptureListItem(uint64_t taggedItem) {
    @try {
        [[AVDB115MagnetCache shared] captureTaggedMagnetListItem:taggedItem];
    } @catch (NSException *ex) {
    }
}
