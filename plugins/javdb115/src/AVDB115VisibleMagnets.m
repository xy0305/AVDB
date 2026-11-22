#import "AVDB115VisibleMagnets.h"
#import "AVDB115Link.h"
#import "AVDB115Catalog.h"
#import <TargetConditionals.h>
#import <string.h>
#import <stdlib.h>
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR || defined(__APPLE__)
#import <mach/mach.h>
#import <mach/vm_map.h>
#endif

// Verified from JavDB 1.9.41 App.framework (Blutter + toJson / detailLink).
// Magnets (package:astarte/home/models/movie_info_entity.dart): cid 2678, size 0x70.
// Tagged field offsets: name 0x17, hash 0x1f, type 0x5f, url 0x67.
static const uint32_t kAVDB115MagnetsCid = 2678;
static const uint32_t kAVDB115MagnetsSizeTag = 0x70 / 16; // 7
static const uint32_t kAVDB115OneByteStringCid = 94;
static const uint32_t kAVDB115TwoByteStringCid = 95;
static const uint32_t kAVDB115ExternalOneByteStringCid = 96;
static const uint32_t kAVDB115ExternalTwoByteStringCid = 97;
static const NSUInteger kAVDB115MaxStringChars = 512;
static const uint64_t kAVDB115MaxScanBytes = 96ull * 1024ull * 1024ull;

@implementation AVDB115VisibleMagnets

