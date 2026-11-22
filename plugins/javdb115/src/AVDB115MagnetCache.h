#pragma once
#import <Foundation/Foundation.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

/// Links reconstructed from live Magnets objects at parse/build time
/// (official detailLink rules). Not a signed API cache.
@interface AVDB115MagnetCache : NSObject

+ (instancetype)shared;

/// Add a usable magnet:/ed2k:// link, keyed by catalog number when known.
- (void)addLink:(NSString *)link catalogHint:(nullable NSString *)hint;

/// Same as addLink:catalogHint:, also records the list-API movie id
/// (`/api/v2/movies/{id}/magnets`) when known.
- (void)addLink:(NSString *)link
   catalogHint:(nullable NSString *)hint
        movieId:(nullable NSString *)movieId;

/// Bind a list-API movie id to an on-screen catalog number (same-unit JSON
/// or a magnets batch that already contained the number).
- (void)bindMovieId:(nullable NSString *)movieId toCatalog:(nullable NSString *)number;

/// Movie id extracted from a magnets URL/path, or nil if it is a reserved
/// collection path (latest, recommend, …).
+ (nullable NSString *)movieIdFromURLString:(nullable NSString *)text;

/// Context for the current detail/list page, set just before a harvest so
/// a just-loaded magnets response can be attributed to the visible 番号.
- (void)setLookupCatalog:(nullable NSString *)number
             listVisible:(BOOL)listVisible
           visibleLabels:(nullable NSArray<NSString *> *)labels;

/// Record that a magnets response for this movie id was seen (newest mtime
/// wins). Used only when the 磁鏈下載 list is already on screen.
- (void)noteMagnetsMovieId:(nullable NSString *)movieId
                  seenAt:(nullable NSDate *)date;

/// If the current page 番号 appears in any cached name for this movie id,
/// bind the id to that 番号.
- (void)bindMovieIdToContextIfNamesMatch:(nullable NSString *)movieId;

/// Links whose name, URI, catalog hint, or list-API movie id matches the
/// catalog (via an id↔番号 map). If number is nil, all usable links.
- (NSArray<NSString *> *)linksForCatalog:(nullable NSString *)number;

/// Like linksForCatalog:, also matching visible 磁鏈下載 row names and, when
/// the list is on screen, the newest magnets response for this page.
- (NSArray<NSString *> *)linksForCatalog:(nullable NSString *)number
                           visibleLabels:(nullable NSArray<NSString *> *)labels
                             listVisible:(BOOL)listVisible;

/// Extra diagnostic when usable cache is non-empty but the current 番号
/// matched nothing (lists cached 番号 / movie ids). No secrets.
- (NSString *)attributionDiagnosticForCatalog:(nullable NSString *)number;

/// Safe capture from a tagged Magnets object (cid 2678). Uses only
/// vm_read_overwrite; never dereferences the foreign pointer directly.
- (void)captureTaggedMagnets:(uint64_t)tagged;

/// MagnetListItem (cid 4158): Magnets lives at tagged offset 0x0f.
- (void)captureTaggedMagnetListItem:(uint64_t)taggedItem;

@end

#ifdef __cplusplus
extern "C" {
#endif
void AVDB115CacheCaptureMagnets(uint64_t tagged);
void AVDB115CacheCaptureListItem(uint64_t taggedItem);
#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
