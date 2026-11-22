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
    NSMutableArray<NSMutableDictionary *> *_rows; // link, hint, movieId
    NSMutableDictionary<NSString *, NSString *> *_idToCatalog; // movieId → identityKey
    NSMutableDictionary<NSString *, NSString *> *_catalogToId; // identityKey → movieId
    NSLock *_lock;
    NSString *_contextCatalog;
    BOOL _contextListVisible;
    NSArray<NSString *> *_contextLabels;
    NSString *_newestMovieId;
    NSDate *_newestMovieAt;
}

static NSSet<NSString *> *AVDB115ReservedMovieIds(void) {
    static NSSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [NSSet setWithArray:@[
            @"latest", @"recommend", @"followed", @"top", @"tags", @"lucky",
            @"may_also_like", @"recommend_periods", @"search", @"popular",
            @"new", @"index", @"show", @"magnets", @"ranks", @"rank",
            @"reviews", @"comments", @"lists", @"focus", @"new_arrival",
        ]];
    });
    return set;
}

+ (NSString *)movieIdFromURLString:(NSString *)text {
    if (text.length == 0) return nil;
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression regularExpressionWithPattern:
              @"/api/v[0-9]+/movies/([A-Za-z0-9_-]{2,64})(?:/magnets)?(?:\\b|$|[/?#])"
              options:NSRegularExpressionCaseInsensitive error:nil];
    });
    NSString *best = nil;
    NSArray *matches = [re matchesInString:text options:0 range:NSMakeRange(0, text.length)];
    for (NSTextCheckingResult *m in matches) {
        if (m.numberOfRanges < 2) continue;
        NSString *cand = [text substringWithRange:[m rangeAtIndex:1]];
        if ([AVDB115ReservedMovieIds() containsObject:cand.lowercaseString]) continue;
        // JavDB movie ids are slugs (e.g. AqXeXO), not bare integers.
        if ([cand rangeOfCharacterFromSet:[NSCharacterSet letterCharacterSet]].location == NSNotFound) continue;
        // Prefer a match that sits on a /magnets path.
        NSRange full = m.range;
        NSString *around = [text substringWithRange:full].lowercaseString;
        if ([around containsString:@"/magnets"]) return cand;
        if (!best) best = cand;
    }
    return best;
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
        _idToCatalog = [NSMutableDictionary dictionary];
        _catalogToId = [NSMutableDictionary dictionary];
        _lock = [[NSLock alloc] init];
    }
    return self;
}

- (NSString *)normalizedCatalog:(NSString *)raw {
    if (raw.length == 0) return nil;
    // Do not treat API paths as 番号 hints.
    if ([raw containsString:@"/api/"] || [raw containsString:@"://"] || [raw containsString:@"/magnets"]) {
        return [AVDB115DetailPagePolicy catalogNumberInText:raw];
    }
    return [AVDB115DetailPagePolicy catalogNumberInText:raw] ?:
           [AVDB115CatalogNumber identityKey:raw];
}

- (void)bindMovieIdLocked:(NSString *)movieId toCatalog:(NSString *)number {
    if (movieId.length == 0 || number.length == 0) return;
    if ([AVDB115ReservedMovieIds() containsObject:movieId.lowercaseString]) return;
    NSString *cat = [AVDB115CatalogNumber identityKey:number] ?: number.uppercaseString;
    if (cat.length == 0) return;
    NSString *existing = _idToCatalog[movieId];
    if (existing.length && ![existing isEqualToString:cat]) {
        // Keep the first binding; do not silently retarget another 番号.
        return;
    }
    _idToCatalog[movieId] = cat;
    _catalogToId[cat] = movieId;
}

- (void)bindMovieId:(NSString *)movieId toCatalog:(NSString *)number {
    [_lock lock];
    [self bindMovieIdLocked:movieId toCatalog:number];
    [_lock unlock];
}

- (void)setLookupCatalog:(NSString *)number
             listVisible:(BOOL)listVisible
           visibleLabels:(NSArray<NSString *> *)labels {
    [_lock lock];
    _contextCatalog = [number copy];
    _contextListVisible = listVisible;
    _contextLabels = [labels copy];
    [_lock unlock];
}

- (void)noteMagnetsMovieId:(NSString *)movieId seenAt:(NSDate *)date {
    if (movieId.length == 0) return;
    if ([AVDB115ReservedMovieIds() containsObject:movieId.lowercaseString]) return;
    NSDate *when = date ?: [NSDate date];
    [_lock lock];
    if (!_newestMovieAt || [when compare:_newestMovieAt] != NSOrderedAscending) {
        _newestMovieId = [movieId copy];
        _newestMovieAt = when;
    }
    [_lock unlock];
}