+ (NSString *)magnetLinkWithHash:(NSString *)hash name:(NSString *)name {
    NSString *h = [[hash stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    NSMutableString *out = [NSMutableString stringWithFormat:@"magnet:?xt=urn:btih:%@", h];
    if (name.length) {
        NSMutableCharacterSet *ok = [NSMutableCharacterSet alphanumericCharacterSet];
        [ok addCharactersInString:@"-._"];
        NSString *enc = [name stringByAddingPercentEncodingWithAllowedCharacters:ok] ?: name;
        [out appendFormat:@"&dn=%@", enc];
    }
    return out;
}

+ (NSString *)linkFromMagnetHash:(NSString *)hash
                            name:(NSString *)name
                            type:(NSString *)type
                             url:(NSString *)url {
    NSString *ty = type.lowercaseString ?: @"";
    NSString *u = [url stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([ty isEqualToString:@"ed2k"] || [u.lowercaseString hasPrefix:@"ed2k://|file|"]) {
        if ([AVDB115Link isOfflineResource:u]) return u;
        NSString *fromUrl = [AVDB115Link firstOfflineResourceIn:u];
        if (fromUrl.length) return fromUrl;
        return nil;
    }
    NSString *h = [hash stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    static NSRegularExpression *hex;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        hex = [NSRegularExpression regularExpressionWithPattern:@"^[0-9a-fA-F]{32,40}$" options:0 error:nil];
    });
    if (h.length == 0 || [hex numberOfMatchesInString:h options:0 range:NSMakeRange(0, h.length)] != 1) {
        if ([AVDB115Link isOfflineResource:u]) return u;
        return nil;
    }
    NSString *link = [self magnetLinkWithHash:h name:name];
    return [AVDB115Link isOfflineResource:link] ? link : nil;
}

+ (BOOL)text:(NSString *)text matchesCatalog:(NSString *)number {
    if (number.length == 0) return YES;
    if (text.length == 0) return NO;
    if ([AVDB115CatalogNumber identity:text matches:number]) return YES;
    // Filenames like MIDA-859-U.LTX... are not a whole-string identity key.
    NSString *wanted = [AVDB115CatalogNumber identityKey:number] ?: number.uppercaseString;
    NSString *folded = text.uppercaseString;
    if (wanted.length && [folded containsString:wanted]) return YES;
    NSString *compactWanted = [[wanted stringByReplacingOccurrencesOfString:@"-" withString:@""]
        stringByReplacingOccurrencesOfString:@"_" withString:@""];
    NSString *compactText = [[folded stringByReplacingOccurrencesOfString:@"-" withString:@""]
        stringByReplacingOccurrencesOfString:@"_" withString:@""];
    return compactWanted.length > 0 && [compactText containsString:compactWanted];
}

+ (NSString *)preferredLink:(NSArray<NSString *> *)links catalogNumber:(NSString *)number {
    if (links.count == 0) return nil;
    NSString *bestMagnet = nil, *anyMagnet = nil, *bestEd2k = nil, *anyEd2k = nil;
    for (NSString *link in links) {
        if (![AVDB115Link isOfflineResource:link]) continue;
        BOOL match = [self text:link matchesCatalog:number] ||
                     [self text:[AVDB115Link displayNameFromLink:link] matchesCatalog:number];
        BOOL magnet = [link.lowercaseString hasPrefix:@"magnet:"];
        if (magnet) {
            if (!anyMagnet) anyMagnet = link;
            if (match && !bestMagnet) bestMagnet = link;
        } else {
            if (!anyEd2k) anyEd2k = link;
            if (match && !bestEd2k) bestEd2k = link;
        }
    }
    return bestMagnet ?: bestEd2k ?: anyMagnet ?: anyEd2k ?: links.firstObject;
}

+ (NSArray<NSString *> *)mergeUniqueLinks:(NSArray<NSString *> *)a withLinks:(NSArray<NSString *> *)b {
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSArray *src in @[ a ?: @[], b ?: @[] ]) {
        for (NSString *raw in src) {
            if (![AVDB115Link isOfflineResource:raw]) continue;
            if ([seen containsObject:raw]) continue;
            [seen addObject:raw];
            [out addObject:raw];
        }
    }
    return out;
}

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR || defined(__APPLE__)

// Dart 3.13.7 iOS 64-bit: new-space objects sit at 8-mod-16, old-space at
// 0-mod-16 (pointer_tagging.h). v8 stepped by 16 from offset 0, so it
// skipped every new-space Magnets instance — the usual case right after
// the 磁鏈下載 list is built. String fields also live on other heap pages;
// v8 only decoded strings inside the same vm_read buffer, so even a hit
// usually produced no link. MagnetListItem.build never calls detailLink,
// so a raw magnet:/ed2k:// prefix scan is empty until the user copies.

static const size_t kAVDB115Page = 16384;
static const NSInteger kAVDB115PageCache = 96;

typedef struct {
    uint64_t page;
    size_t len;
    BOOL valid;
    uint8_t data[16384];
} AVDB115PageSlot;

typedef struct {
    AVDB115PageSlot slot[96];
    uint32_t clock;
    uint64_t scanned;
    CFAbsoluteTime start;
} AVDB115Mem;

static uint32_t AVDB115HeaderCid(uint64_t header) {
    return (uint32_t)((header >> 12) & 0xFFFFF);
}

static uint32_t AVDB115HeaderSizeTag(uint64_t header) {
    return (uint32_t)((header >> 8) & 0xF);
}

static BOOL AVDB115IsHeapPtr(uint64_t tagged) {
    return (tagged & 1ull) == 1ull && tagged > 0x1000ull;
}

static BOOL AVDB115MemFill(AVDB115Mem *m, uint64_t page, AVDB115PageSlot *s) {
    if (s->valid && s->page == page) return YES;
    vm_offset_t data = 0;
    mach_msg_type_number_t cnt = 0;
    kern_return_t kr = vm_read(mach_task_self(), (vm_address_t)page, (vm_size_t)kAVDB115Page, &data, &cnt);
    if (kr != KERN_SUCCESS || cnt == 0 || data == 0) {
        s->page = page;
        s->len = 0;
        s->valid = NO;
        return NO;
    }
    size_t n = cnt > kAVDB115Page ? kAVDB115Page : (size_t)cnt;
    memcpy(s->data, (const void *)data, n);
    s->page = page;
    s->len = n;
    s->valid = YES;
    m->scanned += n;
    vm_deallocate(mach_task_self(), data, cnt);
    return YES;
}

static BOOL AVDB115MemRead(AVDB115Mem *m, uint64_t addr, void *dst, size_t n) {
    uint8_t *out = dst;
    while (n) {
        uint64_t page = addr & ~((uint64_t)kAVDB115Page - 1ull);
        uint64_t off = addr - page;
        AVDB115PageSlot *s = &m->slot[(page / kAVDB115Page) % kAVDB115PageCache];
        if (!(s->valid && s->page == page)) {
            if (m->scanned >= kAVDB115MaxScanBytes) return NO;
            if ((CFAbsoluteTimeGetCurrent() - m->start) > 0.60) return NO;
            if (!AVDB115MemFill(m, page, s)) return NO;
        }
        if (!s->valid || off >= s->len) return NO;
        size_t take = s->len - (size_t)off;
        if (take > n) take = n;
        memcpy(out, s->data + off, take);
        out += take;
        addr += take;
        n -= take;
    }
    return YES;
}

static uint64_t AVDB115MemU64(AVDB115Mem *m, uint64_t addr, BOOL *ok) {
    uint64_t v = 0;
    *ok = AVDB115MemRead(m, addr, &v, 8);
    return v;
}

static NSString *AVDB115StringAtMem(AVDB115Mem *m, uint64_t tagged) {
    if (!AVDB115IsHeapPtr(tagged)) return nil;
    uint64_t untagged = tagged - 1;
    BOOL ok = NO;
    uint64_t header = AVDB115MemU64(m, untagged, &ok);
    if (!ok) return nil;
    uint64_t lengthWord = AVDB115MemU64(m, untagged + 8, &ok);
    if (!ok) return nil;
    uint32_t cid = AVDB115HeaderCid(header);
    uint64_t n = lengthWord;
    if (n > kAVDB115MaxStringChars && (n & 1ull) == 0ull && (n >> 1) <= kAVDB115MaxStringChars) n >>= 1;
    if (n == 0 || n > kAVDB115MaxStringChars) return nil;

    BOOL latin1 = YES;
    uint64_t dataAddr = 0;
    if (cid == kAVDB115OneByteStringCid || cid == kAVDB115TwoByteStringCid) {
        latin1 = (cid == kAVDB115OneByteStringCid);
        dataAddr = untagged + 0x10;
    } else if (cid == kAVDB115ExternalOneByteStringCid || cid == kAVDB115ExternalTwoByteStringCid) {
        // Dart 3.13 predefined strings are 93–95; keep a conservative external path.
        latin1 = (cid == kAVDB115ExternalOneByteStringCid);
        dataAddr = AVDB115MemU64(m, untagged + 0x10, &ok);
        if (!ok || dataAddr == 0) return nil;
    } else {
        return nil;
    }
    size_t nbytes = latin1 ? (size_t)n : (size_t)n * 2;
    if (nbytes == 0 || nbytes > kAVDB115MaxStringChars * 2) return nil;
    uint8_t buf[1024 + 8];
    if (nbytes > sizeof(buf)) return nil;
    if (!AVDB115MemRead(m, dataAddr, buf, nbytes)) return nil;
    if (latin1) {
        for (size_t i = 0; i < nbytes; i++) {
            if (buf[i] < 0x09) return nil;
        }
        return [[NSString alloc] initWithBytes:buf length:nbytes encoding:NSISOLatin1StringEncoding];
    }
    return [[NSString alloc] initWithBytes:buf length:nbytes encoding:NSUTF16LittleEndianStringEncoding];
}

static void AVDB115AddLink(NSMutableArray *links, NSMutableSet *seen, NSString *link, NSString *number, NSString *nameHint) {
    if (![AVDB115Link isOfflineResource:link]) return;
    if (number.length) {
        BOOL match = [AVDB115VisibleMagnets text:link matchesCatalog:number] ||
                     [AVDB115VisibleMagnets text:[AVDB115Link displayNameFromLink:link] matchesCatalog:number] ||
                     [AVDB115VisibleMagnets text:nameHint matchesCatalog:number];
        if (!match) return;
    }
    if ([seen containsObject:link]) return;
    [seen addObject:link];
    [links addObject:link];
}

static NSString *AVDB115JSONStringValue(NSString *window, NSString *key) {
    NSString *pat = [NSString stringWithFormat:@"\"%@\"\\s*:\\s*\"([^\"]{0,400})\"", key];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pat options:0 error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:window options:0 range:NSMakeRange(0, window.length)];
    if (!m || m.numberOfRanges < 2) return nil;
    return [window substringWithRange:[m rangeAtIndex:1]];
}

