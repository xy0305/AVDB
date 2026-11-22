#import "AVDB115HomeCoverOverlay.h"
#import "AVDB115CoverResolver.h"
#import "AVDB115DetailActions.h"
#import "AVDB115OverlayController.h"
#import "AVDB115PageCover.h"
#import "AVDB115Playback.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString *const kFlutterSemanticsUpdateNotification = @"FlutterSemanticsUpdateNotification";
static const NSInteger kAVDB115HomeCoverMaxConcurrent = 3;
static const NSInteger kAVDB115HomeCoverMinGrid = 3;

@interface AVDB115HomeCoverHit : NSObject
@property (nonatomic, copy) NSString *number;
@property (nonatomic) CGRect numberFrame;
@property (nonatomic) CGRect cellFrame;
@property (nonatomic) CGRect coverFrame;
@end
@implementation AVDB115HomeCoverHit
@end

@interface AVDB115HomeCoverOverlay ()
@property (nonatomic, assign) BOOL installed;
@property (nonatomic, assign) BOOL suppressed;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) UIView *container;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIImageView *> *views;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *images;
@property (nonatomic, strong) NSMutableSet<NSString *> *inflight;
@property (nonatomic, strong) NSMutableArray<NSString *> *pending;
@property (nonatomic, strong) NSMutableDictionary<NSString *, AVDB115CoverResolver *> *resolvers;
@end

@implementation AVDB115HomeCoverOverlay

+ (AVDB115HomeCoverOverlay *)shared {
    static AVDB115HomeCoverOverlay *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[AVDB115HomeCoverOverlay alloc] init]; });
    return instance;
}

+ (void)install { [[self shared] install]; }

+ (void)setSuppressed:(BOOL)suppressed {
    AVDB115HomeCoverOverlay *s = [self shared];
    s.suppressed = suppressed;
    if (suppressed) {
        s.container.hidden = YES;
    } else {
        [s refresh];
    }
}

- (instancetype)init {
    if (self = [super init]) {
        _views = [NSMutableDictionary dictionary];
        _images = [[NSCache alloc] init];
        _images.countLimit = 48;
        _inflight = [NSMutableSet set];
        _pending = [NSMutableArray array];
        _resolvers = [NSMutableDictionary dictionary];
    }
    return self;
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

#pragma mark Windows / a11y

- (UIWindow *)keyWindow {
    return [AVDB115OverlayController keyWindow];
}

- (void)ensureSemantics {
    SEL sel = NSSelectorFromString(@"ensureSemanticsEnabled");
    SEL engineSel = NSSelectorFromString(@"engine");
    UIWindow *window = [self keyWindow];
    Class flutterVC = NSClassFromString(@"FlutterViewController");
    if (!flutterVC || !window) return;
    NSMutableArray *all = [NSMutableArray array];
    void (^walk)(UIViewController *) = nil;
    __block void (__strong ^walkStrong)(UIViewController *);
    walkStrong = ^(UIViewController *vc) {
        if (!vc) return;
        [all addObject:vc];
        for (UIViewController *c in vc.childViewControllers) walkStrong(c);
        if (vc.presentedViewController) walkStrong(vc.presentedViewController);
    };
    walkStrong(window.rootViewController);
    for (UIViewController *vc in all) {
        if (![vc isKindOfClass:flutterVC]) continue;
        if (![vc respondsToSelector:engineSel]) continue;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id engine = [vc performSelector:engineSel];
        if ([engine respondsToSelector:sel]) [engine performSelector:sel];
#pragma clang diagnostic pop
    }
}

static void AVDB115HomeCoverVisitAcc(id el, NSMutableSet *seen, void (^visit)(id)) {
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
            AVDB115HomeCoverVisitAcc([el accessibilityElementAtIndex:i], seen, visit);
        }
    }
    if ([el respondsToSelector:@selector(accessibilityElements)]) {
        id arr = [el accessibilityElements];
        if ([arr isKindOfClass:[NSArray class]]) {
            for (id child in (NSArray *)arr) AVDB115HomeCoverVisitAcc(child, seen, visit);
        }
    }
}