- (void)addLink:(NSString *)link catalogHint:(NSString *)hint {
    [self addLink:link catalogHint:hint movieId:nil];
}

- (void)bindMovieIdToContextIfNamesMatch:(NSString *)movieId {
    if (movieId.length == 0) return;
    [_lock lock];
    NSString *wanted = [_contextCatalog copy];
    NSArray *snap = [_rows copy];
    [_lock unlock];
    if (wanted.length == 0) return;
    for (NSDictionary *r in snap) {
        if (![r[@"movieId"] isEqualToString:movieId]) continue;
        NSString *link = r[@"link"];
        NSString *hint = r[@"hint"];
        if ([AVDB115VisibleMagnets text:link matchesCatalog:wanted] ||
            [AVDB115VisibleMagnets text:[AVDB115Link displayNameFromLink:link] matchesCatalog:wanted] ||
            [AVDB115VisibleMagnets text:hint matchesCatalog:wanted]) {
            [self bindMovieId:movieId toCatalog:wanted];
            return;
        }
    }
}


- (void)addLink:(NSString *)link catalogHint:(NSString *)hint movieId:(NSString *)movieId {
    if (![AVDB115Link isOfflineResource:link]) return;
    NSString *fromHintPath = [AVDB115MagnetCache movieIdFromURLString:hint];
    NSString *fromLink = [AVDB115MagnetCache movieIdFromURLString:link];
    NSString *mid = movieId.length ? movieId : (fromHintPath ?: fromLink);
    NSString *cat = [self normalizedCatalog:hint];
    if (!cat) cat = [AVDB115DetailPagePolicy catalogNumberInText:link] ?:
                   [AVDB115CatalogNumber identityKey:[AVDB115Link displayNameFromLink:link]];
    NSString *key = cat ?: @"";
    [_lock lock];
    BOOL found = NO;
    for (NSMutableDictionary *r in _rows) {
        if ([r[@"link"] isEqualToString:link]) {
            if (key.length && (![r[@"hint"] length] || [self normalizedCatalog:r[@"hint"]].length == 0)) {
                r[@"hint"] = key;
            }
            if (mid.length && ![r[@"movieId"] length]) r[@"movieId"] = mid;
            found = YES;
            break;
        }
    }
    if (!found) {
        if (_rows.count > 256) {
            [_rows removeObjectsInRange:NSMakeRange(0, _rows.count - 192)];
        }
        NSMutableDictionary *row = [NSMutableDictionary dictionary];
        row[@"link"] = link;
        row[@"hint"] = key;
        if (mid.length) row[@"movieId"] = mid;
        [_rows addObject:row];
    }
    // Do not bind movieId to a catalog inferred from a single file name
    // (e.g. "clear-sis-01" → SIS-01). That would lock the whole
    // /movies/{id}/magnets batch to the wrong 番号. Binding happens from
    // same-unit movie JSON, or from the current page context.
    [_lock unlock];
}

- (BOOL)row:(NSDictionary *)r matchesCatalog:(NSString *)number
                             mappedId:(NSString *)mappedId {
    NSString *link = r[@"link"];
    NSString *hint = r[@"hint"];
    NSString *mid = r[@"movieId"];
    if ([AVDB115VisibleMagnets text:link matchesCatalog:number]) return YES;
    if ([AVDB115VisibleMagnets text:[AVDB115Link displayNameFromLink:link] matchesCatalog:number]) return YES;
    if ([AVDB115VisibleMagnets text:hint matchesCatalog:number]) return YES;
    if (mappedId.length && mid.length && [mid isEqualToString:mappedId]) return YES;
    return NO;
}

- (NSArray<NSString *> *)linksFromRows:(NSArray *)snap
                           matching:(BOOL (^)(NSDictionary *r))block {
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSDictionary *r in snap) {
        NSString *link = r[@"link"];
        if (![AVDB115Link isOfflineResource:link]) continue;
        if (!block(r)) continue;
        if ([seen containsObject:link]) continue;
        [seen addObject:link];
        [out addObject:link];
    }
    return out;
}

- (NSArray<NSString *> *)linksForCatalog:(NSString *)number {
    return [self linksForCatalog:number visibleLabels:nil listVisible:NO];
}

