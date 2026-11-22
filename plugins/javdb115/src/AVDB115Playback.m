#import "AVDB115Playback.h"
#import "AVDB115DetailActions.h"
#import "AVDB115OverlayController.h"
#import "AVDB115HomeCoverOverlay.h"

static BOOL gPlayerPresented = NO;

@implementation AVDB115Playback

+ (BOOL)isPlayerPresented { return gPlayerPresented; }

+ (UIInterfaceOrientationMask)playerOrientationMask {
    return UIInterfaceOrientationMaskLandscape;
}

+ (UIInterfaceOrientation)preferredPlayerOrientation {
    return UIInterfaceOrientationLandscapeRight;
}

+ (void)setChromeHidden:(BOOL)hidden {
    [AVDB115DetailActions setPlaybackChromeHidden:hidden];
    [AVDB115OverlayController setFloatingButtonHidden:hidden];
    [AVDB115HomeCoverOverlay setSuppressed:hidden];
}

+ (void)requestMask:(UIInterfaceOrientationMask)mask inView:(UIView *)view {
    UIWindow *window = view.window ?: AVDB115OverlayController.keyWindow;
    UIWindowScene *scene = window.windowScene;
    if (@available(iOS 16.0, *)) {
        if (scene) {
            UIWindowSceneGeometryPreferencesIOS *prefs =
                [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:mask];
            [scene requestGeometryUpdateWithPreferences:prefs errorHandler:^(__unused NSError *error) {
                // Soft-fail: the player still presents; orientation may stay portrait
                // until the user rotates if the scene rejects the request.
            }];
        }
        UIViewController *vc = window.rootViewController;
        while (vc.presentedViewController) vc = vc.presentedViewController;
        if ([vc respondsToSelector:@selector(setNeedsUpdateOfSupportedInterfaceOrientations)]) {
            [vc setNeedsUpdateOfSupportedInterfaceOrientations];
        }
    } else {
        UIInterfaceOrientation target = (mask & UIInterfaceOrientationMaskLandscapeRight)
            ? UIInterfaceOrientationLandscapeRight
            : ((mask & UIInterfaceOrientationMaskLandscapeLeft)
               ? UIInterfaceOrientationLandscapeLeft
               : UIInterfaceOrientationPortrait);
        @try {
            [[UIDevice currentDevice] setValue:@(target) forKey:@"orientation"];
            [UIViewController attemptRotationToDeviceOrientation];
        } @catch (NSException *ex) {
        }
    }
}

+ (void)playerWillAppearInView:(UIView *)view {
    gPlayerPresented = YES;
    [self setChromeHidden:YES];
    [self requestMask:UIInterfaceOrientationMaskLandscape inView:view];
}

+ (void)playerWillDisappearFromView:(UIView *)view {
    gPlayerPresented = NO;
    [self requestMask:UIInterfaceOrientationMaskPortrait inView:view];
    [self setChromeHidden:NO];
}

+ (UIInterfaceOrientationMask)applicationOrientationsOrDefault:(UIInterfaceOrientationMask)fallback {
    if (gPlayerPresented) return [self playerOrientationMask];
    return fallback;
}

@end