static void AVDB115CollectJSONFromBytes(const uint8_t *base, size_t len, NSString *number,
                                        NSMutableArray *links, NSMutableSet *seen) {
    if (!base || len < 16) return;
    NSString *blob = [[NSString alloc] initWithBytes:base length:len encoding:NSISOLatin1StringEncoding];
    if (blob.length == 0) return;
    static NSRegularExpression *hashRe, *ed2kRe;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        hashRe = [NSRegularExpression regularExpressionWithPattern:@"\"hash\"\\s*:\\s*\"([0-9a-fA-F]{32,40})\"" options:0 error:nil];
        ed2kRe = [NSRegularExpression regularExpressionWithPattern:@"\"url\"\\s*:\\s*\"(ed2k://[^\"]{10,400})\"" options:NSRegularExpressionCaseInsensitive error:nil];
    });
    void (^consider)(NSRange) = ^(NSRange pos) {
        NSUInteger start = pos.location > 500 ? pos.location - 500 : 0;
        NSUInteger end = MIN(blob.length, pos.location + pos.length + 500);
        NSString *window = [blob substringWithRange:NSMakeRange(start, end - start)];
        NSString *name = AVDB115JSONStringValue(window, @"name") ?: AVDB115JSONStringValue(window, @"title");
        NSString *type = AVDB115JSONStringValue(window, @"type");
        NSString *url = AVDB115JSONStringValue(window, @"url");
        NSString *hash = AVDB115JSONStringValue(window, @"hash");
        NSString *link = [AVDB115VisibleMagnets linkFromMagnetHash:hash name:name type:type url:url];
        AVDB115AddLink(links, seen, link, number, name);
    };
    NSArray *hm = [hashRe matchesInString:blob options:0 range:NSMakeRange(0, blob.length)];
    for (NSTextCheckingResult *m in hm) consider(m.range);
    NSArray *em = [ed2kRe matchesInString:blob options:0 range:NSMakeRange(0, blob.length)];
    for (NSTextCheckingResult *m in em) consider(m.range);
}

