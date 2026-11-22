#import "AVDB115DetailActions.h"
#import "AVDB115OverlayController.h"
#import "AVDB115Catalog.h"
#import "AVDB115Link.h"
#import "AVDB115VisibleMagnets.h"
#import "AVDB115MagnetCache.h"
#import "AVDB115MagnetJSON.h"
#import "AVDB115FileCacheHarvest.h"
#import "AVDB115PlaintextHarvest.h"
#import "AVDB115Client.h"
#import "AVDB115Settings.h"
#import "AVDB115PlayerViewController.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString *const kFlutterSemanticsUpdateNotification = @"FlutterSemanticsUpdateNotification";
static const void *kAVDB115MagnetTabKey = &kAVDB115MagnetTabKey;

static NSString *AVDB115NormLabel(NSString *label) {
    if (label.length == 0) return @"";
    NSArray *parts = [label componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray *kept = [NSMutableArray array];
    for (NSString *p in parts) if (p.length) [kept addObject:p];
    return [kept componentsJoinedByString:@" "];
}

@implementation AVDB115DetailPagePolicy

+ (NSSet<NSString *> *)actionLabels {
    return [NSSet setWithArray:@[
        @"想看", @"看过", @"看過",
        @"存入清單", @"存入清单",
        @"離線觀看", @"离线观看",
    ]];
}

+ (BOOL)isActionRowLabel:(NSString *)label {
    NSString *s = AVDB115NormLabel(label);
    return s.length > 0 && [[self actionLabels] containsObject:s];
}

+ (BOOL)isMagnetTabLabel:(NSString *)label {
    NSString *s = AVDB115NormLabel(label);
    if (s.length == 0) return NO;
    if ([s isEqualToString:@"磁鏈下載"] || [s isEqualToString:@"磁链下载"]) return YES;
    // Badge, e.g. "磁鏈下載 6"
    if ([s hasPrefix:@"磁鏈下載"] || [s hasPrefix:@"磁链下载"]) {
        NSString *tok = [s hasPrefix:@"磁鏈下載"] ? @"磁鏈下載" : @"磁链下载";
        NSString *rest = [[s substringFromIndex:tok.length]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (rest.length == 0) return YES;
        static NSRegularExpression *re;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            re = [NSRegularExpression regularExpressionWithPattern:@"^[0-9]{1,4}$" options:0 error:nil];
        });
        return [re numberOfMatchesInString:rest options:0 range:NSMakeRange(0, rest.length)] == 1;
    }
    return NO;
}

+ (BOOL)isBottomTabLabel:(NSString *)label {
    if ([self isMagnetTabLabel:label]) return YES;
    NSString *s = AVDB115NormLabel(label);
    return [s isEqualToString:@"短評"] || [s isEqualToString:@"短评"]
        || [s isEqualToString:@"相關清單"] || [s isEqualToString:@"相关清单"];
}

+ (BOOL)isVIPBannerLabel:(NSString *)label {
    NSString *s = AVDB115NormLabel(label);
    return [s isEqualToString:@"購買VIP"] || [s isEqualToString:@"购买VIP"]
        || [s hasPrefix:@"購買VIP"] || [s hasPrefix:@"购买VIP"];
}

