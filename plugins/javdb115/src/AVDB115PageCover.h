#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Policy for replacing JavDB original-page covers with AVDB HQ sources.
/// A replacement is allowed only when a classified JavDB cover URL and a catalog
/// number are bound in the SAME unit (JSON object or HTML card). The URL alone
/// is never enough. This type does not install a network hook.
@interface AVDB115PageCoverSettings : NSObject
@property (class, readonly) AVDB115PageCoverSettings *shared;
/// Default YES. The switch is retained even though the Flutter page hook cannot be armed.
@property (nonatomic) BOOL replaceEnabled;
/// Honest, localized reason whether a native original-page hook is active.
@property (nonatomic, readonly) NSString *hookStatus;
@property (nonatomic, readonly) BOOL hookArmed;
@end

@interface AVDB115PageCoverPolicy : NSObject
+ (BOOL)isJavDBCoverURL:(nullable NSString *)urlString;
+ (BOOL)isJavDBSampleURL:(nullable NSString *)urlString;
+ (nullable NSString *)movieUIDFromCoverURL:(nullable NSString *)urlString;
/// Catalog number from the same JSON object only. Values must parse as a number.
+ (nullable NSString *)numberFromUnit:(nullable NSDictionary *)unit;
+ (nullable NSString *)coverURLFromUnit:(nullable NSDictionary *)unit;
/// Bind a cover URL to a number only when both belong to the same unit.
+ (nullable NSString *)numberBoundToCoverURL:(nullable NSString *)urlString inUnit:(nullable NSDictionary *)unit;
/// Return deterministic HQ candidate URLs, or nil to keep the original image.
+ (nullable NSArray<NSString *> *)hqCandidatesIfRewritable:(nullable NSString *)urlString
                                                     unit:(nullable NSDictionary *)unit
                                                  enabled:(BOOL)enabled;
+ (NSArray<NSDictionary *> *)unitsFromHomepageHTML:(NSString *)html;
@end

NS_ASSUME_NONNULL_END