static void AVDB115CollectURIsFromBytes(const uint8_t *base, size_t len, NSString *number,
                                        NSMutableArray *links, NSMutableSet *seen) {
    if (!base || len < 12) return;
    void (^addFromText)(NSString *) = ^(NSString *text) {
        if (text.length < 12) return;
        for (NSString *l in [AVDB115Link offlineResourcesIn:text]) {
            AVDB115AddLink(links, seen, l, number, [AVDB115Link displayNameFromLink:l]);
        }
    };
    const char *needles[2] = { "magnet:?xt=urn:btih:", "ed2k://|file|" };
    for (int ni = 0; ni < 2; ni++) {
        size_t nlen = strlen(needles[ni]);
        const uint8_t *p = base, *end = base + len;
        while (p + nlen < end) {
            const uint8_t *found = memmem(p, (size_t)(end - p), needles[ni], nlen);
            if (!found) break;
            size_t take = (size_t)(end - found);
            if (take > 1024) take = 1024;
            addFromText([[NSString alloc] initWithBytes:found length:take encoding:NSISOLatin1StringEncoding]);
            p = found + nlen;
        }
    }
}

static void AVDB115CollectMagnetsOnPage(AVDB115Mem *mem, uint64_t page, size_t len, NSString *number,
                                        NSMutableArray *links, NSMutableSet *seen) {
    // Step 8 so both old-space (0 mod 16) and new-space (8 mod 16) are visited.
    size_t maxOff = len;
    for (size_t off = 0; off + 8 <= maxOff; off += 8) {
        BOOL ok = NO;
        uint64_t header = AVDB115MemU64(mem, page + off, &ok);
        if (!ok) break;
        if (AVDB115HeaderCid(header) != kAVDB115MagnetsCid) continue;
        uint32_t stag = AVDB115HeaderSizeTag(header);
        if (stag != kAVDB115MagnetsSizeTag && stag != 0) continue;
        uint64_t base = page + off;
        uint64_t nameT = AVDB115MemU64(mem, base + 0x18, &ok);
        if (!ok) continue;
        uint64_t hashT = AVDB115MemU64(mem, base + 0x20, &ok);
        if (!ok) continue;
        uint64_t typeT = AVDB115MemU64(mem, base + 0x60, &ok);
        if (!ok) continue;
        uint64_t urlT = AVDB115MemU64(mem, base + 0x68, &ok);
        if (!ok) continue;
        NSString *name = AVDB115StringAtMem(mem, nameT);
        NSString *hash = AVDB115StringAtMem(mem, hashT);
        NSString *type = AVDB115StringAtMem(mem, typeT);
        NSString *url  = AVDB115StringAtMem(mem, urlT);
        if (name.length == 0 && hash.length == 0 && url.length == 0) continue;
        NSString *link = [AVDB115VisibleMagnets linkFromMagnetHash:hash name:name type:type url:url];
        AVDB115AddLink(links, seen, link, number, name);
    }
}