- (NSArray<UIView *> *)flutterViewsInWindow:(UIWindow *)window {
    Class flutterVC = NSClassFromString(@"FlutterViewController");
    Class flutterViewClass = NSClassFromString(@"FlutterView");
    NSMutableArray *starts = [NSMutableArray array];
    if (!flutterVC || !flutterViewClass || !window) return starts;
    NSMutableArray *all = [NSMutableArray array];
    void (^walk)(UIViewController *);
    __block void (__strong ^walkStrong)(UIViewController *);
    walkStrong = ^(UIViewController *vc) {
        if (!vc) return;
        [all addObject:vc];
        for (UIViewController *c in vc.childViewControllers) walkStrong(c);
        if (vc.presentedViewController) walkStrong(vc.presentedViewController);
    };
    walkStrong(window.rootViewController);
    for (UIViewController *vc in all) {
        if (![vc isKindOfClass:flutterVC]) continue;
        UIView *root = vc.view;
        if ([root isKindOfClass:flutterViewClass]) [starts addObject:root];
        for (UIView *sub in root.subviews) {
            if ([sub isKindOfClass:flutterViewClass] && ![starts containsObject:sub]) [starts addObject:sub];
        }
    }
    return starts;
}

- (CGRect)rectInWindow:(UIWindow *)window fromAccessibility:(CGRect)acc {
    if (CGRectIsEmpty(acc) || !window) return acc;
    CGRect r = [window convertRect:acc fromView:nil];
    if (CGRectIsEmpty(r) || isnan(r.origin.x) || isnan(r.origin.y)) return acc;
    return r;
}

#pragma mark Layout

