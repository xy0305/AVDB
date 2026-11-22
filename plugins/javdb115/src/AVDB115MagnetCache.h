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

/// Links whose name or URI matches the catalog number, plus any recently
/// captured links if the hint is empty.
- (NSArray<NSString *> *)linksForCatalog:(nullable NSString *)number;

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
