#import "AVDB115SplashSkip.h"
#import "AVDB115AdBlock.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Official Flutter notification name (FlutterViewController.h). Looked up
// by string so this dylib does not need to link Flutter.framework.
static NSString *const kFlutterSemanticsUpdateNotification = @"FlutterSemanticsUpdateNotification";
static const NSTimeInterval kAVDB115SplashSkipWindow = 20.0;
static const NSTimeInterval kAVDB115SplashSkipPoll = 0.35;

@implementation AVDB115SplashSkipPolicy

+ (NSString *)normalizedLabel:(NSString *)label {
    if (label.length == 0) return @"";
    NSArray<NSString *> *parts = [label componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray<NSString *> *kept = [NSMutableArray array];
    for (NSString *part in parts) {
        if (part.length > 0) [kept addObject:part];
    }
    return [kept componentsJoinedByString:@" "];
}

+ (BOOL)restLooksLikeCountdownOrAd:(NSString *)rest english:(BOOL)english {
    if (rest.length == 0) return YES;
    NSString *pattern = english
        ? @"^([0-9]|sec|secs|second|seconds|s|ad|ads|广告|廣告|\\s)+$"
        : @"^([0-9]|秒|s|S|广告|廣告|ad|Ad|AD|\\s)+$";
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                        options:NSRegularExpressionCaseInsensitive
                                                                          error:nil];
    if (!re) return NO;
    return [re numberOfMatchesInString:rest options:0 range:NSMakeRange(0, rest.length)] == 1;
}

+ (BOOL)isSplashSkipLabel:(NSString *)label {
    NSString *s = [self normalizedLabel:label];
    if (s.length == 0) return NO;

    NSArray<NSString *> *zh = @[@"跳过", @"跳過", @"略过", @"略過"];
    for (NSString *tok in zh) {
        if ([s isEqualToString:tok]) return YES;
        if ([s hasPrefix:tok] && s.length <= 16) {
            NSString *rest = [[s substringFromIndex:tok.length]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if ([self restLooksLikeCountdownOrAd:rest english:NO]) return YES;
        }
    }

    NSArray<NSString *> *click = @[@"点击跳过", @"點擊跳過", @"点击跳过广告", @"點擊跳過廣告"];
    for (NSString *tok in click) {
        if ([s isEqualToString:tok]) return YES;
    }

    NSString *low = s.lowercaseString;
    if ([low isEqualToString:@"skip"] || [low hasPrefix:@"skip "]) {
        NSString *rest = [[s substringFromIndex:4]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if ([self restLooksLikeCountdownOrAd:rest english:YES]) return YES;
    }
    return NO;
}

static void AVDB115CollectViewControllers(UIViewController *vc, NSMutableArray *out) {
    if (!vc) return;
    [out addObject:vc];
    for (UIViewController *child in vc.childViewControllers) {
        AVDB115CollectViewControllers(child, out);
    }
    if (vc.presentedViewController) {
        AVDB115CollectViewControllers(vc.presentedViewController, out);
    }
}

+ (NSArray *)flutterViewControllers {
    Class flutterVC = NSClassFromString(@"FlutterViewController");
    if (!flutterVC) return @[];
    NSMutableArray *found = [NSMutableArray array];
    NSMutableArray *all = [NSMutableArray array];
    // iOS 15+ (deployment target): prefer window scenes so we do not use the
    // deprecated UIApplication.windows API.
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            AVDB115CollectViewControllers(window.rootViewController, all);
        }
    }
    for (UIViewController *vc in all) {
        if ([vc isKindOfClass:flutterVC] && ![found containsObject:vc]) {
            [found addObject:vc];
        }
    }
    return found;
}

+ (void)ensureSemanticsOnEngines {
    SEL sel = NSSelectorFromString(@"ensureSemanticsEnabled");
    SEL engineSel = NSSelectorFromString(@"engine");
    for (id vc in [self flutterViewControllers]) {
        if (![vc respondsToSelector:engineSel]) continue;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id engine = [vc performSelector:engineSel];
        if ([engine respondsToSelector:sel]) {
            [engine performSelector:sel];
        }
#pragma clang diagnostic pop
    }
}

