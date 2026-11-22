#import "AVDB115VisibleMagnets.h"
#import "AVDB115Link.h"
#import "AVDB115Catalog.h"
#import <TargetConditionals.h>
#import <string.h>
#import <stdlib.h>
#import <stdint.h>
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR || defined(__APPLE__)
#import <mach/mach.h>
#import <mach/vm_map.h>
#import <mach/vm_region.h>
#import <mach/vm_statistics.h>
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

// v9 crashed on tap: AVDB115Mem (96 * 16KB page slots) was a ~1.5MB *stack*
// local in residentLinksMatchingCatalog. The iOS main-thread stack is about
// 1MB, so memset/entry overflowed and the app died (闪退). v10 keeps that
// state on the heap, reads only through vm_read_overwrite into a single
// page-sized buffer, never dereferences foreign pointers, and only follows
// addresses that already sit inside enumerated RW regions.

static const unsigned kAVDB115MaxRegions = 192;
static const uint64_t kAVDB115MaxScanBytesV10 = 24ull * 1024ull * 1024ull;
static const CFTimeInterval kAVDB115MaxScanSeconds = 0.15;

typedef struct {
    uint64_t start;
    uint64_t end;
} AVDB115Region;

typedef struct {
    AVDB115Region regions[192];
    unsigned nregions;
    uint8_t *pagebuf;
    vm_size_t pagesz;
    uint64_t cached_page;
    vm_size_t cached_len;
    BOOL cached_ok;
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
    return (tagged & 1ull) == 1ull && tagged > 0x10000ull;
}

static BOOL AVDB115BudgetLeft(const AVDB115Mem *m) {
    if (!m || !m->pagebuf) return NO;
    if (m->scanned >= kAVDB115MaxScanBytesV10) return NO;
    if ((CFAbsoluteTimeGetCurrent() - m->start) > kAVDB115MaxScanSeconds) return NO;
    return YES;
}

static BOOL AVDB115InRegions(const AVDB115Mem *m, uint64_t addr, size_t n) {
    if (n == 0) return NO;
    if (addr + n < addr) return NO; // overflow
    uint64_t last = addr + n;
    for (unsigned i = 0; i < m->nregions; i++) {
        if (addr >= m->regions[i].start && last <= m->regions[i].end) return YES;
    }
    return NO;
}

static void AVDB115MemFree(AVDB115Mem *m) {
    if (!m) return;
    if (m->pagebuf) {
        free(m->pagebuf);
        m->pagebuf = NULL;
    }
    free(m);
}

static AVDB115Mem *AVDB115MemNew(void) {
    AVDB115Mem *m = (AVDB115Mem *)calloc(1, sizeof(AVDB115Mem));
    if (!m) return NULL;
    vm_size_t ps = vm_page_size;
    if (ps < 4096 || ps > (1024 * 1024) || (ps & (ps - 1)) != 0) ps = 16384;
    m->pagesz = ps;
    m->pagebuf = (uint8_t *)malloc((size_t)ps);
    if (!m->pagebuf) {
        free(m);
        return NULL;
    }
    m->cached_page = UINT64_MAX;
    m->start = CFAbsoluteTimeGetCurrent();

    vm_address_t addr = 0;
    while (m->nregions < kAVDB115MaxRegions) {
        vm_size_t size = 0;
        vm_region_extended_info_data_t info;
        mach_msg_type_number_t count = VM_REGION_EXTENDED_INFO_COUNT;
        mach_port_t object = MACH_PORT_NULL;
        kern_return_t kr = vm_region_64(mach_task_self(), &addr, &size, VM_REGION_EXTENDED_INFO,
                                        (vm_region_info_t)&info, &count, &object);
        if (object != MACH_PORT_NULL) {
            mach_port_deallocate(mach_task_self(), object);
        }
        if (kr != KERN_SUCCESS || size == 0) break;
        BOOL readable = (info.protection & VM_PROT_READ) != 0;
        BOOL writable = (info.protection & VM_PROT_WRITE) != 0;
        BOOL executable = (info.protection & VM_PROT_EXECUTE) != 0;
        uint64_t start = (uint64_t)addr;
        uint64_t end = start + (uint64_t)size;
        BOOL skipSpecial = NO;
#ifdef SM_EMPTY
        if (info.share_mode == SM_EMPTY) skipSpecial = YES;
#endif
#ifdef VM_MEMORY_IOKIT
        if (info.user_tag == VM_MEMORY_IOKIT) skipSpecial = YES;
#endif
#ifdef VM_MEMORY_GUARD
        if (info.user_tag == VM_MEMORY_GUARD) skipSpecial = YES;
#endif
        if (info.pages_resident == 0) skipSpecial = YES;
        if (readable && writable && !executable && !skipSpecial && end > start && size >= 64 &&
            size <= (512ull * 1024ull * 1024ull)) {
            m->regions[m->nregions].start = start;
            m->regions[m->nregions].end = end;
            m->nregions++;
        }
        vm_address_t next = addr + size;
        if (next <= addr) break;
        addr = next;
    }
    return m;
}