+ (NSString *)tokenIfCatalog:(NSString *)token {
    NSString *t = [token stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (t.length == 0) return nil;
    if (![AVDB115CatalogNumber identityKey:t] && ![AVDB115CatalogNumber parse:t]) return nil;
    return t.uppercaseString;
}

+ (NSString *)catalogNumberInText:(NSString *)text {
    if (text.length == 0) return nil;
    NSString *s = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (s.length == 0) return nil;

    static NSRegularExpression *fieldRe;
    static NSRegularExpression *tokenRe;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fieldRe = [NSRegularExpression regularExpressionWithPattern:@"(?:番號|番号)\\s*[:：]?\\s*([A-Za-z0-9][A-Za-z0-9._-]{1,24})"
                                                           options:0
                                                             error:nil];
        tokenRe = [NSRegularExpression regularExpressionWithPattern:@"(?<![A-Za-z0-9])([A-Za-z]{1,4}[0-9]{1,4}[-_ ][0-9]{2,10}|[0-9]{1,4}[A-Za-z]{2,12}[-_ ]?[0-9]{2,10}|[A-Za-z]{2,12}[-_ ]?[0-9]{2,10})(?![A-Za-z0-9])"
                                                           options:0
                                                             error:nil];
    });

    NSTextCheckingResult *field = [fieldRe firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    if (field && field.numberOfRanges > 1) {
        NSString *tok = [s substringWithRange:[field rangeAtIndex:1]];
        NSString *ok = [self tokenIfCatalog:tok];
        if (ok) return ok;
    }

    NSString *whole = [self tokenIfCatalog:s];
    if (whole) return whole;

    NSArray<NSTextCheckingResult *> *matches = [tokenRe matchesInString:s options:0 range:NSMakeRange(0, s.length)];
    for (NSTextCheckingResult *m in matches) {
        if (m.numberOfRanges < 2) continue;
        NSString *ok = [self tokenIfCatalog:[s substringWithRange:[m rangeAtIndex:1]]];
        if (ok) return ok;
    }
    return nil;
}

+ (BOOL)looksLikeMovieDetailWithActionLabels:(NSArray<NSString *> *)labels
                              catalogNumber:(NSString *)number {
    if (number.length == 0) return NO;
    BOOL want = NO, watched = NO, list = NO, offline = NO;
    for (NSString *raw in labels) {
        NSString *s = AVDB115NormLabel(raw);
        if ([s isEqualToString:@"想看"]) want = YES;
        else if ([s isEqualToString:@"看过"] || [s isEqualToString:@"看過"]) watched = YES;
        else if ([s isEqualToString:@"存入清單"] || [s isEqualToString:@"存入清单"]) list = YES;
        else if ([s isEqualToString:@"離線觀看"] || [s isEqualToString:@"离线观看"]) offline = YES;
    }
    NSInteger unique = (want?1:0) + (watched?1:0) + (list?1:0) + (offline?1:0);
    // Require the distinctive detail chips (list / offline) or at least two of the four.
    if (list || offline) return unique >= 1 && number.length > 0;
    return unique >= 2;
}

@end

static void AVDB115CollectControllers(UIViewController *vc, NSMutableArray *out) {
    if (!vc) return;
    [out addObject:vc];
    for (UIViewController *child in vc.childViewControllers) {
        AVDB115CollectControllers(child, out);
    }
    if (vc.presentedViewController) {
        AVDB115CollectControllers(vc.presentedViewController, out);
    }
}

#pragma mark - Overlay row

static const CGFloat kAVDB115ChipHeight = 32.0;
static const CGFloat kAVDB115ChipRadius = 16.0;
static const CGFloat kAVDB115ChipGap = 8.0;
static const CGFloat kAVDB115SideInset = 16.0;
static const NSInteger kAVDB115ColumnCount = 4;

@interface AVDB115DetailActions ()
@property (nonatomic, strong) UIView *row;
@property (nonatomic, strong) UIButton *pushButton;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIButton *settingsButton;
@property (nonatomic, copy) NSString *currentNumber;
@property (nonatomic, copy) NSArray<NSString *> *visibleLinks;
@property (nonatomic, copy) NSArray<NSString *> *visibleLabels;
@property (nonatomic, assign) BOOL magnetListVisible;
@property (nonatomic, assign) BOOL suppressOverlayRow;
@property (nonatomic, assign) BOOL playbackChromeHidden;
@property (nonatomic, assign) BOOL installed;
@property (nonatomic, assign) BOOL onDetail;
@property (nonatomic, strong) NSTimer *timer;
- (void)refresh;
- (void)tapPush;
- (void)tapPlay;
@end

@implementation AVDB115DetailActions

+ (instancetype)shared {
    static AVDB115DetailActions *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[AVDB115DetailActions alloc] init]; });
    return instance;
}

+ (void)install {
    [[self shared] install];
}