- (NSArray<AVDB115HomeCoverHit *> *)hitsFromNumberFrames:(NSArray<AVDB115HomeCoverHit *> *)raw
                                                  window:(UIWindow *)window
                                           sectionLikely:(BOOL)sectionLikely {
    if (raw.count == 0) return @[];
    // Require a grid so a lone detail-page 番号 is not painted over.
    if (raw.count < kAVDB115HomeCoverMinGrid && !sectionLikely) return @[];
    if (raw.count == 1 && sectionLikely) {
        // Still skip a single large hero unless it looks cell-sized.
        CGRect nf = raw[0].numberFrame;
        if (nf.size.width > window.bounds.size.width * 0.55) return @[];
    }

    NSArray *sortedY = [raw sortedArrayUsingComparator:^NSComparisonResult(AVDB115HomeCoverHit *a, AVDB115HomeCoverHit *b) {
        if (a.numberFrame.origin.y < b.numberFrame.origin.y) return NSOrderedAscending;
        if (a.numberFrame.origin.y > b.numberFrame.origin.y) return NSOrderedDescending;
        return a.numberFrame.origin.x < b.numberFrame.origin.x ? NSOrderedAscending : NSOrderedDescending;
    }];

    NSMutableArray<NSMutableArray<AVDB115HomeCoverHit *> *> *rows = [NSMutableArray array];
    for (AVDB115HomeCoverHit *hit in sortedY) {
        NSMutableArray *row = rows.lastObject;
        if (row && fabs(hit.numberFrame.origin.y - [row[0] numberFrame].origin.y) < 18) {
            [row addObject:hit];
        } else {
            [rows addObject:[NSMutableArray arrayWithObject:hit]];
        }
    }

    CGFloat cellW = 0;
    NSMutableArray *widths = [NSMutableArray array];
    for (AVDB115HomeCoverHit *hit in raw) {
        if (hit.cellFrame.size.width > 60 && hit.cellFrame.size.width < window.bounds.size.width * 0.55) {
            [widths addObject:@(hit.cellFrame.size.width)];
        } else if (hit.numberFrame.size.width > 60 && hit.numberFrame.size.width < 220) {
            [widths addObject:@(hit.numberFrame.size.width)];
        }
    }
    // Horizontal gaps in a row are a stronger cell-width signal.
    for (NSArray<AVDB115HomeCoverHit *> *row in rows) {
        if (row.count < 2) continue;
        NSArray *xs = [row sortedArrayUsingComparator:^NSComparisonResult(AVDB115HomeCoverHit *a, AVDB115HomeCoverHit *b) {
            return a.numberFrame.origin.x < b.numberFrame.origin.x ? NSOrderedAscending : NSOrderedDescending;
        }];
        for (NSUInteger i = 1; i < xs.count; i++) {
            CGFloat gap = [xs[i] numberFrame].origin.x - [xs[i - 1] numberFrame].origin.x;
            if (gap > 80 && gap < 240) [widths addObject:@(gap)];
        }
    }
    if (widths.count) {
        NSArray *sorted = [widths sortedArrayUsingSelector:@selector(compare:)];
        cellW = [sorted[sorted.count / 2] doubleValue];
    }
    if (cellW < 80) cellW = 110;
    if (cellW > 200) cellW = 140;

    CGFloat rowGap = 0;
    if (rows.count >= 2) {
        rowGap = [rows[1][0] numberFrame].origin.y - [rows[0][0] numberFrame].origin.y;
    }
    CGFloat textBlock = 48;
    CGFloat coverH = cellW * 1.42;
    if (rowGap > 100) {
        coverH = MAX(80, rowGap - textBlock);
    }
    if (coverH > 260) coverH = cellW * 1.45;
    if (coverH < 80) coverH = cellW * 1.35;

    CGFloat topSafe = 44;
    if (@available(iOS 11.0, *)) topSafe = window.safeAreaInsets.top + 36;
    CGFloat bottomSafe = 56;
    if (@available(iOS 11.0, *)) bottomSafe = window.safeAreaInsets.bottom + 56;

    NSMutableArray *out = [NSMutableArray array];
    for (AVDB115HomeCoverHit *hit in raw) {
        CGRect nf = hit.numberFrame;
        CGRect cover;
        if (!CGRectIsEmpty(hit.cellFrame) && hit.cellFrame.size.height > nf.size.height * 2.2) {
            CGRect cell = hit.cellFrame;
            CGFloat h = MIN(cell.size.width * 1.5, MAX(80, cell.size.height - textBlock));
            cover = CGRectMake(cell.origin.x + 2, cell.origin.y + 2, cell.size.width - 4, h - 2);
        } else {
            CGFloat x = CGRectGetMidX(nf) - cellW / 2.0;
            CGFloat y = nf.origin.y - 22 - coverH; // title line sits just above the number
            if (y < 0) y = nf.origin.y - coverH;
            cover = CGRectInset(CGRectMake(x, y, cellW, coverH), 2, 2);
        }
        // Clip to usable Flutter area (keep title bar and tab bar clear).
        if (cover.origin.y < topSafe) {
            CGFloat d = topSafe - cover.origin.y;
            cover.origin.y += d;
            cover.size.height -= d;
        }
        CGFloat maxY = window.bounds.size.height - bottomSafe;
        if (CGRectGetMaxY(cover) > maxY) cover.size.height = maxY - cover.origin.y;
        if (cover.size.width < 60 || cover.size.height < 70) continue;
        if (cover.origin.x < -8 || CGRectGetMaxX(cover) > window.bounds.size.width + 8) {
            if (cover.origin.x < 0) {
                cover.size.width += cover.origin.x;
                cover.origin.x = 0;
            }
            if (CGRectGetMaxX(cover) > window.bounds.size.width) {
                cover.size.width = window.bounds.size.width - cover.origin.x;
            }
        }
        // Do not cover the 115 FAB area.
        CGRect fab = CGRectMake(window.bounds.size.width - 80, window.bounds.size.height - 160, 80, 160);
        if (CGRectIntersectsRect(CGRectInset(cover, 8, 8), fab)) continue;
        hit.coverFrame = cover;
        [out addObject:hit];
    }
    return out;
}

#pragma mark Refresh