// Copy one page (or the remainder of a region) via vm_read_overwrite into
// our heap buffer. Never dereference the foreign address itself.
static BOOL AVDB115MemFill(AVDB115Mem *m, uint64_t page) {
    if (!m || !m->pagebuf) return NO;
    if (m->cached_ok && m->cached_page == page) return YES;
    m->cached_ok = NO;
    m->cached_len = 0;
    m->cached_page = page;
    if ((page % m->pagesz) != 0) return NO;
    if (!AVDB115InRegions(m, page, 1)) return NO;
    if (!AVDB115BudgetLeft(m)) return NO;

    uint64_t maxEnd = page;
    for (unsigned i = 0; i < m->nregions; i++) {
        if (page >= m->regions[i].start && page < m->regions[i].end) {
            maxEnd = m->regions[i].end;
            break;
        }
    }
    if (maxEnd <= page) return NO;
    vm_size_t want = m->pagesz;
    if ((uint64_t)want > maxEnd - page) want = (vm_size_t)(maxEnd - page);
    if (want == 0) return NO;

    vm_size_t outsz = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(),
                                         (vm_address_t)page,
                                         want,
                                         (vm_address_t)m->pagebuf,
                                         &outsz);
    if (kr != KERN_SUCCESS || outsz == 0 || outsz > want) return NO;
    m->cached_len = outsz;
    m->cached_ok = YES;
    m->scanned += outsz;
    return YES;
}

static BOOL AVDB115MemRead(AVDB115Mem *m, uint64_t addr, void *dst, size_t n) {
    if (!m || !dst || n == 0) return NO;
    if (!AVDB115InRegions(m, addr, n)) return NO;
    uint8_t *out = dst;
    while (n) {
        uint64_t page = addr & ~((uint64_t)m->pagesz - 1ull);
        uint64_t off = addr - page;
        if (!AVDB115MemFill(m, page)) return NO;
        if (!m->cached_ok || off >= m->cached_len) return NO;
        size_t take = (size_t)(m->cached_len - off);
        if (take > n) take = n;
        memcpy(out, m->pagebuf + off, take);
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
    // Header + length word must already lie in a known RW region.
    if (!AVDB115InRegions(m, untagged, 16)) return nil;
    BOOL ok = NO;
    uint64_t header = AVDB115MemU64(m, untagged, &ok);
    if (!ok) return nil;
    uint64_t lengthWord = AVDB115MemU64(m, untagged + 8, &ok);
    if (!ok) return nil;
    uint32_t cid = AVDB115HeaderCid(header);
    uint64_t n = lengthWord;
    if (n > kAVDB115MaxStringChars) return nil;
    if (n == 0) return nil;

    BOOL latin1 = YES;
    uint64_t dataAddr = 0;
    // Dart 3.13 predefined string cids are 93–95 (String/OneByte/TwoByte).
    // Do not chase "external" string pointers; those cids are not strings here.
    if (cid == kAVDB115OneByteStringCid || cid == 93) {
        latin1 = YES;
        dataAddr = untagged + 0x10;
    } else if (cid == kAVDB115TwoByteStringCid) {
        latin1 = NO;
        dataAddr = untagged + 0x10;
    } else {
        return nil;
    }
    size_t nbytes = latin1 ? (size_t)n : (size_t)n * 2;
    if (nbytes == 0 || nbytes > kAVDB115MaxStringChars * 2) return nil;
    if (!AVDB115InRegions(m, dataAddr, nbytes)) return nil;
    uint8_t buf[1024 + 8];
    if (nbytes > sizeof(buf)) return nil;
    if (!AVDB115MemRead(m, dataAddr, buf, nbytes)) return nil;
    if (latin1) {
        for (size_t i = 0; i < nbytes; i++) {
            if (buf[i] < 0x09) return nil;
        }
        return [[NSString alloc] initWithBytes:buf length:nbytes encoding:NSISOLatin1StringEncoding];
    }
    if (nbytes % 2) return nil;
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
    if (window.length == 0 || key.length == 0) return nil;
    NSString *pat = [NSString stringWithFormat:@"\"%@\"\\s*:\\s*\"([^\"]{0,400})\"", key];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pat options:0 error:nil];
    if (!re) return nil;
    NSTextCheckingResult *m = [re firstMatchInString:window options:0 range:NSMakeRange(0, window.length)];
    if (!m || m.numberOfRanges < 2) return nil;
    NSRange r = [m rangeAtIndex:1];
    if (r.location == NSNotFound || NSMaxRange(r) > window.length) return nil;
    return [window substringWithRange:r];
}