- (NSArray<NSString *> *)linksForCatalog:(NSString *)number
                           visibleLabels:(NSArray<NSString *> *)labels
                             listVisible:(BOOL)listVisible {
    [_lock lock];
    NSArray *snap = [_rows copy];
    NSString *mappedId = nil;
    if (number.length) {
        NSString *cat = [AVDB115CatalogNumber identityKey:number] ?: number.uppercaseString;
        mappedId = _catalogToId[cat];
        if (!mappedId.length) {
            // identityKey may already be stored; also try raw.
            mappedId = _catalogToId[number.uppercaseString];
        }
    }
    NSString *newest = _newestMovieId;
    NSDictionary *idMap = [_idToCatalog copy];
    [_lock unlock];

    if (number.length == 0) {
        return [self linksFromRows:snap matching:^BOOL(__unused NSDictionary *r) { return YES; }];
    }

    NSArray *direct = [self linksFromRows:snap matching:^BOOL(NSDictionary *r) {
        return [self row:r matchesCatalog:number mappedId:mappedId];
    }];
    if (direct.count) return direct;

    // Visible 磁鏈下載 row titles (may omit the 番号) matched against cached names.
    NSArray *labs = labels;
    if (labs.count == 0) {
        [_lock lock];
        labs = _contextLabels;
        if (!listVisible) listVisible = _contextListVisible;
        [_lock unlock];
    }
    if (listVisible && labs.count) {
        NSMutableSet *ids = [NSMutableSet set];
        NSArray *byName = [self linksFromRows:snap matching:^BOOL(NSDictionary *r) {
            NSString *name = [AVDB115Link displayNameFromLink:r[@"link"]] ?: r[@"hint"];
            if (name.length == 0) return NO;
            for (NSString *lab in labs) {
                if (lab.length < 4) continue;
                if ([name isEqualToString:lab] || [name containsString:lab] || [lab containsString:name]) {
                    if ([r[@"movieId"] length]) [ids addObject:r[@"movieId"]];
                    return YES;
                }
            }
            return NO;
        }];
        if (ids.count) {
            NSArray *sameId = [self linksFromRows:snap matching:^BOOL(NSDictionary *r) {
                return [r[@"movieId"] length] && [ids containsObject:r[@"movieId"]];
            }];
            if (sameId.count) return sameId;
        }
        if (byName.count) return byName;
    }

    // On-screen list, newest magnets response not already bound to another 番号.
    if (listVisible && newest.length) {
        NSString *bound = idMap[newest];
        BOOL other = bound.length && ![AVDB115VisibleMagnets text:bound matchesCatalog:number];
        if (!other) {
            [self bindMovieId:newest toCatalog:number];
            NSArray *recent = [self linksFromRows:snap matching:^BOOL(NSDictionary *r) {
                return [r[@"movieId"] isEqualToString:newest];
            }];
            if (recent.count) return recent;
        }
    }
    return @[];
}

- (NSString *)attributionDiagnosticForCatalog:(NSString *)number {
    [_lock lock];
    NSArray *snap = [_rows copy];
    NSDictionary *idMap = [_idToCatalog copy];
    NSDictionary *catMap = [_catalogToId copy];
    [_lock unlock];
    NSUInteger usable = 0;
    NSUInteger matched = 0;
    NSString *mappedId = nil;
    if (number.length) {
        NSString *cat = [AVDB115CatalogNumber identityKey:number] ?: number.uppercaseString;
        mappedId = catMap[cat] ?: catMap[number.uppercaseString];
    }
    NSMutableOrderedSet *cats = [NSMutableOrderedSet orderedSet];
    NSMutableOrderedSet *ids = [NSMutableOrderedSet orderedSet];
    for (NSDictionary *r in snap) {
        if (![AVDB115Link isOfflineResource:r[@"link"]]) continue;
        usable++;
        if (number.length && [self row:r matchesCatalog:number mappedId:mappedId]) matched++;
        NSString *hint = r[@"hint"];
        NSString *cat = [self normalizedCatalog:hint];
        if (cat.length) [cats addObject:cat];
        NSString *mid = r[@"movieId"];
        if (mid.length) [ids addObject:mid];
    }
    for (NSString *cid in idMap) {
        if (cid.length) [ids addObject:cid];
        if ([idMap[cid] length]) [cats addObject:idMap[cid]];
    }
    (void)usable;
    NSArray *catList = [cats.array subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)8, cats.count))];
    NSArray *idList = [ids.array subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)8, ids.count))];
    NSString *catStr = catList.count ? [catList componentsJoinedByString:@","] : @"(无)";
    NSString *idStr = idList.count ? [idList componentsJoinedByString:@","] : @"(无)";
    return [NSString stringWithFormat:@"当前番号匹配=%lu 缓存番号=%@ 缓存影片id=%@",
            (unsigned long)matched, catStr, idStr];
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