- (void)ensureContainerInWindow:(UIWindow *)window {
    if (self.container && self.container.superview == window) {
        // Keep below the 115 FAB and detail chips if they exist.
        UIView *frontChrome = nil;
        for (UIView *v in window.subviews) {
            if (v == self.container) continue;
            if ([v isKindOfClass:[UIButton class]] &&
                [((UIButton *)v).accessibilityLabel isEqualToString:@"115 离线推送与播放"]) {
                frontChrome = v;
            }
        }
        if (frontChrome) [window insertSubview:self.container belowSubview:frontChrome];
        return;
    }
    [self.container removeFromSuperview];
    UIView *c = [[UIView alloc] initWithFrame:window.bounds];
    c.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    c.userInteractionEnabled = NO;
    c.backgroundColor = UIColor.clearColor;
    c.accessibilityElementsHidden = YES;
    self.container = c;
    UIView *frontChrome = nil;
    for (UIView *v in window.subviews) {
        if ([v isKindOfClass:[UIButton class]] &&
            [((UIButton *)v).accessibilityLabel isEqualToString:@"115 离线推送与播放"]) {
            frontChrome = v;
        }
    }
    if (frontChrome) [window insertSubview:c belowSubview:frontChrome];
    else [window addSubview:c];
}

- (void)refresh {
    if (self.suppressed || [AVDB115Playback isPlayerPresented]) {
        self.container.hidden = YES;
        return;
    }
    if (!AVDB115PageCoverSettings.shared.replaceEnabled) {
        self.container.hidden = YES;
        for (UIImageView *iv in self.views.allValues) iv.hidden = YES;
        return;
    }
    UIWindow *window = [self keyWindow];
    if (!window || [AVDB115OverlayController shouldSkipWindow:window]) return;
    if (NSClassFromString(@"FlutterViewController")) [self ensureSemantics];

    NSMutableArray<AVDB115HomeCoverHit *> *raw = [NSMutableArray array];
    NSMutableSet *seenNumbers = [NSMutableSet set];
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    __block BOOL sectionLikely = NO;
    __block NSString *catalogOnPage = nil;

    void (^consider)(id) = ^(id el) {
        NSString *label = [el respondsToSelector:@selector(accessibilityLabel)] ? [el accessibilityLabel] : nil;
        NSString *value = [el respondsToSelector:@selector(accessibilityValue)] ? [el accessibilityValue] : nil;
        NSString *text = label.length ? label : value;
        if (text.length) {
            [labels addObject:text];
            if ([text containsString:@"近期可播放更新"] || [text containsString:@"換一組"] || [text containsString:@"换一组"]) {
                sectionLikely = YES;
            }
            NSString *n = [AVDB115DetailPagePolicy catalogNumberInText:text];
            if (n.length && !catalogOnPage) catalogOnPage = n;
        }
        NSString *number = text.length ? [AVDB115DetailPagePolicy catalogNumberInText:text] : nil;
        if (number.length == 0) return;
        // Combined labels like "title PBD-530" still count, but skip huge
        // containers that include many movies.
        CGRect acc = [el respondsToSelector:@selector(accessibilityFrame)] ? [el accessibilityFrame] : CGRectZero;
        CGRect nf = [self rectInWindow:window fromAccessibility:acc];
        if (CGRectIsEmpty(nf) || nf.size.width < 20 || nf.size.height < 8) return;
        if (nf.size.width > window.bounds.size.width * 0.7) return;
        if (nf.size.height > 220) return;
        if ([seenNumbers containsObject:number]) return;
        // Prefer the tighter frame if the same number appears twice; first
        // (usually the leaf label) wins because we skip after insert.
        [seenNumbers addObject:number];
        AVDB115HomeCoverHit *hit = [[AVDB115HomeCoverHit alloc] init];
        hit.number = number;
        hit.numberFrame = nf;
        [raw addObject:hit];
    };

    NSMutableSet *seen = [NSMutableSet set];
    for (UIView *v in [self flutterViewsInWindow:window]) {
        AVDB115HomeCoverVisitAcc(v, seen, consider);
    }
    if (raw.count == 0) {
        // Fallback: the window itself sometimes exposes the a11y tree.
        AVDB115HomeCoverVisitAcc(window, seen, consider);
    }

    BOOL onDetail = [AVDB115DetailPagePolicy looksLikeMovieDetailWithActionLabels:labels catalogNumber:catalogOnPage];
    if (onDetail) {
        self.container.hidden = YES;
        for (UIImageView *iv in self.views.allValues) iv.hidden = YES;
        return;
    }

    NSArray<AVDB115HomeCoverHit *> *hits = [self hitsFromNumberFrames:raw window:window sectionLikely:sectionLikely];
    if (hits.count == 0) {
        self.container.hidden = YES;
        for (UIImageView *iv in self.views.allValues) iv.hidden = YES;
        return;
    }

    [self ensureContainerInWindow:window];
    self.container.frame = window.bounds;
    self.container.hidden = NO;

    NSMutableSet<NSString *> *keep = [NSMutableSet set];
    for (AVDB115HomeCoverHit *hit in hits) {
        [keep addObject:hit.number];
        UIImageView *iv = self.views[hit.number];
        if (!iv) {
            iv = [[UIImageView alloc] init];
            iv.contentMode = UIViewContentModeScaleAspectFill;
            iv.clipsToBounds = YES;
            iv.layer.cornerRadius = 6;
            iv.userInteractionEnabled = NO;
            iv.backgroundColor = UIColor.clearColor;
            iv.accessibilityIdentifier = hit.number;
            [self.container addSubview:iv];
            self.views[hit.number] = iv;
        }
        iv.frame = hit.coverFrame;
        iv.hidden = NO;
        UIImage *cached = [self.images objectForKey:hit.number];
        if (cached) {
            iv.image = cached;
        } else {
            [self enqueueResolve:hit.number];
        }
    }
    NSArray *keys = self.views.allKeys;
    for (NSString *k in keys) {
        if ([keep containsObject:k]) continue;
        UIImageView *iv = self.views[k];
        [iv removeFromSuperview];
        [self.views removeObjectForKey:k];
    }
}

