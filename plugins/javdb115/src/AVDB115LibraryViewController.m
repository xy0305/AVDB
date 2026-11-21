#import "AVDB115LibraryViewController.h"
#import "AVDB115ExternalLibrary.h"
#import "AVDB115Settings.h"
#import "AVDB115Client.h"
#import "AVDB115Link.h"
#import "AVDB115PlayerViewController.h"

@interface AVDB115LibraryViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong) UISwitch *enabledSwitch;
@property (nonatomic, strong) UITextField *urlField;
@property (nonatomic, strong) UITextField *tokenField;
@property (nonatomic, strong) UITextField *keywordField;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, copy) NSArray<AVDB115ExternalLink *> *links;
@end

@implementation AVDB115LibraryViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = @"外部数据库";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStylePlain target:self action:@selector(closePanel)];
    self.links = @[];

    UILabel *hint = [self caption:@"对接 AVDB 已公开的 External Library HTTP API（默认地址来自 AVDB 源码，默认关闭）。不是本地 JSON 文件导入。令牌只保存在本机钥匙串，不会写入公开仓库或日志。不会把 115 Cookie 发送到外部库。搜索需你自己的 API Token；无 Token 时不会发起请求。"];
    hint.numberOfLines = 0;

    self.enabledSwitch = [[UISwitch alloc] init];
    self.enabledSwitch.on = AVDB115ExternalLibrarySettings.shared.enabled;
    UILabel *enableLabel = [self caption:@"启用外部数据库"];
    UIStackView *enableRow = [[UIStackView alloc] initWithArrangedSubviews:@[enableLabel, self.enabledSwitch]];
    enableRow.axis = UILayoutConstraintAxisHorizontal;

    self.urlField = [self field:@"服务器根地址" text:AVDB115ExternalLibrarySettings.shared.baseURL];
    self.tokenField = [self field:@"API Token（保存后不再回显）" text:@""];
    self.tokenField.secureTextEntry = YES;
    if (@available(iOS 12.0, *)) self.tokenField.textContentType = UITextContentTypeNewPassword;
    self.keywordField = [self field:@"番号 / 关键字" text:@""];
    self.keywordField.delegate = self;
    self.keywordField.returnKeyType = UIReturnKeySearch;

    UIButton *save = [self button:@"保存设置" action:@selector(saveSettings)];
    UIButton *clear = [self button:@"清除令牌" action:@selector(clearToken)];
    UIButton *search = [self button:@"搜索" action:@selector(search)];

    self.statusLabel = [self caption:@""];
    self.statusLabel.numberOfLines = 0;
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.table registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        hint, enableRow,
        [self caption:@"服务器（仅根域名或 IP:端口）"], self.urlField,
        [self caption:AVDB115ExternalLibrarySettings.shared.hasToken ? @"令牌（已保存在钥匙串，留空则保留原令牌）" : @"令牌（X-API-Key）"],
        self.tokenField, save, clear,
        [self caption:@"搜索"], self.keywordField, search,
        self.spinner, self.statusLabel
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];
    [scroll addSubview:stack];
    [self.view addSubview:self.table];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-8],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32],
        [scroll.bottomAnchor constraintEqualToAnchor:self.table.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [self.table.heightAnchor constraintEqualToConstant:280],
    ]];
    [self refreshStatus:@"默认关闭。输入你自己的 Token 并保存后才能搜索。"];
}

