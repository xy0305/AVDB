#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runtime hook for MoviePageState._getButtonLine (JavDB 1.9.41).
/// Wraps the function entry (FAT 0x3c1144 / vm 0x3bd144) and, after the
/// original Wrap is built, appends two MyInkWell chips after the existing
/// Consumer. Does not rewrite the packed 0x3b4 body, does not replace
/// 離線觀看, and does not hook getMovieMagnets.
///
/// Installation may fail (text not writable, image not found). In that case
/// the v6 UIKit overlay remains the action path. Device success is untested.
@interface AVDB115DartRowHook : NSObject
+ (void)install;
+ (BOOL)isInstalled;
@end

#ifdef __cplusplus
extern "C" {
#endif
/// Called from the Dart call$0 trampolines (kind 0 = push, 1 = play).
void AVDB115DartHandleTap(intptr_t kind);
#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