static void AVDB115CollectJSONFromBytes(const uint8_t *base, size_t len, NSString *number,
                                        NSMutableArray *links, NSMutableSet *seen) {
    if (!base || len < 16 || len > (64u * 1024u)) return;
    // Cheap prefilter so we do not build/regex every binary page.
    if (!memmem(base, len, "\"hash\"", 6) && !memmem(base, len, "ed2k://", 7)) return;
    NSString *blob = [[NSString alloc] initWithBytes:base length:len encoding:NSISOLatin1StringEncoding];
    if (blob.length == 0) return;
    static NSRegularExpression *hashRe, *ed2kRe;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        hashRe = [NSRegularExpression regularExpressionWithPattern:@"\"hash\"\\s*:\\s*\"([0-9a-fA-F]{32,40})\"" options:0 error:nil];
        ed2kRe = [NSRegularExpression regularExpressionWithPattern:@"\"url\"\\s*:\\s*\"(ed2k://[^\"]{10,400})\"" options:NSRegularExpressionCaseInsensitive error:nil];
    });
    void (^consider)(NSRange) = ^(NSRange pos) {
        if (pos.location == NSNotFound || NSMaxRange(pos) > blob.length) return;
        NSUInteger start = pos.location > 500 ? pos.location - 500 : 0;
        NSUInteger end = MIN(blob.length, pos.location + pos.length + 500);
        if (end <= start) return;
        NSString *window = [blob substringWithRange:NSMakeRange(start, end - start)];
        NSString *name = AVDB115JSONStringValue(window, @"name") ?: AVDB115JSONStringValue(window, @"title");
        NSString *type = AVDB115JSONStringValue(window, @"type");
        NSString *url = AVDB115JSONStringValue(window, @"url");
        NSString *hash = AVDB115JSONStringValue(window, @"hash");
        NSString *link = [AVDB115VisibleMagnets linkFromMagnetHash:hash name:name type:type url:url];
        AVDB115AddLink(links, seen, link, number, name);
    };
    if (hashRe) {
        NSArray *hm = [hashRe matchesInString:blob options:0 range:NSMakeRange(0, blob.length)];
        for (NSTextCheckingResult *m in hm) consider(m.range);
    }
    if (ed2kRe) {
        NSArray *em = [ed2kRe matchesInString:blob options:0 range:NSMakeRange(0, blob.length)];
        for (NSTextCheckingResult *m in em) consider(m.range);
    }
}

