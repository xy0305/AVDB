#import "AVDB115VisibleMagnets.h"
#import "AVDB115Link.h"
#import "AVDB115Catalog.h"
#import <TargetConditionals.h>
#import <string.h>
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR || defined(__APPLE__)
#import <mach/mach.h>
#import <mach/mach_vm.h>
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

static uint32_t AVDB115HeaderCid(uint64_t header) {
    return (uint32_t)((header >> 12) & 0xFFFFF);
}

static uint32_t AVDB115HeaderSizeTag(uint64_t header) {
    return (uint32_t)((header >> 8) & 0xF);
}

static BOOL AVDB115IsHeapPtr(uint64_t tagged) {
    return (tagged & 1ull) == 1ull && tagged > 0x1000ull;
}

static BOOL AVDB115ReadU64(const uint8_t *base, size_t len, uint64_t addr, uint64_t regionStart, uint64_t *out) {
    if (addr < regionStart) return NO;
    uint64_t off = addr - regionStart;
    if (off + 8 > len) return NO;
    memcpy(out, base + off, 8);
    return YES;
}

static NSString *AVDB115StringAt(const uint8_t *base, size_t len, uint64_t tagged, uint64_t regionStart) {
    if (!AVDB115IsHeapPtr(tagged)) return nil;
    uint64_t untagged = tagged - 1;
    uint64_t header = 0, lengthWord = 0;
    if (!AVDB115ReadU64(base, len, untagged, regionStart, &header)) return nil;
    if (!AVDB115ReadU64(base, len, untagged + 8, regionStart, &lengthWord)) return nil;
    uint32_t cid = AVDB115HeaderCid(header);
    uint64_t n = lengthWord;
    // Smi length is unexpected but accept a small even Smi just in case.
    if (n > kAVDB115MaxStringChars && (n & 1ull) == 0ull && (n >> 1) <= kAVDB115MaxStringChars) n >>= 1;
    if (n == 0 || n > kAVDB115MaxStringChars) return nil;

    const uint8_t *data = NULL;
    size_t nbytes = 0;
    BOOL latin1 = YES;
    if (cid == kAVDB115OneByteStringCid || cid == kAVDB115TwoByteStringCid) {
        latin1 = (cid == kAVDB115OneByteStringCid);
        uint64_t dataAddr = untagged + 0x10;
        if (dataAddr < regionStart) return nil;
        uint64_t off = dataAddr - regionStart;
        nbytes = latin1 ? (size_t)n : (size_t)n * 2;
        if (off + nbytes > len) return nil;
        data = base + off;
    } else if (cid == kAVDB115ExternalOneByteStringCid || cid == kAVDB115ExternalTwoByteStringCid) {
        latin1 = (cid == kAVDB115ExternalOneByteStringCid);
        uint64_t ptr = 0;
        if (!AVDB115ReadU64(base, len, untagged + 0x10, regionStart, &ptr) || ptr == 0) return nil;
        if (ptr < regionStart) return nil;
        uint64_t off = ptr - regionStart;
        nbytes = latin1 ? (size_t)n : (size_t)n * 2;
        if (off + nbytes > len) return nil;
        data = base + off;
    } else {
        return nil;
    }
    if (latin1) {
        for (size_t i = 0; i < nbytes; i++) {
            if (data[i] < 0x09) return nil;
        }
        return [[NSString alloc] initWithBytes:data length:nbytes encoding:NSISOLatin1StringEncoding];
    }
    return [[NSString alloc] initWithBytes:data length:nbytes encoding:NSUTF16LittleEndianStringEncoding];
}

