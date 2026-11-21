#pragma once
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AVDB115OverlayController : UIViewController
+ (void)startWindowWatcher;
+ (void)attachToKeyWindowIfNeeded;
+ (void)presentFromTop;
+ (void)promptForLink:(NSString *)link;
+ (UIViewController *)topViewController;
@end

NS_ASSUME_NONNULL_END