static void AVDB115CollectURIsFromBytes(const uint8_t *base, size_t len, NSString *number,
                                        NSMutableArray *links, NSMutableSet *seen) {
    if (!base || len < 12 || len > (64u * 1024u)) return;
    if (!memmem(base, len, "magnet:?xt=urn:btih:", 20) && !memmem(base, len, "ed2k://|file|", 13)) return;
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
    if (!mem || len < 0x70) return;
    // Step 8: visit new-space (8 mod 16) and old-space (0 mod 16).
    for (size_t off = 0; off + 0x70 <= len; off += 8) {
        if (!AVDB115BudgetLeft(mem)) return;
        uint64_t base = page + off;
        // The whole 0x70-byte Magnets object must lie in a known region.
        if (!AVDB115InRegions(mem, base, 0x70)) continue;
        BOOL ok = NO;
        uint64_t header = AVDB115MemU64(mem, base, &ok);
        if (!ok) continue;
        if (AVDB115HeaderCid(header) != kAVDB115MagnetsCid) continue;
        // Require the verified size tag (7). Do not accept 0: it matches too
        // much random memory and led v9 to chase garbage pointers.
        if (AVDB115HeaderSizeTag(header) != kAVDB115MagnetsSizeTag) continue;
        uint64_t nameT = AVDB115MemU64(mem, base + 0x18, &ok); if (!ok) continue;
        uint64_t hashT = AVDB115MemU64(mem, base + 0x20, &ok); if (!ok) continue;
        uint64_t typeT = AVDB115MemU64(mem, base + 0x60, &ok); if (!ok) continue;
        uint64_t urlT  = AVDB115MemU64(mem, base + 0x68, &ok); if (!ok) continue;
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

+ (NSArray<NSString *> *)avdb115_residentLinksSafe:(NSString *)number {
    NSMutableArray *links = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    AVDB115Mem *mem = AVDB115MemNew();
    if (!mem) return links;

    uint8_t overlap[600];
    size_t overlapLen = 0;
    uint64_t prevRegionEnd = 0;

    for (unsigned i = 0; i < mem->nregions && AVDB115BudgetLeft(mem); i++) {
        uint64_t start = mem->regions[i].start;
        uint64_t end = mem->regions[i].end;
        if (start != prevRegionEnd) overlapLen = 0;
        prevRegionEnd = end;
        for (uint64_t page = start; page < end && AVDB115BudgetLeft(mem); page += mem->pagesz) {
            if (!AVDB115MemFill(mem, page) || !mem->cached_ok) {
                overlapLen = 0;
                continue;
            }
            AVDB115CollectMagnetsOnPage(mem, page, (size_t)mem->cached_len, number, links, seen);
            const uint8_t *data = mem->pagebuf;
            size_t len = (size_t)mem->cached_len;
            if (overlapLen) {
                size_t comb = overlapLen + len;
                if (comb >= overlapLen && comb <= 600 + (size_t)mem->pagesz) {
                    uint8_t *tmp = (uint8_t *)malloc(comb);
                    if (tmp) {
                        memcpy(tmp, overlap, overlapLen);
                        memcpy(tmp + overlapLen, data, len);
                        AVDB115CollectJSONFromBytes(tmp, comb, number, links, seen);
                        AVDB115CollectURIsFromBytes(tmp, comb, number, links, seen);
                        free(tmp);
                    }
                }
            } else {
                AVDB115CollectJSONFromBytes(data, len, number, links, seen);
                AVDB115CollectURIsFromBytes(data, len, number, links, seen);
            }
            // Re-fill: CollectMagnetsOnPage may have replaced the cached page
            // while following string pointers.
            if (!(mem->cached_ok && mem->cached_page == page)) {
                if (!AVDB115MemFill(mem, page) || !mem->cached_ok) {
                    overlapLen = 0;
                    continue;
                }
                data = mem->pagebuf;
                len = (size_t)mem->cached_len;
            }
            overlapLen = len > 600 ? 600 : len;
            if (overlapLen) memcpy(overlap, data + (len - overlapLen), overlapLen);
        }
    }
    AVDB115MemFree(mem);
    return links;
}

+ (NSArray<NSString *> *)residentLinksMatchingCatalog:(NSString *)number {
    @try {
        return [self avdb115_residentLinksSafe:number] ?: @[];
    } @catch (NSException *ex) {
        return @[];
    }
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