static void AVDB115CollectFromRegion(const uint8_t *base, size_t len, uint64_t regionStart,
                                     NSString *number, NSMutableArray *links, NSMutableSet *seen) {
    // 1) Reconstruct from live Magnets objects (cid 2678, size 0x70).
    if (len >= 0x70) {
        size_t maxOff = len - 0x70;
        for (size_t off = 0; off + 8 <= len && off <= maxOff; off += 16) {
            uint64_t header = 0;
            memcpy(&header, base + off, 8);
            if (AVDB115HeaderCid(header) != kAVDB115MagnetsCid) continue;
            if (AVDB115HeaderSizeTag(header) != kAVDB115MagnetsSizeTag) continue;
            uint64_t nameT = 0, hashT = 0, typeT = 0, urlT = 0;
            memcpy(&nameT, base + off + 0x18, 8);
            memcpy(&hashT, base + off + 0x20, 8);
            memcpy(&typeT, base + off + 0x60, 8);
            memcpy(&urlT,  base + off + 0x68, 8);
            NSString *name = AVDB115StringAt(base, len, nameT, regionStart);
            NSString *hash = AVDB115StringAt(base, len, hashT, regionStart);
            NSString *type = AVDB115StringAt(base, len, typeT, regionStart);
            NSString *url  = AVDB115StringAt(base, len, urlT, regionStart);
            if (name.length == 0 && hash.length == 0 && url.length == 0) continue;
            if (number.length && ![AVDB115VisibleMagnets text:name matchesCatalog:number] &&
                ![AVDB115VisibleMagnets text:url matchesCatalog:number]) {
                continue;
            }
            NSString *link = [AVDB115VisibleMagnets linkFromMagnetHash:hash name:name type:type url:url];
            if (link.length && ![seen containsObject:link]) {
                [seen addObject:link];
                [links addObject:link];
            }
        }
    }

    // 2) Already-materialized URI strings (ASCII and UTF-16LE).
    void (^addFromText)(NSString *) = ^(NSString *text) {
        if (text.length < 12) return;
        for (NSString *l in [AVDB115Link offlineResourcesIn:text]) {
            if (number.length && ![AVDB115VisibleMagnets text:l matchesCatalog:number] &&
                ![AVDB115VisibleMagnets text:[AVDB115Link displayNameFromLink:l] matchesCatalog:number]) {
                continue;
            }
            if (![seen containsObject:l]) {
                [seen addObject:l];
                [links addObject:l];
            }
        }
    };

    // ASCII / Latin-1
    const char *needles[2] = { "magnet:?xt=urn:btih:", "ed2k://|file|" };
    for (int ni = 0; ni < 2; ni++) {
        const char *needle = needles[ni];
        size_t nlen = strlen(needle);
        const uint8_t *p = base;
        const uint8_t *end = base + len;
        while (p + nlen < end) {
            const uint8_t *found = memmem(p, (size_t)(end - p), needle, nlen);
            if (!found) break;
            size_t remain = (size_t)(end - found);
            size_t take = remain > 1024 ? 1024 : remain;
            NSString *chunk = [[NSString alloc] initWithBytes:found length:take encoding:NSISOLatin1StringEncoding];
            addFromText(chunk);
            p = found + nlen;
        }
    }
    // UTF-16LE of the same prefixes
    static const uint8_t mag16[] = {
        'm',0,'a',0,'g',0,'n',0,'e',0,'t',0,':',0,'?',0,'x',0,'t',0,'=',0,
        'u',0,'r',0,'n',0,':',0,'b',0,'t',0,'i',0,'h',0,':',0
    };
    static const uint8_t ed16[] = {
        'e',0,'d',0,'2',0,'k',0,':',0,'/',0,'/',0,'|',0,'f',0,'i',0,'l',0,'e',0,'|',0
    };
    const uint8_t *need16[2] = { mag16, ed16 };
    size_t n16len[2] = { sizeof(mag16), sizeof(ed16) };
    for (int ni = 0; ni < 2; ni++) {
        const uint8_t *p = base;
        const uint8_t *end = base + len;
        size_t nlen = n16len[ni];
        while (p + nlen < end) {
            const uint8_t *found = memmem(p, (size_t)(end - p), need16[ni], nlen);
            if (!found) break;
            size_t remain = (size_t)(end - found);
            size_t take = remain > 2048 ? 2048 : remain;
            if (take % 2) take--;
            NSString *chunk = [[NSString alloc] initWithBytes:found length:take encoding:NSUTF16LittleEndianStringEncoding];
            addFromText(chunk);
            p = found + nlen;
        }
    }
}

+ (NSArray<NSString *> *)residentLinksMatchingCatalog:(NSString *)number {
    NSMutableArray *links = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    mach_vm_address_t addr = 0;
    mach_vm_size_t size = 0;
    natural_t depth = 0;
    mach_vm_size_t scanned = 0;
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    while (scanned < kAVDB115MaxScanBytes && (CFAbsoluteTimeGetCurrent() - start) < 0.20) {
        vm_region_submap_info_data_64_t info;
        mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;
        kern_return_t kr = mach_vm_region_recurse(mach_task_self(), &addr, &size, &depth,
                                                  (vm_region_recurse_info_t)&info, &count);
        if (kr != KERN_SUCCESS || size == 0) break;
        if (info.is_submap) {
            depth++;
            continue;
        }
        BOOL readable = (info.protection & VM_PROT_READ) != 0;
        BOOL writable = (info.protection & VM_PROT_WRITE) != 0;
        // Dart heap and Dio JSON buffers are readable+writable user memory.
        if (readable && writable && size >= 64 && size <= 256ull * 1024ull * 1024ull) {
            vm_offset_t data = 0;
            mach_msg_type_number_t dataCnt = 0;
            if (mach_vm_read(mach_task_self(), addr, size, &data, &dataCnt) == KERN_SUCCESS && dataCnt >= 64) {
                AVDB115CollectFromRegion((const uint8_t *)data, (size_t)dataCnt, (uint64_t)addr, number, links, seen);
                scanned += dataCnt;
                vm_deallocate(mach_task_self(), data, dataCnt);
            }
        }
        mach_vm_address_t next = addr + size;
        if (next <= addr) break;
        addr = next;
        depth = 0;
    }
    return links;
}

#else

+ (NSArray<NSString *> *)residentLinksMatchingCatalog:(NSString *)number {
    (void)number;
    return @[];
}

#endif

@end