+ (void)setOverlayRowSuppressed:(BOOL)suppressed {
    AVDB115DetailActions *s = [self shared];
    s.suppressOverlayRow = suppressed;
    if (suppressed) {
        s.row.hidden = YES;
    }
}

+ (void)setPlaybackChromeHidden:(BOOL)hidden {
    AVDB115DetailActions *s = [self shared];
    s.playbackChromeHidden = hidden;
    if (hidden) {
        if (s.row) s.row.hidden = YES;
        [AVDB115OverlayController setFloatingButtonHidden:YES];
    } else {
        [s refresh];
    }
}

+ (void)performPushFromDartRow {
    AVDB115DetailActions *s = [self shared];
    [s refresh];
    [s tapPush];
}

+ (void)performPlayFromDartRow {
    AVDB115DetailActions *s = [self shared];
    [s refresh];
    [s tapPlay];
}


- (void)install {
    if (self.installed) return;
    self.installed = YES;
    NSNotificationCenter *c = NSNotificationCenter.defaultCenter;
    __weak typeof(self) weakSelf = self;
    void (^tick)(NSNotification *) = ^(__unused NSNotification *n) {
        [weakSelf refresh];
    };
    [c addObserverForName:kFlutterSemanticsUpdateNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:tick];
    [c addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:tick];
    [c addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:tick];
    [c addObserverForName:UIWindowDidBecomeKeyNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:tick];
    self.timer = [NSTimer timerWithTimeInterval:0.35 repeats:YES block:^(__unused NSTimer *t) {
        [weakSelf refresh];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; });
}

#pragma mark Windows / Flutter

- (UIWindow *)keyWindow {
    return [AVDB115OverlayController keyWindow] ?: ({
        UIWindow *found = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) { found = w; break; }
            }
            if (found) break;
            if (((UIWindowScene *)scene).windows.count) found = ((UIWindowScene *)scene).windows.firstObject;
        }
        found;
    });
}

- (NSArray<UIViewController *> *)flutterViewControllersInWindow:(UIWindow *)window {
    Class flutterVC = NSClassFromString(@"FlutterViewController");
    if (!flutterVC || !window) return @[];
    NSMutableArray *all = [NSMutableArray array];
    NSMutableArray *found = [NSMutableArray array];
    AVDB115CollectControllers(window.rootViewController, all);
    for (UIViewController *vc in all) {
        if ([vc isKindOfClass:flutterVC]) [found addObject:vc];
    }
    return found;
}

- (void)ensureSemantics {
    SEL sel = NSSelectorFromString(@"ensureSemanticsEnabled");
    SEL engineSel = NSSelectorFromString(@"engine");
    UIWindow *window = [self keyWindow];
    for (id vc in [self flutterViewControllersInWindow:window]) {
        if (![vc respondsToSelector:engineSel]) continue;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id engine = [vc performSelector:engineSel];
        if ([engine respondsToSelector:sel]) [engine performSelector:sel];
#pragma clang diagnostic pop
    }
}

static void AVDB115VisitAcc(id el, NSMutableSet *seen, void (^visit)(id)) {
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
            AVDB115VisitAcc([el accessibilityElementAtIndex:i], seen, visit);
        }
    }
    if ([el respondsToSelector:@selector(accessibilityElements)]) {
        id arr = [el accessibilityElements];
        if ([arr isKindOfClass:[NSArray class]]) {
            for (id child in (NSArray *)arr) AVDB115VisitAcc(child, seen, visit);
        }
    }
}

- (NSArray<UIView *> *)flutterViewsInWindow:(UIWindow *)window {
    Class flutterViewClass = NSClassFromString(@"FlutterView");
    NSMutableArray *starts = [NSMutableArray array];
    if (!flutterViewClass) return starts;
    for (UIViewController *vc in [self flutterViewControllersInWindow:window]) {
        UIView *root = vc.view;
        if ([root isKindOfClass:flutterViewClass]) [starts addObject:root];
        for (UIView *sub in root.subviews) {
            if ([sub isKindOfClass:flutterViewClass] && ![starts containsObject:sub]) [starts addObject:sub];
        }
    }
    return starts;
}

#pragma mark Scan

