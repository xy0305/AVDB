#pragma once
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AVDB115OverlayController : UIViewController
+ (void)startWindowWatcher;
+ (void)attachToKeyWindowIfNeeded;
+ (void)presentFromTop;
+ (void)promptForLink:(NSString *)link;
+ (UIViewController *)topViewController;
+ (nullable UIWindow *)keyWindow;
+ (BOOL)shouldSkipWindow:(nullable UIWindow *)window;
/// Hide the floating 115 button while movie-detail chips are the primary actions.
+ (void)setFloatingButtonHidden:(BOOL)hidden;
@end

NS_ASSUME_NONNULL_END