- (UILabel *)caption:(NSString *)text {
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.font = [UIFont systemFontOfSize:13];
    l.textColor = UIColor.secondaryLabelColor;
    l.numberOfLines = 0;
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

- (void)refreshStatus:(NSString *)message {
    AVDB115ExternalLibrarySettings *s = AVDB115ExternalLibrarySettings.shared;
    NSString *tok = s.hasToken ? @"已保存令牌" : @"无令牌";
    NSString *en = s.enabled ? @"已启用" : @"未启用";
    self.statusLabel.text = [NSString stringWithFormat:@"%@ · %@\n%@", en, tok, message ?: @""];
}

- (void)saveSettings {
    NSError *error = nil;
    BOOL ok = [AVDB115ExternalLibrarySettings.shared saveBaseURL:self.urlField.text ?: @""
                                                         enabled:self.enabledSwitch.on
                                               replacementToken:self.tokenField.text ?: @""
                                                          error:&error];
    if (ok) {
        self.tokenField.text = @"";
        self.urlField.text = AVDB115ExternalLibrarySettings.shared.baseURL;
        [self refreshStatus:@"已保存。令牌不会出现在日志或 UserDefaults 里。"];
    } else {
        [self refreshStatus:error.localizedDescription ?: @"保存失败"];
    }
}

- (void)clearToken {
    NSError *error = nil;
    if ([AVDB115ExternalLibrarySettings.shared clearTokenWithError:&error]) {
        self.tokenField.text = @"";
        [self refreshStatus:@"已清除令牌"];
    } else {
        [self refreshStatus:error.localizedDescription ?: @"清除失败"];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self search];
    return YES;
}

- (void)search {
    [self.view endEditing:YES];
    [self saveSettings];
    AVDB115ExternalLibrarySettings *s = AVDB115ExternalLibrarySettings.shared;
    if (!s.enabled) { [self refreshStatus:@"请先启用外部数据库并保存"]; return; }
    if (!s.hasToken) { [self refreshStatus:@"未保存令牌，按 AVDB 逻辑不会发请求。请填写 Token。"]; return; }
    NSString *keyword = [self.keywordField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (keyword.length == 0) { [self refreshStatus:@"请填写番号"]; return; }
    [self.spinner startAnimating];
    [self refreshStatus:@"正在搜索…"];
    [AVDB115ExternalLibraryClient.shared fetchLinksForNumber:keyword completion:^(NSArray<AVDB115ExternalLink *> *links, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            if (error) {
                self.links = @[];
                [self.table reloadData];
                [self refreshStatus:error.localizedDescription];
                return;
            }
            self.links = links ?: @[];
            [self.table reloadData];
            [self refreshStatus:[NSString stringWithFormat:@"找到 %lu 条（仅展示接口返回的 download_url，不编造结果）", (unsigned long)self.links.count]];
        });
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.links.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    AVDB115ExternalLink *link = self.links[indexPath.row];
    NSMutableArray *bits = [NSMutableArray array];
    if (link.title.length) [bits addObject:link.title];
    if (link.sizeMB) [bits addObject:[NSString stringWithFormat:@"%.0f MB", link.sizeMB.doubleValue]];
    if (link.seeders) [bits addObject:[NSString stringWithFormat:@"%ld seeders", (long)link.seeders.integerValue]];
    if (link.chinese.boolValue) [bits addObject:@"中字"];
    if (link.uncensored.boolValue) [bits addObject:@"无码"];
    if (link.uhd.boolValue) [bits addObject:@"UHD"];
    NSString *kind = link.isMagnet ? @"magnet" : (link.isED2K ? @"ed2k" : @"链接");
    cell.textLabel.numberOfLines = 3;
    cell.textLabel.font = [UIFont systemFontOfSize:13];
    cell.textLabel.text = [NSString stringWithFormat:@"[%@] %@", kind, [bits componentsJoinedByString:@" · "]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    AVDB115ExternalLink *link = self.links[indexPath.row];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"外部库条目" message:link.title ?: link.downloadURL preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"复制链接" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        UIPasteboard.generalPasteboard.string = link.downloadURL;
        [self refreshStatus:@"已复制（不会自动上传到 115）"];
    }]];
    if (link.isMagnet || link.isED2K) {
        [alert addAction:[UIAlertAction actionWithTitle:@"推送到 115" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            [self pushLink:link play:NO];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"推送并播放" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            [self pushLink:link play:YES];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    alert.popoverPresentationController.sourceView = tableView;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)pushLink:(AVDB115ExternalLink *)link play:(BOOL)play {
    if (!AVDB115Settings.shared.isConfigured) {
        [self refreshStatus:AVDB115Settings.shared.missingHint];
        return;
    }
    NSString *resource = [AVDB115Link firstOfflineResourceIn:link.downloadURL] ?: ((link.isMagnet || link.isED2K) ? link.downloadURL : nil);
    if (resource.length == 0) {
        [self refreshStatus:@"该条目不是 magnet / ed2k，不会自动推送"];
        return;
    }
    if (play) {
        NSString *keyword = link.title.length ? link.title : (self.keywordField.text ?: @"");
        AVDB115PlayerViewController *player = [[AVDB115PlayerViewController alloc] initWithKeyword:keyword magnet:resource];
        [self presentViewController:player animated:YES completion:nil];
        return;
    }
    [self.spinner startAnimating];
    [AVDB115Client.shared addOfflineTask:resource cookie:AVDB115Settings.shared.cookie folderCID:AVDB115Settings.shared.folderCID completion:^(AVDB115PushResult *result, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            [self refreshStatus:error.localizedDescription ?: result.message];
        });
    }];
}


- (void)closePanel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