- (void)refresh {
    if (self.playbackChromeHidden) {
        if (self.row) self.row.hidden = YES;
        [AVDB115OverlayController setFloatingButtonHidden:YES];
        return;
    }
    if (NSClassFromString(@"FlutterViewController")) [self ensureSemantics];
    UIWindow *window = [self keyWindow];
    if (!window) return;
    if ([AVDB115OverlayController shouldSkipWindow:window]) return;

    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    NSMutableArray<NSValue *> *actionFrames = [NSMutableArray array];
    NSMutableArray<NSValue *> *tabFrames = [NSMutableArray array];
    NSMutableArray<NSValue *> *vipFrames = [NSMutableArray array];
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    NSMutableArray *magnetTabElements = [NSMutableArray array];
    __block NSString *number = nil;

    void (^consider)(id) = ^(id el) {
        NSString *label = [el respondsToSelector:@selector(accessibilityLabel)] ? [el accessibilityLabel] : nil;
        NSString *value = [el respondsToSelector:@selector(accessibilityValue)] ? [el accessibilityValue] : nil;
        NSString *hint = [el respondsToSelector:@selector(accessibilityHint)] ? [el accessibilityHint] : nil;
        NSString *ident = [el respondsToSelector:@selector(accessibilityIdentifier)] ? [el accessibilityIdentifier] : nil;
        if (label.length) [texts addObject:label];
        if (value.length) [texts addObject:value];
        if (hint.length) [texts addObject:hint];
        if (ident.length) [texts addObject:ident];
        if (label.length) [labels addObject:label];
        if (!number) number = [AVDB115DetailPagePolicy catalogNumberInText:label];
        if (!number) number = [AVDB115DetailPagePolicy catalogNumberInText:value];
        if (!number) number = [AVDB115DetailPagePolicy catalogNumberInText:hint];
        if (!number) number = [AVDB115DetailPagePolicy catalogNumberInText:ident];
        CGRect frame = CGRectZero;
        if ([el respondsToSelector:@selector(accessibilityFrame)]) frame = [el accessibilityFrame];
        if ([AVDB115DetailPagePolicy isActionRowLabel:label] && !CGRectIsEmpty(frame)) {
            [actionFrames addObject:[NSValue valueWithCGRect:frame]];
        }
        if ([AVDB115DetailPagePolicy isBottomTabLabel:label] && !CGRectIsEmpty(frame)) {
            [tabFrames addObject:[NSValue valueWithCGRect:frame]];
        }
        if ([AVDB115DetailPagePolicy isMagnetTabLabel:label]) {
            [magnetTabElements addObject:el];
        }
        if ([AVDB115DetailPagePolicy isVIPBannerLabel:label] && !CGRectIsEmpty(frame)) {
            [vipFrames addObject:[NSValue valueWithCGRect:frame]];
        }
        NSString *link = [AVDB115Link firstOfflineResourceIn:label] ?: [AVDB115Link firstOfflineResourceIn:value];
        (void)link;
    };

    NSMutableSet *seen = [NSMutableSet set];
    NSArray *starts = [self flutterViewsInWindow:window];
    if (starts.count == 0) {
        // No FlutterView: do not scan the whole window (would include our own chips).
        [self leaveDetail:window];
        return;
    }
    for (UIView *start in starts) AVDB115VisitAcc(start, seen, consider);

    // Collect magnets after the walk (avoid capturing mutable array issues).
    NSMutableArray<NSString *> *links = [NSMutableArray array];
    NSMutableSet *linkSet = [NSMutableSet set];
    for (NSString *t in texts) {
        for (NSString *l in [AVDB115Link offlineResourcesIn:t]) {
            if (![linkSet containsObject:l]) {
                [linkSet addObject:l];
                [links addObject:l];
            }
        }
    }

    if (!number) {
        for (NSString *t in texts) {
            number = [AVDB115DetailPagePolicy catalogNumberInText:t];
            if (number) break;
        }
    }

    BOOL detail = [AVDB115DetailPagePolicy looksLikeMovieDetailWithActionLabels:labels catalogNumber:number];
    if (!detail) {
        [self leaveDetail:window];
        return;
    }

    self.onDetail = YES;
    self.currentNumber = number;
    self.visibleLinks = links;
    self.visibleLabels = [labels copy];
    self.magnetListVisible = [AVDB115VisibleMagnets labelsSuggestVisibleMagnetList:labels catalogNumber:number];
    objc_setAssociatedObject(self, kAVDB115MagnetTabKey, magnetTabElements, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [AVDB115OverlayController setFloatingButtonHidden:YES];
    [self showRowInWindow:window actionFrames:actionFrames tabFrames:tabFrames vipFrames:vipFrames];
}

- (void)leaveDetail:(UIWindow *)window {
    (void)window;
    if (self.onDetail) {
        self.onDetail = NO;
        [AVDB115OverlayController setFloatingButtonHidden:NO];
    }
    self.currentNumber = nil;
    self.visibleLinks = @[];
    self.visibleLabels = @[];
    self.magnetListVisible = NO;
    self.row.hidden = YES;
}

#pragma mark Layout

- (UIButton *)capsuleButton:(NSString *)title action:(SEL)action prominent:(BOOL)prominent {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    b.titleLabel.adjustsFontSizeToFitWidth = YES;
    b.titleLabel.minimumScaleFactor = 0.75;
    b.layer.cornerRadius = kAVDB115ChipRadius;
    b.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    if (prominent) {
        b.backgroundColor = [UIColor secondarySystemFillColor];
        b.layer.borderColor = [UIColor separatorColor].CGColor;
        [b setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
    } else {
        b.backgroundColor = [UIColor clearColor];
        b.layer.borderColor = [UIColor separatorColor].CGColor;
        [b setTitleColor:UIColor.secondaryLabelColor forState:UIControlStateNormal];
    }
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)ensureRowInWindow:(UIWindow *)window {
    if (self.row && self.row.superview == window) return;
    [self.row removeFromSuperview];
    UIView *row = [[UIView alloc] initWithFrame:CGRectZero];
    row.backgroundColor = UIColor.clearColor;
    row.userInteractionEnabled = YES;
    row.accessibilityIdentifier = @"avdb115.detail.actions";
    self.pushButton = [self capsuleButton:@"推送到 115" action:@selector(tapPush) prominent:YES];
    self.playButton = [self capsuleButton:@"115 播放" action:@selector(tapPlay) prominent:YES];
    self.settingsButton = [self capsuleButton:@"115 设置" action:@selector(tapSettings) prominent:NO];
    self.pushButton.accessibilityLabel = @"推送到 115";
    self.playButton.accessibilityLabel = @"115 播放";
    self.settingsButton.accessibilityLabel = @"打开 115 设置";
    [row addSubview:self.pushButton];
    [row addSubview:self.playButton];
    [row addSubview:self.settingsButton];
    [window addSubview:row];
    self.row = row;
}

- (CGRect)rowFrameInWindow:(UIWindow *)window
              actionFrames:(NSArray<NSValue *> *)actionFrames
                 tabFrames:(NSArray<NSValue *> *)tabFrames
                 vipFrames:(NSArray<NSValue *> *)vipFrames {
    CGRect bounds = window.bounds;
    UIEdgeInsets safe = window.safeAreaInsets;
    CGFloat width = bounds.size.width - kAVDB115SideInset * 2;
    CGFloat height = kAVDB115ChipHeight;
    CGFloat x = kAVDB115SideInset;

    // Stable default: just above the bottom tab bar (磁鏈下載 / 短評 / 相關清單).
    // Following the mid-page Flutter action row during scroll is not reliable:
    // those chips are painted into FlutterView and accessibility frames often
    // lag, which would leave a jumpy or stale overlay over other content.
    CGFloat tabTop = bounds.size.height - safe.bottom - 49.0;
    if (tabFrames.count) {
        CGFloat minY = CGFLOAT_MAX;
        for (NSValue *v in tabFrames) {
            CGRect f = [self rectInWindow:window fromAccessibility:[v CGRectValue]];
            if (CGRectIsEmpty(f)) continue;
            minY = MIN(minY, CGRectGetMinY(f));
        }
        if (minY < CGFLOAT_MAX && minY > safe.top + 80) tabTop = minY;
    }
    CGFloat y = tabTop - kAVDB115ChipGap - height;
    CGRect proposed = CGRectMake(x, y, width, height);

    // Never cover the VIP banner or the upper cover / play area.
    CGFloat vipBottom = 0;
    for (NSValue *v in vipFrames) {
        CGRect f = [self rectInWindow:window fromAccessibility:[v CGRectValue]];
        if (!CGRectIsEmpty(f)) vipBottom = MAX(vipBottom, CGRectGetMaxY(f));
    }
    if (vipBottom > 0 && CGRectGetMinY(proposed) < vipBottom + 6) {
        proposed.origin.y = vipBottom + 6;
    }
    CGFloat minY = safe.top + 56; // below a typical nav bar
    if (CGRectGetMinY(proposed) < minY) proposed.origin.y = minY;
    if (CGRectGetMaxY(proposed) > tabTop - 4) {
        proposed.origin.y = tabTop - 4 - height;
    }
    (void)actionFrames; // inspected for future same-row work; not used for placement
    return proposed;
}

- (CGRect)rectInWindow:(UIWindow *)window fromAccessibility:(CGRect)acc {
    if (CGRectIsEmpty(acc) || !window) return acc;
    // accessibilityFrame is in screen coordinates.
    CGRect r = [window convertRect:acc fromView:nil];
    if (CGRectIsEmpty(r) || isnan(r.origin.x) || isnan(r.origin.y)) return acc;
    return r;
}

- (void)showRowInWindow:(UIWindow *)window
           actionFrames:(NSArray<NSValue *> *)actionFrames
              tabFrames:(NSArray<NSValue *> *)tabFrames
              vipFrames:(NSArray<NSValue *> *)vipFrames {
    if (self.suppressOverlayRow) {
        if (self.row) self.row.hidden = YES;
        return;
    }
    [self ensureRowInWindow:window];
    [window bringSubviewToFront:self.row];
    self.row.hidden = NO;
    CGRect frame = [self rowFrameInWindow:window actionFrames:actionFrames tabFrames:tabFrames vipFrames:vipFrames];
    self.row.frame = frame;
    CGFloat col = (frame.size.width - kAVDB115ChipGap * (kAVDB115ColumnCount - 1)) / (CGFloat)kAVDB115ColumnCount;
    if (col < 44) col = (frame.size.width - kAVDB115ChipGap) / 3.0;
    CGFloat h = frame.size.height;
    self.pushButton.frame = CGRectMake(0, 0, col, h);
    self.playButton.frame = CGRectMake(col + kAVDB115ChipGap, 0, col, h);
    self.settingsButton.frame = CGRectMake((col + kAVDB115ChipGap) * 2, 0, col, h);
    self.pushButton.layer.cornerRadius = h / 2.0;
    self.playButton.layer.cornerRadius = h / 2.0;
    self.settingsButton.layer.cornerRadius = h / 2.0;
}

#pragma mark Actions

- (UIViewController *)presenter {
    return [AVDB115OverlayController topViewController];
}

- (void)alert:(NSString *)title message:(NSString *)message {
    UIViewController *top = [self presenter];
    if (!top) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [top presentViewController:a animated:YES completion:nil];
}

- (void)tapSettings {
    [AVDB115OverlayController presentFromTop];
}

- (void)tapPlay {
    NSString *number = self.currentNumber;
    if (number.length == 0) {
        [self alert:@"115 播放" message:@"还没有从当前详情页读到番号（导航标题或「番號」字段）。"];
        return;
    }
    if (!AVDB115Settings.shared.isConfigured) {
        [self alert:@"115 播放" message:AVDB115Settings.shared.missingHint ?: @"请先在设置里填写 115 Cookie。也可点「115 设置」。"];
        return;
    }
    NSString *magnet = [AVDB115VisibleMagnets preferredLink:[self usableLinksForCurrentPage]
                                            catalogNumber:number];
    UIViewController *top = [self presenter];
    if (!top) return;
    AVDB115PlayerViewController *player = [[AVDB115PlayerViewController alloc] initWithKeyword:number magnet:magnet];
    [top presentViewController:player animated:YES completion:nil];
}

- (NSArray<NSString *> *)usableLinksForCurrentPage {
    [self refresh];
    // v13: native intercept cache first (HTTP / FileCacheStore / raw JSON).
    // These do not patch App.framework and do not call getMovieMagnets.
    // v15: tell the cache which 番号 / 磁鏈下載 page is on screen *before*
    // harvest, so a /api/v2/movies/{id}/magnets body can be attributed even
    // when individual file names omit the catalog.
    @try {
        [[AVDB115MagnetCache shared] setLookupCatalog:self.currentNumber
                                          listVisible:self.magnetListVisible
                                        visibleLabels:self.visibleLabels];
    } @catch (NSException *ex) {}
    @try { [AVDB115FileCacheHarvest harvest]; } @catch (NSException *ex) {}
    NSArray<NSString *> *fromCache = @[];
    @try {
        fromCache = [[AVDB115MagnetCache shared] linksForCatalog:self.currentNumber
                                                   visibleLabels:self.visibleLabels
                                                     listVisible:self.magnetListVisible] ?: @[];
    } @catch (NSException *ex) {
        fromCache = @[];
    }
    if (fromCache.count == 0) {
        @try { [AVDB115PlaintextHarvest harvestMatchingCatalog:self.currentNumber]; } @catch (NSException *ex) {}
        @try {
            fromCache = [[AVDB115MagnetCache shared] linksForCatalog:self.currentNumber
                                                       visibleLabels:self.visibleLabels
                                                         listVisible:self.magnetListVisible] ?: @[];
        } @catch (NSException *ex) {
            fromCache = fromCache ?: @[];
        }
    }
    NSArray<NSString *> *fromTree = self.visibleLinks ?: @[];
    NSArray<NSString *> *fromResident = @[];
    if (fromCache.count == 0) {
        @try {
            fromResident = [AVDB115VisibleMagnets residentLinksMatchingCatalog:self.currentNumber
                                                               visibleLabels:self.visibleLabels] ?: @[];
        } @catch (NSException *ex) {
            fromResident = @[];
        }
        [AVDB115MagnetJSON setDartObjectScanCount:fromResident.count];
    }
    return [AVDB115VisibleMagnets mergeUniqueLinks:fromCache
                                         withLinks:[AVDB115VisibleMagnets mergeUniqueLinks:fromTree withLinks:fromResident]];
}

- (void)tapPush {
    NSString *number = self.currentNumber ?: @"";
    if (!AVDB115Settings.shared.isConfigured) {
        [self alert:@"推送到 115" message:AVDB115Settings.shared.missingHint ?: @"请先在设置里填写 115 Cookie。也可点「115 设置」。"];
        return;
    }
    // One-tap: pick a usable magnet/ed2k already shown or already resident
    // (Magnets.detailLink reconstruction). Do not call getMovieMagnets.
    NSArray<NSString *> *links = [self usableLinksForCurrentPage];
    if (number.length == 0 && self.currentNumber.length) number = self.currentNumber;
    NSString *pick = [AVDB115VisibleMagnets preferredLink:links catalogNumber:number];
    if (pick.length) {
        [self pushLink:pick];
        return;
    }
    [self tryOpenMagnetTabThenPush:number];
}

- (void)tryOpenMagnetTabThenPush:(NSString *)number {
    NSArray *tabs = objc_getAssociatedObject(self, kAVDB115MagnetTabKey);
    __block BOOL activated = NO;
    for (id el in tabs) {
        if ([el respondsToSelector:@selector(accessibilityActivate)]) {
            if ([el accessibilityActivate]) { activated = YES; break; }
        }
    }
    UIViewController *top = [self presenter];
    if (!top) return;
    NSString *clipboard = [AVDB115Link firstOfflineResourceIn:UIPasteboard.generalPasteboard.string];
    NSString *msg;
    if (self.magnetListVisible) {
        NSString *diag = [AVDB115MagnetJSON diagnosticLineForCatalog:number];
        msg = number.length
            ? [NSString stringWithFormat:@"「磁鏈下載」列表已在当前页，但仍未能还原 %@ 的 magnet/ed2k（不会请求带签名的磁力接口）。%@ 若列表里有复制按钮，可先复制一条再点「使用剪贴板链接」。", number, diag]
            : [NSString stringWithFormat:@"「磁鏈下載」列表已在当前页，但仍未能还原 magnet/ed2k（不会请求带签名的磁力接口）。%@ 若列表里有复制按钮，可先复制一条再点「使用剪贴板链接」。", diag];
    } else if (number.length) {
        msg = [NSString stringWithFormat:@"当前页还没有解析到 %@ 的 magnet/ed2k（已扫描无障碍树和已载入的列表数据，不会请求带签名的磁力接口）。%@ 若「磁鏈下載」列表尚未打开，请先打开后再点一次推送，或使用已复制的链接。", number, [AVDB115MagnetJSON diagnosticLineForCatalog:number]];
    } else {
        msg = [NSString stringWithFormat:@"当前页还没有解析到 magnet/ed2k（已扫描无障碍树和已载入的列表数据，不会请求带签名的磁力接口）。%@ 若「磁鏈下載」列表尚未打开，请先打开后再点一次推送，或使用已复制的链接。", [AVDB115MagnetJSON diagnosticLineForCatalog:number]];
    }
    if (activated && !self.magnetListVisible) {
        msg = [msg stringByAppendingString:@"\n已尝试切到「磁鏈下載」标签。若列表出现后请再点一次推送。"];
    }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"推送到 115" message:msg preferredStyle:UIAlertControllerStyleAlert];
    if (clipboard.length) {
        NSString *shortL = clipboard.length > 120 ? [[clipboard substringToIndex:120] stringByAppendingString:@"…"] : clipboard;
        [a addAction:[UIAlertAction actionWithTitle:@"使用剪贴板链接" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) {
            [self pushLink:clipboard];
        }]];
        (void)shortL;
    }
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:a animated:YES completion:nil];
    if (activated) {
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf refresh];
        });
    }
}

