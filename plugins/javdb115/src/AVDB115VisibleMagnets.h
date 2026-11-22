#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Collect magnet/ed2k already present on the official movie-magnets page
/// without calling getMovieMagnets or forging jdsignature.
///
/// JavDB 1.9.41 `MagnetListItem` paints `name` / `type` ("ED2K") /
/// `files_count`, not the raw URI, so an accessibility-only scan of
/// `magnet:` / `ed2k://` misses rows that are already on screen. The
/// same items are live `Magnets` objects (cid 2678, movie_info_entity)
/// whose `detailLink` is `buildMagnetLink(hash, name)` or
/// `rebuildEd2kLink(url, name)`. This helper reconstructs that link
/// from already-resident objects and in-memory strings.
@interface AVDB115VisibleMagnets : NSObject

+ (NSString *)magnetLinkWithHash:(NSString *)hash name:(nullable NSString *)name;
+ (nullable NSString *)linkFromMagnetHash:(nullable NSString *)hash
                                      name:(nullable NSString *)name
                                      type:(nullable NSString *)type
                                       url:(nullable NSString *)url;

+ (BOOL)text:(nullable NSString *)text matchesCatalog:(nullable NSString *)number;

/// Prefer a catalog-matching magnet, then a catalog-matching ed2k, then any magnet, then any ed2k.
+ (nullable NSString *)preferredLink:(NSArray<NSString *> *)links
                      catalogNumber:(nullable NSString *)number;

/// Scan already-mapped process memory for live Magnets objects and
/// already-materialized magnet/ed2k strings. Does not request any API.
+ (NSArray<NSString *> *)residentLinksMatchingCatalog:(nullable NSString *)number;
+ (NSArray<NSString *> *)residentLinksMatchingCatalog:(nullable NSString *)number
                                       visibleLabels:(nullable NSArray<NSString *> *)labels;

/// YES when accessibility already shows the 磁鏈下載 list (tab + ED2K / catalog filenames).
+ (BOOL)labelsSuggestVisibleMagnetList:(nullable NSArray<NSString *> *)labels
                        catalogNumber:(nullable NSString *)number;

+ (NSArray<NSString *> *)mergeUniqueLinks:(NSArray<NSString *> *)a
                                 withLinks:(NSArray<NSString *> *)b;

@end

NS_ASSUME_NONNULL_END