static void AVDB115VisitAccessibility(id el, NSMutableSet *seen, void (^visit)(id)) {
    if (!el) return;
    NSValue *key = [NSValue valueWithNonretainedObject:el];
    if ([seen containsObject:key]) return;
    [seen addObject:key];

    Class wk = NSClassFromString(@"WKWebView");
    if (wk && [el isKindOfClass:wk]) return;

    visit(el);

    NSInteger count = 0;
    if ([el respondsToSelector:@selector(accessibilityElementCount)]) {
        count = [el accessibilityElementCount];
    }
    if (count > 0 && count < 512 && [el respondsToSelector:@selector(accessibilityElementAtIndex:)]) {
        for (NSInteger i = 0; i < count; i++) {
            AVDB115VisitAccessibility([el accessibilityElementAtIndex:i], seen, visit);
        }
    }
    if ([el respondsToSelector:@selector(accessibilityElements)]) {
        id arr = [el accessibilityElements];
        if ([arr isKindOfClass:[NSArray class]]) {
            for (id child in (NSArray *)arr) {
                AVDB115VisitAccessibility(child, seen, visit);
            }
        }
    }
}

+ (BOOL)activateIfSkipElement:(id)el {
    if (!el) return NO;
    NSString *label = nil;
    if ([el respondsToSelector:@selector(accessibilityLabel)]) {
        label = [el accessibilityLabel];
    }
    if (![self isSplashSkipLabel:label]) return NO;
    if ([el respondsToSelector:@selector(accessibilityTraits)]) {
        UIAccessibilityTraits traits = [el accessibilityTraits];
        if (traits & UIAccessibilityTraitNotEnabled) return NO;
    }
    if ([el respondsToSelector:@selector(accessibilityActivate)]) {
        return [el accessibilityActivate];
    }
    return NO;
}

+ (BOOL)scanAndActivateSkip {
    if (!AVDB115AdBlockSettings.shared.enabled) return NO;
    Class flutterViewClass = NSClassFromString(@"FlutterView");
    __block BOOL activated = NO;
    for (UIViewController *vc in [self flutterViewControllers]) {
        UIView *root = vc.view;
        if (!root) continue;
        NSMutableArray<UIView *> *starts = [NSMutableArray array];
        if (flutterViewClass) {
            if ([root isKindOfClass:flutterViewClass]) {
                [starts addObject:root];
            } else {
                for (UIView *sub in root.subviews) {
                    if ([sub isKindOfClass:flutterViewClass]) [starts addObject:sub];
                }
            }
        }
        // Fall back to the Flutter VC view only (never the whole window, so
        // we will not activate controls on the plugin overlay or a WKWebView).
        if (starts.count == 0 && flutterViewClass && [root isKindOfClass:flutterViewClass]) {
            [starts addObject:root];
        }
        if (starts.count == 0 && flutterViewClass) {
            continue;
        }
        if (starts.count == 0) {
            // No FlutterView class symbol in this process; do not scan arbitrarily.
            continue;
        }
        for (UIView *start in starts) {
            NSMutableSet *seen = [NSMutableSet set];
            AVDB115VisitAccessibility(start, seen, ^(id el) {
                if (activated) return;
                if ([self activateIfSkipElement:el]) {
                    activated = YES;
                }
            });
            if (activated) return YES;
        }
    }
    return activated;
}

+ (void)install {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // File-scope-like storage: the once block returns immediately, so
        // state cannot live on its stack. The run loop retains the timer.
        static NSTimeInterval started;
        static BOOL done;
        static NSTimer *timer;
        started = [NSDate date].timeIntervalSince1970;
        done = NO;
        timer = nil;
        void (^tick)(void) = ^{
            if (done) return;
            if (!AVDB115AdBlockSettings.shared.enabled) return;
            if (([NSDate date].timeIntervalSince1970 - started) > kAVDB115SplashSkipWindow) {
                done = YES;
                [timer invalidate];
                timer = nil;
                return;
            }
            [self ensureSemanticsOnEngines];
            if ([self scanAndActivateSkip]) {
                done = YES;
                [timer invalidate];
                timer = nil;
            }
        };
        NSNotificationCenter *c = NSNotificationCenter.defaultCenter;
        [c addObserverForName:kFlutterSemanticsUpdateNotification
                       object:nil
                        queue:NSOperationQueue.mainQueue
                   usingBlock:^(__unused NSNotification *n) {
            tick();
        }];
        [c addObserverForName:UIApplicationDidBecomeActiveNotification
                       object:nil
                        queue:NSOperationQueue.mainQueue
                   usingBlock:^(__unused NSNotification *n) {
            tick();
        }];
        timer = [NSTimer timerWithTimeInterval:kAVDB115SplashSkipPoll
                                       repeats:YES
                                         block:^(__unused NSTimer *t) {
            tick();
        }];
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
        dispatch_async(dispatch_get_main_queue(), ^{
            tick();
        });
    });
}

@end