- (void)enqueueResolve:(NSString *)number {
    if (!number.length) return;
    if ([self.images objectForKey:number]) return;
    if ([self.inflight containsObject:number]) return;
    if ([self.pending containsObject:number]) return;
    [self.pending addObject:number];
    [self pumpQueue];
}

- (void)pumpQueue {
    while (self.inflight.count < kAVDB115HomeCoverMaxConcurrent && self.pending.count) {
        NSString *number = self.pending.firstObject;
        [self.pending removeObjectAtIndex:0];
        if ([self.images objectForKey:number] || [self.inflight containsObject:number]) continue;
        [self.inflight addObject:number];
        AVDB115CoverResolver *resolver = [[AVDB115CoverResolver alloc] init];
        self.resolvers[number] = resolver;
        __weak typeof(self) weakSelf = self;
        [resolver resolveNumber:number progress:nil completion:^(AVDB115CoverResolveResult *result, NSError *error) {
            (void)error;
            dispatch_async(dispatch_get_main_queue(), ^{
                AVDB115HomeCoverOverlay *s = weakSelf;
                [s.inflight removeObject:number];
                [s.resolvers removeObjectForKey:number];
                UIImage *img = nil;
                AVDB115CoverCandidate *best = nil;
                for (AVDB115CoverCandidate *c in result.candidates) {
                    if (!c.reachable || c.cachePath.length == 0) continue;
                    if (c.eligiblePortrait) { best = c; break; }
                    if (!best) best = c;
                }
                if (best.cachePath.length) img = [UIImage imageWithContentsOfFile:best.cachePath];
                if (img) {
                    [s.images setObject:img forKey:number];
                    UIImageView *iv = s.views[number];
                    if (iv) iv.image = img;
                }
                [s pumpQueue];
            });
        }];
    }
}

@end