- (void)chooseAndPushLinks:(NSArray<NSString *> *)links number:(NSString *)number {
    if (links.count == 1) {
        [self pushLink:links.firstObject];
        return;
    }
    UIViewController *top = [self presenter];
    if (!top) return;
    NSString *title = number.length ? [NSString stringWithFormat:@"推送 %@ 到 115", number] : @"推送到 115";
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title message:@"当前页上有多个磁力/ed2k，请选一条。" preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *link in links) {
        NSString *name = [AVDB115Link displayNameFromLink:link] ?: link;
        if (name.length > 48) name = [[name substringToIndex:48] stringByAppendingString:@"…"];
        [sheet addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            [self pushLink:link];
        }]];
        if (sheet.actions.count >= 8) break;
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.pushButton ?: top.view;
    sheet.popoverPresentationController.sourceRect = self.pushButton.bounds;
    [top presentViewController:sheet animated:YES completion:nil];
}

- (void)pushLink:(NSString *)link {
    if (![AVDB115Link isOfflineResource:link]) {
        [self alert:@"推送到 115" message:@"不是有效的 magnet / ed2k。"];
        return;
    }
    UIViewController *top = [self presenter];
    if (!top) return;
    UIAlertController *wait = [UIAlertController alertControllerWithTitle:@"推送到 115" message:@"正在推送…" preferredStyle:UIAlertControllerStyleAlert];
    [top presentViewController:wait animated:YES completion:^{
        [AVDB115Client.shared addOfflineTask:link
                                      cookie:AVDB115Settings.shared.cookie
                                   folderCID:AVDB115Settings.shared.folderCID
                                  completion:^(AVDB115PushResult *result, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *msg = error.localizedDescription ?: (result.message ?: @"完成");
                [wait dismissViewControllerAnimated:YES completion:^{
                    [self alert:@"推送到 115" message:msg];
                }];
            });
        }];
    }];
}

@end
