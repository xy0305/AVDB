#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Narrow policy for dismissing only the Flutter in-app splash ad
/// (`SplashPage` / `_handleAd` / skip label), not the iOS LaunchScreen
/// and not SplashPage startup work (domain probe, update, local auth).
@interface AVDB115SplashSkipPolicy : NSObject
/// True for short, identifiable splash-ad skip labels such as 跳过 / 跳过 5 / Skip.
+ (BOOL)isSplashSkipLabel:(nullable NSString *)label;
/// Start a short-lived post-launch scan. Safe to call more than once.
+ (void)install;
@end

NS_ASSUME_NONNULL_END
