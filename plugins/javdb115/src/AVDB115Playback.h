#pragma once
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Presentation helpers for the plugin's 115 player (AVPlayerViewController
/// hosted by AVDB115PlayerViewController). Default orientation is landscape.
/// Does not change JavDB official player routes.
@interface AVDB115Playback : NSObject
+ (BOOL)isPlayerPresented;
+ (void)playerWillAppearInView:(UIView *)view;
+ (void)playerWillDisappearFromView:(UIView *)view;
+ (UIInterfaceOrientationMask)playerOrientationMask;
+ (UIInterfaceOrientation)preferredPlayerOrientation;
+ (UIInterfaceOrientationMask)applicationOrientationsOrDefault:(UIInterfaceOrientationMask)fallback;
@end

NS_ASSUME_NONNULL_END
