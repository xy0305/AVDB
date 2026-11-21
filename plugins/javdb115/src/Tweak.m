// AVDB115 dylib plugin for JavDB (com.javdb6.com).
// Additive hooks only: no JavDB membership, payment, or DRM bypass.
// Runtime ObjC swizzling (no Logos/Substrate) so the same dylib works
// as a sideloaded LC_LOAD_DYLIB and as a jailbreak tweak.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "AVDB115OverlayController.h"
#import "AVDB115Link.h"

static void AVDB115SwizzleInstance(Class cls, SEL original, SEL replacement) {
    if (!cls) return;
    Method originalMethod = class_getInstanceMethod(cls, original);
    Method swizzledMethod = class_getInstanceMethod(cls, replacement);
    if (!originalMethod || !swizzledMethod) return;
    if (class_addMethod(cls, original, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod))) {
        class_replaceMethod(cls, replacement, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}

/// Hook a method only if it is implemented on `cls` itself; otherwise add a
/// wrapper that calls the inherited IMP. Avoids rewriting a superclass method
/// (which would affect every FlutterAppDelegate sibling / UIKit delegate).
static void AVDB115HookOrAdd(Class cls, SEL sel, IMP replacement, IMP *outOriginal, const char *fallbackTypes) {
    if (!cls || !sel || !replacement) return;
    Method inherited = class_getInstanceMethod(cls, sel);
    const char *types = inherited ? method_getTypeEncoding(inherited) : fallbackTypes;
    IMP inheritedIMP = inherited ? method_getImplementation(inherited) : NULL;
    Method *list = NULL;
    unsigned int count = 0;
    BOOL definedHere = NO;
    list = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        if (sel_isEqual(method_getName(list[i]), sel)) { definedHere = YES; break; }
    }
    if (list) free(list);
    if (definedHere && inherited) {
        if (outOriginal) *outOriginal = inheritedIMP;
        method_setImplementation(inherited, replacement);
        return;
    }
    if (outOriginal) *outOriginal = inheritedIMP;
    class_addMethod(cls, sel, replacement, types ?: "v@:");
}

static NSString *AVDB115LastPromptedLink;
static NSTimeInterval AVDB115LastPromptAt;

static void AVDB115MaybePrompt(NSString *text) {
    NSString *link = [AVDB115Link firstOfflineResourceIn:text];
    if (link.length == 0) return;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if (AVDB115LastPromptedLink && [AVDB115LastPromptedLink isEqualToString:link] && (now - AVDB115LastPromptAt) < 8) {
        return;
    }
    AVDB115LastPromptedLink = [link copy];
    AVDB115LastPromptAt = now;
    dispatch_async(dispatch_get_main_queue(), ^{
        [AVDB115OverlayController promptForLink:link];
    });
}

@interface AVDB115ShareActivity : UIActivity
@property (nonatomic, copy) NSString *link;
- (instancetype)initWithLink:(NSString *)link;
@end

@implementation AVDB115ShareActivity
- (instancetype)initWithLink:(NSString *)link {
    if (self = [super init]) _link = [link copy];
    return self;
}
- (UIActivityType)activityType { return @"com.avdb115.plugin.push"; }
- (NSString *)activityTitle { return @"推送到 115"; }
- (UIImage *)activityImage { return [UIImage systemImageNamed:@"icloud.and.arrow.up"]; }
- (BOOL)canPerformWithActivityItems:(NSArray *)activityItems { (void)activityItems; return self.link.length > 0; }
- (void)performActivity {
    NSString *link = self.link;
    dispatch_async(dispatch_get_main_queue(), ^{
        [AVDB115OverlayController promptForLink:link];
    });
    [self activityDidFinish:YES];
}
@end

@implementation UIWindow (AVDB115)
- (void)avdb115_becomeKeyWindow {
    [self avdb115_becomeKeyWindow];
    dispatch_async(dispatch_get_main_queue(), ^{
        [AVDB115OverlayController attachToKeyWindowIfNeeded];
    });
}
@end

