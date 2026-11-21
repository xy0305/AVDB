#import "AVDB115OverlayController.h"
#import "AVDB115Settings.h"
#import "AVDB115Client.h"
#import "AVDB115Link.h"
#import "AVDB115PlayerViewController.h"
#import "AVDB115LibraryViewController.h"
#import "AVDB115CoverViewController.h"
#import <objc/runtime.h>

static const void *kButtonKey = &kButtonKey;

@interface AVDB115OverlayController ()
@property (nonatomic, strong) UITextView *cookieView;
@property (nonatomic, strong) UITextField *cidField;
@property (nonatomic, strong) UITextField *linkField;
@property (nonatomic, strong) UITextField *keywordField;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation AVDB115OverlayController

+ (UIWindow *)keyWindow {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        if (ws.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *w in ws.windows) {
            if (w.isKeyWindow) return w;
        }
        if (ws.windows.count) return ws.windows.firstObject;
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

+ (UIViewController *)topViewController {
    UIViewController *vc = [self keyWindow].rootViewController;
    while (YES) {
        if (vc.presentedViewController) vc = vc.presentedViewController;
        else if ([vc isKindOfClass:[UINavigationController class]]) {
            UIViewController *top = ((UINavigationController *)vc).topViewController;
            if (top) vc = top; else break;
        } else if ([vc isKindOfClass:[UITabBarController class]]) {
            UIViewController *sel = ((UITabBarController *)vc).selectedViewController;
            if (sel) vc = sel; else break;
        } else {
            break;
        }
    }
    return vc;
}

+ (BOOL)shouldSkipWindow:(UIWindow *)window {
    if (!window) return YES;
    if (window.windowLevel > UIWindowLevelNormal) return YES;
    NSString *name = NSStringFromClass(window.class);
    if ([name containsString:@"Keyboard"] || [name containsString:@"TextEffects"] || [name containsString:@"RemoteKeyboard"] || [name containsString:@"UIRemote"]) {
        return YES;
    }
    return NO;
}

+ (void)startWindowWatcher {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void (^attach)(NSNotification *) = ^(__unused NSNotification *note) {
            [AVDB115OverlayController attachToKeyWindowIfNeeded];
        };
        NSNotificationCenter *c = NSNotificationCenter.defaultCenter;
        [c addObserverForName:UIWindowDidBecomeKeyNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:attach];
        [c addObserverForName:UIWindowDidBecomeVisibleNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:attach];
        if (@available(iOS 13.0, *)) {
            [c addObserverForName:UISceneDidActivateNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:attach];
        }
        // Flutter often creates the real key window after didFinishLaunching.
        __block NSInteger tries = 0;
        __block void (^tick)(void);
        tick = ^{
            [AVDB115OverlayController attachToKeyWindowIfNeeded];
            tries += 1;
            if (tries < 20) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), tick);
            }
        };
        dispatch_async(dispatch_get_main_queue(), tick);
    });
}

