#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Native HD-cover overlay for JavDB movie grids (homepage 「近期可播放更新」
/// and other same-pipeline grids). Matches visible catalog numbers and paints
/// AVDB CoverResolver images over estimated cover cells. Does not patch
/// App.framework and does not rewrite dart:io image bytes.
@interface AVDB115HomeCoverOverlay : NSObject
+ (void)install;
+ (void)setSuppressed:(BOOL)suppressed;
@end

NS_ASSUME_NONNULL_END
