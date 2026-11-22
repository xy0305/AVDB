#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Policy for the movie-detail 115 chip row. The action row itself is Flutter
/// (`MovieDetailLayout` / movieButtonWantWatch, movieButtonWatched,
/// movieButtonSavedList, plus 離線觀看). There is no PlatformView or method
/// channel to insert into that Dart Row; this policy only identifies labels
/// and catalog numbers from already-visible text.
@interface AVDB115DetailPagePolicy : NSObject
+ (BOOL)isActionRowLabel:(nullable NSString *)label;
+ (BOOL)isMagnetTabLabel:(nullable NSString *)label;
+ (BOOL)isBottomTabLabel:(nullable NSString *)label;
+ (BOOL)isVIPBannerLabel:(nullable NSString *)label;
/// First catalog number in nav titles, "番號: MIDA-859", or similar visible text.
+ (nullable NSString *)catalogNumberInText:(nullable NSString *)text;
+ (BOOL)looksLikeMovieDetailWithActionLabels:(NSArray<NSString *> *)labels
                              catalogNumber:(nullable NSString *)number;
@end

@interface AVDB115DetailActions : NSObject
+ (void)install;
/// Hide the UIKit overlay row when the Dart Wrap hook is live (scan still runs).
+ (void)setOverlayRowSuppressed:(BOOL)suppressed;
/// Hide the v6 chip row (and keep it hidden) while the plugin 115 player is up.
+ (void)setPlaybackChromeHidden:(BOOL)hidden;
+ (void)performPushFromDartRow;
+ (void)performPlayFromDartRow;
@end

NS_ASSUME_NONNULL_END