+ (void)attachToKeyWindowIfNeeded {
    UIWindow *window = [self keyWindow];
    if ([self shouldSkipWindow:window]) return;
    if (objc_getAssociatedObject(window, kButtonKey)) return;
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = CGRectMake(window.bounds.size.width - 72, window.bounds.size.height - 140, 52, 52);
    btn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
    btn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.72];
    btn.layer.cornerRadius = 26;
    btn.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
    btn.layer.borderWidth = 1;
    [btn setTitle:@"115" forState:UIControlStateNormal];
    [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    btn.accessibilityLabel = @"115 离线推送与播放";
    [btn addTarget:self action:@selector(presentFromTop) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [btn addGestureRecognizer:pan];
    [window addSubview:btn];
    objc_setAssociatedObject(window, kButtonKey, btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *btn = pan.view;
    UIView *superview = btn.superview;
    CGPoint t = [pan translationInView:superview];
    [pan setTranslation:CGPointZero inView:superview];
    CGPoint c = CGPointMake(btn.center.x + t.x, btn.center.y + t.y);
    CGFloat m = 26;
    c.x = MIN(MAX(m, c.x), superview.bounds.size.width - m);
    c.y = MIN(MAX(m, c.y), superview.bounds.size.height - m);
    btn.center = c;
}

+ (void)presentFromTop {
    UIViewController *top = [self topViewController];
    if (!top || [top isKindOfClass:[AVDB115OverlayController class]]) return;
    AVDB115OverlayController *vc = [[AVDB115OverlayController alloc] init];
    vc.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        vc.sheetPresentationController.detents = @[
            [UISheetPresentationControllerDetent mediumDetent],
            [UISheetPresentationControllerDetent largeDetent]
        ];
    }
    [top presentViewController:vc animated:YES completion:nil];
}

+ (void)promptForLink:(NSString *)link {
    UIViewController *top = [self topViewController];
    if (!top) return;
    NSString *msg = link.length > 160 ? [[link substringToIndex:160] stringByAppendingString:@"…"] : link;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"推送到 115？" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"仅推送" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        [self presentFromTop];
        // Fill after a short delay so the panel exists.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIViewController *panel = [self topViewController];
            if ([panel isKindOfClass:[AVDB115OverlayController class]]) {
                [((AVDB115OverlayController *)panel) applyIncomingLink:link andPush:YES play:NO];
            }
        });
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"推送并播放" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        AVDB115PlayerViewController *player = [[AVDB115PlayerViewController alloc] initWithKeyword:[AVDB115Link displayNameFromLink:link] ?: @"" magnet:link];
        [top presentViewController:player animated:YES completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"忽略" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:alert animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = @"AVDB 插件";

    UILabel *hint = [self caption:@"115 推送与播放、外部数据库搜索、高清封面预览都在这个浮钮面板里。不会改 JavDB 原界面，不绕过 JavDB 会员，不替换原首页封面。115 Cookie 与外部库 Token 只存在本机钥匙串，不会互相发送。"];
    hint.numberOfLines = 0;

    self.cookieView = [[UITextView alloc] init];
    self.cookieView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.cookieView.layer.borderColor = UIColor.separatorColor.CGColor;
    self.cookieView.layer.borderWidth = 1;
    self.cookieView.layer.cornerRadius = 8;
    self.cookieView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.cookieView.autocorrectionType = UITextAutocorrectionTypeNo;
    self.cookieView.spellCheckingType = UITextSpellCheckingTypeNo;
    self.cookieView.smartQuotesType = UITextSmartQuotesTypeNo;
    self.cookieView.dataDetectorTypes = UIDataDetectorTypeNone;
    self.cookieView.secureTextEntry = YES;
    if (@available(iOS 12.0, *)) {
        self.cookieView.textContentType = UITextContentTypeNewPassword;
    }
    self.cookieView.text = AVDB115Settings.shared.cookie;

    self.cidField = [self field:@"离线目录 CID" text:AVDB115Settings.shared.folderCID];
    self.linkField = [self field:@"磁力 / ed2k（可从剪贴板粘贴）" text:@""];
    self.keywordField = [self field:@"番号（搜索已下载文件并播放）" text:@""];

    NSString *found = [AVDB115Link firstOfflineResourceIn:UIPasteboard.generalPasteboard.string];
    if (found) self.linkField.text = found;

    UIButton *save = [self button:@"保存配置" action:@selector(saveSettings)];
    UIButton *paste = [self button:@"使用剪贴板链接" action:@selector(pasteLink)];
    UIButton *push = [self button:@"推送到 115" action:@selector(pushOnly)];
    UIButton *play = [self button:@"推送并播放" action:@selector(pushAndPlay)];
    UIButton *search = [self button:@"按番号搜索播放" action:@selector(searchPlay)];
    UIButton *library = [self button:@"外部数据库" action:@selector(openLibrary)];
    UIButton *covers = [self button:@"高清封面源" action:@selector(openCovers)];

    self.statusLabel = [self caption:@""];
    self.statusLabel.numberOfLines = 0;
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        hint,
        [self caption:@"Cookie（需含 UID / CID / SEID）"],
        self.cookieView,
        [self caption:@"离线目录 CID"],
        self.cidField,
        save,
        [self caption:@"资源"],
        self.linkField,
        paste, push, play,
        [self caption:@"已在网盘中的文件"],
        self.keywordField,
        search,
        [self caption:@"扩展（不改 JavDB 原界面）"],
        library,
        covers,
        self.spinner,
        self.statusLabel
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];
    [scroll addSubview:stack];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-20],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32],
        [self.cookieView.heightAnchor constraintEqualToConstant:120],
    ]];
}

