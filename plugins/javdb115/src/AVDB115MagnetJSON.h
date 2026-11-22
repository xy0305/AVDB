#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Parse magnet-list JSON the official app already received and cache
/// official detailLink results (`buildMagnetLink(hash, name)` or existing
/// `ed2k://` url). Never invents hashes, never calls getMovieMagnets, and
/// never forges jdsignature.
@interface AVDB115MagnetJSON : NSObject

/// YES when a URL path looks like the list endpoint
/// `{base}/api/v2/movies/{id}/magnets` (or a closely related magnets path
/// the app itself already requested).
+ (BOOL)isMagnetListURL:(nullable NSURL *)url;
+ (BOOL)isMagnetListURLString:(nullable NSString *)text;

/// Walk a JSON object/array (or parse NSData / NSString) and add usable
/// magnet:/ed2k:// links to AVDB115MagnetCache. Returns how many new links
/// were added this call.
+ (NSUInteger)ingestJSONObject:(nullable id)obj catalogHint:(nullable NSString *)hint;
+ (NSUInteger)ingestData:(nullable NSData *)data
                     url:(nullable NSURL *)url
             catalogHint:(nullable NSString *)hint;
+ (NSUInteger)ingestUTF8Bytes:(const void *)bytes
                       length:(NSUInteger)length
                  catalogHint:(nullable NSString *)hint;

/// Walk already-cached movie list/detail JSON and record id↔番号 maps only.
/// Does not invent magnets or issue requests.
+ (NSUInteger)ingestMovieIndexFromData:(nullable NSData *)data;

/// Diagnostic line. If catalog is set, also reports how many usable cache
/// rows matched that 番号 and which 番号 / movie ids are in the cache.
+ (NSString *)diagnosticLineForCatalog:(nullable NSString *)number;

/// Snapshot used by the failure dialog so a device test can tell which
/// path was empty. Does not include secrets.
+ (NSDictionary<NSString *, id> *)diagnosticSnapshot;
+ (NSString *)diagnosticLine;

+ (void)addHttpCaptureCount:(NSUInteger)n;
+ (void)setFileHarvestCount:(NSUInteger)n;
+ (void)setPlaintextHarvestCount:(NSUInteger)n;
+ (void)setDartObjectScanCount:(NSUInteger)n;
+ (void)setURLSessionHookInstalled:(BOOL)ok;
+ (void)setURLProtocolRegistered:(BOOL)ok;

@end

NS_ASSUME_NONNULL_END