+ (BOOL)labelsSuggestVisibleMagnetList:(NSArray<NSString *> *)labels catalogNumber:(NSString *)number {
    BOOL tab = NO, ed2k = NO, named = NO;
    for (NSString *raw in labels) {
        NSString *norm = [[raw componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@" "];
        while ([norm containsString:@"  "]) norm = [norm stringByReplacingOccurrencesOfString:@"  " withString:@" "];
        if ([norm isEqualToString:@"磁鏈下載"] || [norm isEqualToString:@"磁链下载"] ||
            [norm hasPrefix:@"磁鏈下載 "] || [norm hasPrefix:@"磁链下载 "]) tab = YES;
        NSString *s = raw.uppercaseString ?: @"";
        if ([s isEqualToString:@"ED2K"] || [s containsString:@"ED2K"]) ed2k = YES;
        if (number.length && [self text:raw matchesCatalog:number] && raw.length > number.length) named = YES;
    }
    return (tab && (ed2k || named)) || (ed2k && named);
}

+ (NSArray<NSString *> *)residentLinksMatchingCatalog:(NSString *)number {
    NSMutableArray *links = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    AVDB115Mem mem;
    memset(&mem, 0, sizeof(mem));
    mem.start = CFAbsoluteTimeGetCurrent();

    vm_address_t addr = 0;
    while (mem.scanned < kAVDB115MaxScanBytes && (CFAbsoluteTimeGetCurrent() - mem.start) < 0.60) {
        vm_size_t size = 0;
        vm_region_basic_info_data_64_t info;
        mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
        mach_port_t object = MACH_PORT_NULL;
        kern_return_t kr = vm_region_64(mach_task_self(), &addr, &size, VM_REGION_BASIC_INFO_64,
                                        (vm_region_info_t)&info, &count, &object);
        if (kr != KERN_SUCCESS || size == 0) break;
        BOOL readable = (info.protection & VM_PROT_READ) != 0;
        BOOL writable = (info.protection & VM_PROT_WRITE) != 0;
        BOOL executable = (info.protection & VM_PROT_EXECUTE) != 0;
        // Dart heap / Dio JSON: readable+writable, not executable. Skip RX images
        // (they only contain the constant URI prefixes, not live hashes).
        if (readable && writable && !executable) {
            uint64_t start = (uint64_t)addr;
            uint64_t end = start + (uint64_t)size;
            uint8_t overlap[600];
            size_t overlapLen = 0;
            for (uint64_t page = start; page < end; page += kAVDB115Page) {
                if (mem.scanned >= kAVDB115MaxScanBytes) break;
                if ((CFAbsoluteTimeGetCurrent() - mem.start) > 0.60) break;
                AVDB115PageSlot *s = &mem.slot[(page / kAVDB115Page) % kAVDB115PageCache];
                if (!AVDB115MemFill(&mem, page, s)) { overlapLen = 0; continue; }
                AVDB115CollectMagnetsOnPage(&mem, page, s->len, number, links, seen);
                if (overlapLen) {
                    size_t comb = overlapLen + s->len;
                    uint8_t *tmp = (uint8_t *)malloc(comb);
                    if (tmp) {
                        memcpy(tmp, overlap, overlapLen);
                        memcpy(tmp + overlapLen, s->data, s->len);
                        AVDB115CollectJSONFromBytes(tmp, comb, number, links, seen);
                        AVDB115CollectURIsFromBytes(tmp, comb, number, links, seen);
                        free(tmp);
                    }
                } else {
                    AVDB115CollectJSONFromBytes(s->data, s->len, number, links, seen);
                    AVDB115CollectURIsFromBytes(s->data, s->len, number, links, seen);
                }
                overlapLen = s->len > 600 ? 600 : s->len;
                memcpy(overlap, s->data + (s->len - overlapLen), overlapLen);
            }
        }
        vm_address_t next = addr + size;
        if (next <= addr) break;
        addr = next;
    }
    return links;
}

#else

+ (BOOL)labelsSuggestVisibleMagnetList:(NSArray<NSString *> *)labels catalogNumber:(NSString *)number {
    (void)labels; (void)number;
    return NO;
}

+ (NSArray<NSString *> *)residentLinksMatchingCatalog:(NSString *)number {
    (void)number;
    return @[];
}

#endif

@end