- (UILabel *)caption:(NSString *)text {
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.font = [UIFont systemFontOfSize:13];
    l.textColor = UIColor.secondaryLabelColor;
    return l;
}

- (UITextField *)field:(NSString *)placeholder text:(NSString *)text {
    UITextField *f = [[UITextField alloc] init];
    f.placeholder = placeholder;
    f.text = text;
    f.borderStyle = UITextBorderStyleRoundedRect;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    return f;
}

- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)setBusy:(BOOL)busy message:(NSString *)message {
    self.statusLabel.text = message ?: @"";
    if (busy) [self.spinner startAnimating];
    else [self.spinner stopAnimating];
}

- (void)saveSettings {
    AVDB115Settings.shared.cookie = self.cookieView.text ?: @"";
    AVDB115Settings.shared.folderCID = self.cidField.text ?: @"";
    [self setBusy:NO message:AVDB115Settings.shared.isConfigured ? @"已保存" : AVDB115Settings.shared.missingHint];
}

- (void)pasteLink {
    NSString *found = [AVDB115Link firstOfflineResourceIn:UIPasteboard.generalPasteboard.string];
    if (found) {
        self.linkField.text = found;
        [self setBusy:NO message:@"已填入剪贴板中的磁力/ed2k"];
    } else {
        [self setBusy:NO message:@"剪贴板里没有 magnet / ed2k"];
    }
}

- (void)applyIncomingLink:(NSString *)link andPush:(BOOL)push play:(BOOL)play {
    self.linkField.text = link;
    if (play) [self pushAndPlay];
    else if (push) [self pushOnly];
}

- (NSString *)currentLink {
    NSString *text = self.linkField.text;
    NSString *found = [AVDB115Link firstOfflineResourceIn:text];
    return found ?: @"";
}

- (void)pushOnly {
    [self saveSettings];
    if (!AVDB115Settings.shared.isConfigured) { [self setBusy:NO message:AVDB115Settings.shared.missingHint]; return; }
    NSString *link = [self currentLink];
    if (link.length == 0) { [self setBusy:NO message:@"请先提供有效的 magnet / ed2k"]; return; }
    [self setBusy:YES message:@"正在推送到 115…"];
    [AVDB115Client.shared addOfflineTask:link cookie:AVDB115Settings.shared.cookie folderCID:AVDB115Settings.shared.folderCID completion:^(AVDB115PushResult *result, NSError *error) {
        [self setBusy:NO message:error.localizedDescription ?: result.message];
    }];
}

- (void)pushAndPlay {
    [self saveSettings];
    if (!AVDB115Settings.shared.isConfigured) { [self setBusy:NO message:AVDB115Settings.shared.missingHint]; return; }
    NSString *link = [self currentLink];
    if (link.length == 0) { [self setBusy:NO message:@"请先提供有效的 magnet / ed2k"]; return; }
    NSString *keyword = self.keywordField.text.length ? self.keywordField.text : ([AVDB115Link displayNameFromLink:link] ?: [AVDB115Link infoHashFromMagnet:link] ?: link);
    AVDB115PlayerViewController *player = [[AVDB115PlayerViewController alloc] initWithKeyword:keyword magnet:link];
    [self presentViewController:player animated:YES completion:nil];
}

- (void)searchPlay {
    [self saveSettings];
    if (!AVDB115Settings.shared.isConfigured) { [self setBusy:NO message:AVDB115Settings.shared.missingHint]; return; }
    NSString *keyword = [self.keywordField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (keyword.length == 0) { [self setBusy:NO message:@"请填写番号"]; return; }
    AVDB115PlayerViewController *player = [[AVDB115PlayerViewController alloc] initWithKeyword:keyword magnet:nil];
    [self presentViewController:player animated:YES completion:nil];
}


- (void)openLibrary {
    AVDB115LibraryViewController *vc = [[AVDB115LibraryViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)openCovers {
    AVDB115CoverViewController *vc = [[AVDB115CoverViewController alloc] init];
    vc.initialNumber = [self.keywordField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

@end
