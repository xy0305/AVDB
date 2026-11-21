#import "AVDB115PlayerViewController.h"
#import "AVDB115Settings.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

@interface AVDB115PlayerViewController ()
@property (nonatomic, copy) NSString *keyword;
@property (nonatomic, copy, nullable) NSString *magnet;
@property (nonatomic, strong, nullable) AVDB115FileItem *file;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *qualityButton;
@property (nonatomic, strong) AVPlayerViewController *playerVC;
@property (nonatomic, copy) NSArray<AVDB115PlayStream *> *streams;
@property (nonatomic, strong, nullable) AVDB115PlayStream *active;
@property (nonatomic, assign) BOOL triedOriginal;
@property (nonatomic, assign) BOOL triedHLS;
@end

@implementation AVDB115PlayerViewController

- (instancetype)initWithKeyword:(NSString *)keyword magnet:(NSString *)magnet {
    if (self = [super init]) {
        _keyword = [keyword copy] ?: @"";
        _magnet = [magnet copy];
        self.modalPresentationStyle = UIModalPresentationFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    }
    return self;
}

- (instancetype)initWithFile:(AVDB115FileItem *)file {
    if (self = [self initWithKeyword:file.name magnet:nil]) {
        _file = file;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;

    _statusLabel = [[UILabel alloc] init];
    _statusLabel.textColor = UIColor.whiteColor;
    _statusLabel.font = [UIFont systemFontOfSize:15];
    _statusLabel.numberOfLines = 0;
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_statusLabel];

    _closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_closeButton setTitle:@"关闭" forState:UIControlStateNormal];
    [_closeButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_closeButton addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_closeButton];

    _qualityButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_qualityButton setTitle:@"画质" forState:UIControlStateNormal];
    [_qualityButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _qualityButton.translatesAutoresizingMaskIntoConstraints = NO;
    _qualityButton.hidden = YES;
    [_qualityButton addTarget:self action:@selector(pickQuality) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_qualityButton];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_closeButton.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [_closeButton.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [_qualityButton.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [_qualityButton.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [_statusLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_statusLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_statusLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24],
        [_statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-24],
    ]];

    [self start];
}

- (void)setStatus:(NSString *)text {
    self.statusLabel.hidden = NO;
    self.statusLabel.text = text;
}

- (void)close {
    [self.playerVC.player pause];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)start {
    AVDB115Settings *settings = AVDB115Settings.shared;
    if (!settings.isConfigured) {
        [self setStatus:settings.missingHint];
        return;
    }
    if (self.file) {
        [self playFile:self.file];
        return;
    }
    NSString *keyword = self.keyword.length ? self.keyword : (self.magnet ?: @"");
    [self setStatus:[NSString stringWithFormat:@"正在 115 中搜索 %@…", keyword]];
    __weak typeof(self) weakSelf = self;
    [AVDB115Client.shared findMatchedVideos:keyword cookie:settings.cookie limit:100 completion:^(NSArray<AVDB115FileItem *> *files, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (files.count) {
            [self playFile:files.firstObject];
            return;
        }
        if (self.magnet.length == 0) {
            [self setStatus:error.localizedDescription ?: @"网盘没有匹配文件，也没有可推送的磁力/ed2k"];
            return;
        }
        [self setStatus:@"正在推送到 115 离线…"];
        [AVDB115Client.shared addOfflineTask:self.magnet cookie:settings.cookie folderCID:settings.folderCID completion:^(AVDB115PushResult *result, NSError *pushErr) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            if (pushErr) { [self setStatus:pushErr.localizedDescription]; return; }
            if (result.status == AVDB115PushStatusFailed) { [self setStatus:result.message]; return; }
            [self setStatus:result.status == AVDB115PushStatusExists ? @"任务已存在，正在打开已下载文件…" : @"已推送，等待离线完成…"];
            NSTimeInterval timeout = result.status == AVDB115PushStatusExists ? 45 : 90;
            [AVDB115Client.shared waitOfflineReady:keyword cookie:settings.cookie timeout:timeout completion:^(AVDB115OfflineTask *task, NSError *waitErr) {
                __strong typeof(weakSelf) self = weakSelf;
                if (!self) return;
                if (waitErr) { [self setStatus:waitErr.localizedDescription]; return; }
                (void)task;
                [AVDB115Client.shared findMatchedVideo:keyword cookie:settings.cookie folderCID:settings.folderCID requireMatch:YES completion:^(AVDB115FileItem *file, NSError *findErr) {
                    __strong typeof(weakSelf) self = weakSelf;
                    if (!self) return;
                    if (!file) { [self setStatus:findErr.localizedDescription ?: @"离线完成但没找到视频"]; return; }
                    [self playFile:file];
                }];
            }];
        }];
    }];
}