@implementation UIPasteboard (AVDB115)
- (void)avdb115_setString:(NSString *)string {
    [self avdb115_setString:string];
    // Only magnet/ed2k are examined; anything else is ignored and never stored or uploaded.
    AVDB115MaybePrompt(string);
}
- (void)avdb115_setStrings:(NSArray<NSString *> *)strings {
    [self avdb115_setStrings:strings];
    for (NSString *string in strings) {
        if ([AVDB115Link firstOfflineResourceIn:string].length) {
            AVDB115MaybePrompt(string);
            break;
        }
    }
}
@end

@implementation UIApplication (AVDB115)
- (void)avdb115_openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenExternalURLOptionsKey, id> *)options completionHandler:(void (^)(BOOL))completion {
    NSString *text = url.absoluteString ?: @"";
    if ([AVDB115Link isOfflineResource:text]) {
        AVDB115MaybePrompt(text);
        if (completion) completion(YES);
        return;
    }
    [self avdb115_openURL:url options:options completionHandler:completion];
}
@end

@implementation UIActivityViewController (AVDB115)
- (instancetype)avdb115_initWithActivityItems:(NSArray *)activityItems applicationActivities:(NSArray *)applicationActivities {
    NSString *found = nil;
    for (id item in activityItems) {
        NSString *text = nil;
        if ([item isKindOfClass:[NSString class]]) text = item;
        else if ([item isKindOfClass:[NSURL class]]) text = [((NSURL *)item) absoluteString];
        NSString *link = [AVDB115Link firstOfflineResourceIn:text];
        if (link) { found = link; break; }
    }
    NSMutableArray *extra = [NSMutableArray arrayWithArray:applicationActivities ?: @[]];
    if (found) {
        [extra addObject:[[AVDB115ShareActivity alloc] initWithLink:found]];
    }
    return [self avdb115_initWithActivityItems:activityItems applicationActivities:extra];
}
@end

static BOOL (*AVDB115OrigFlutterLaunch)(id, SEL, UIApplication *, NSDictionary *);

static BOOL AVDB115FlutterLaunch(id self, SEL sel, UIApplication *application, NSDictionary *launchOptions) {
    BOOL ok = YES;
    if (AVDB115OrigFlutterLaunch) {
        ok = AVDB115OrigFlutterLaunch(self, sel, application, launchOptions);
    } else {
        struct objc_super super = { self, class_getSuperclass(object_getClass(self)) };
        BOOL (*msg)(struct objc_super *, SEL, UIApplication *, NSDictionary *) = (void *)objc_msgSendSuper;
        ok = msg(&super, sel, application, launchOptions);
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [AVDB115OverlayController startWindowWatcher];
        [AVDB115OverlayController attachToKeyWindowIfNeeded];
    });
    return ok;
}

static void AVDB115InstallHooks(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        AVDB115SwizzleInstance(UIWindow.class, @selector(becomeKeyWindow), @selector(avdb115_becomeKeyWindow));
        AVDB115SwizzleInstance(UIPasteboard.class, @selector(setString:), @selector(avdb115_setString:));
        AVDB115SwizzleInstance(UIPasteboard.class, @selector(setStrings:), @selector(avdb115_setStrings:));
        AVDB115SwizzleInstance(UIApplication.class, @selector(openURL:options:completionHandler:), @selector(avdb115_openURL:options:completionHandler:));
        AVDB115SwizzleInstance(UIActivityViewController.class, @selector(initWithActivityItems:applicationActivities:), @selector(avdb115_initWithActivityItems:applicationActivities:));
        Class flutter = NSClassFromString(@"FlutterAppDelegate");
        AVDB115HookOrAdd(flutter,
                         @selector(application:didFinishLaunchingWithOptions:),
                         (IMP)AVDB115FlutterLaunch,
                         (IMP *)&AVDB115OrigFlutterLaunch,
                         "B@:@@");
    });
}

__attribute__((constructor))
static void AVDB115Init(void) {
    AVDB115InstallHooks();
    void (^start)(void) = ^{
        [AVDB115OverlayController startWindowWatcher];
        [AVDB115OverlayController attachToKeyWindowIfNeeded];
    };
    if ([NSThread isMainThread]) start();
    else dispatch_async(dispatch_get_main_queue(), start);
}