- (void)playFile:(AVDB115FileItem *)file {
    self.file = file;
    [self setStatus:[NSString stringWithFormat:@"正在获取播放地址：%@", file.name]];
    self.triedOriginal = YES;
    __weak typeof(self) weakSelf = self;
    [AVDB115Client.shared originalStream:file.pickCode cookie:AVDB115Settings.shared.cookie completion:^(AVDB115PlayStream *stream, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (stream) {
            [self loadStreamsThenActivate:stream];
            return;
        }
        (void)error;
        [self fallbackHLS];
    }];
}

- (void)loadStreamsThenActivate:(AVDB115PlayStream *)original {
    __weak typeof(self) weakSelf = self;
    [AVDB115Client.shared streamsForVideo:self.file.pickCode cookie:AVDB115Settings.shared.cookie completion:^(NSArray<AVDB115PlayStream *> *streams, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        (void)error;
        NSMutableArray *all = [NSMutableArray array];
        if (original) [all addObject:original];
        [all addObjectsFromArray:streams ?: @[]];
        self.streams = all;
        self.qualityButton.hidden = all.count <= 1;
        [self activate:original];
    }];
}

- (void)fallbackHLS {
    if (self.triedHLS || !self.file) {
        [self setStatus:@"无法获取 115 播放地址。原文件可能需要 KSPlayer/MPVKit，本插件这一版使用 AVPlayer。"];
        return;
    }
    self.triedHLS = YES;
    [self setStatus:@"原文件不可用，回退 HLS 转码…"];
    __weak typeof(self) weakSelf = self;
    [AVDB115Client.shared streamsForVideo:self.file.pickCode cookie:AVDB115Settings.shared.cookie completion:^(NSArray<AVDB115PlayStream *> *streams, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (streams.count == 0) {
            [self setStatus:error.localizedDescription ?: @"无法获取 115 HLS 地址"];
            return;
        }
        self.streams = streams;
        self.qualityButton.hidden = streams.count <= 1;
        [self activate:streams.firstObject];
    }];
}

- (void)activate:(AVDB115PlayStream *)stream {
    self.active = stream;
    NSURL *url = [NSURL URLWithString:stream.url];
    if (!url) { [self setStatus:@"播放地址无效"]; return; }
    NSDictionary *headers = stream.headers.count ? stream.headers : [AVDB115Client playHeadersWithCookie:AVDB115Settings.shared.cookie];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:@{@"AVURLAssetHTTPHeaderFieldsKey": headers}];
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
    if (!self.playerVC) {
        self.playerVC = [[AVPlayerViewController alloc] init];
        self.playerVC.view.translatesAutoresizingMaskIntoConstraints = NO;
        [self addChildViewController:self.playerVC];
        [self.view insertSubview:self.playerVC.view atIndex:0];
        UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
        [NSLayoutConstraint activateConstraints:@[
            [self.playerVC.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [self.playerVC.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [self.playerVC.view.topAnchor constraintEqualToAnchor:safe.topAnchor constant:44],
            [self.playerVC.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        ]];
        [self.playerVC didMoveToParentViewController:self];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemFailed:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:nil];
    }
    self.statusLabel.hidden = YES;
    self.playerVC.player = [AVPlayer playerWithPlayerItem:item];
    [self.playerVC.player play];
}

- (void)itemFailed:(NSNotification *)note {
    if (note.object != self.playerVC.player.currentItem) return;
    if (self.active.isOriginal && !self.triedHLS) {
        [self fallbackHLS];
    }
}

- (void)pickQuality {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"播放源" message:@"HDR/编码支持依设备。AVPlayer 不兼容时可改选 HLS。" preferredStyle:UIAlertControllerStyleActionSheet];
    for (AVDB115PlayStream *stream in self.streams) {
        NSString *title = [((self.active == stream || [self.active.name isEqualToString:stream.name]) ? @"✓ 正在播放 · " : @"") stringByAppendingString:stream.name];
        __weak typeof(self) weakSelf = self;
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [weakSelf activate:stream];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    alert.popoverPresentationController.sourceView = self.qualityButton;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
