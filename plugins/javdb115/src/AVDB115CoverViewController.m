#import "AVDB115CoverViewController.h"
#import "AVDB115CoverResolver.h"
#import "AVDB115PageCover.h"

@interface AVDB115CoverViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong) UITextField *keywordField;
@property (nonatomic, strong) UISwitch *dmmSwitch;
@property (nonatomic, strong) UISwitch *mgsSwitch;
@property (nonatomic, strong) UISwitch *avbaseSwitch;
@property (nonatomic, strong) UISwitch *javbusSwitch;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UITextView *notesView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) AVDB115CoverResolveResult *result;
@property (nonatomic, strong) UIButton *cancelButton;
@end

@implementation AVDB115CoverViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = @"高清封面源";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStylePlain target:self action:@selector(closePanel)];

    UILabel *hint = [self caption:@"按 AVDB 已实现的公开封面规则预览候选图：DMM（awsimgsrc / pics.dmm.co.jp）、MGS Prestige 模板。Avbase / JavBus 仅在页面可达且非验证码时解析；验证或封禁会跳过，不绕过。可选 TPDB（需自备 Bearer）本版未接入。插件面板可预览高清源。原页封面替换开关在主面板，默认开启；但 JavDB Flutter 原页当前无法被稳定替换，见主面板说明。"];
    hint.numberOfLines = 0;

    self.keywordField = [self field:@"番号，例如 SSIS-001" text:self.initialNumber ?: @""];
    self.keywordField.delegate = self;
    self.keywordField.returnKeyType = UIReturnKeySearch;
    self.keywordField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;

    self.dmmSwitch = [[UISwitch alloc] init]; self.dmmSwitch.on = YES;
    self.mgsSwitch = [[UISwitch alloc] init]; self.mgsSwitch.on = YES;
    self.avbaseSwitch = [[UISwitch alloc] init]; self.avbaseSwitch.on = YES;
    self.javbusSwitch = [[UISwitch alloc] init]; self.javbusSwitch.on = YES;

    UIButton *search = [self button:@"预览并缓存" action:@selector(resolve)];
    self.cancelButton = [self button:@"取消请求" action:@selector(cancelResolve)];
    UIButton *clear = [self button:@"清除封面缓存" action:@selector(clearCache)];

    self.statusLabel = [self caption:@"等待查询"];
    self.statusLabel.numberOfLines = 0;
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.notesView = [[UITextView alloc] init];
    self.notesView.editable = NO;
    self.notesView.scrollEnabled = YES;
    self.notesView.font = [UIFont systemFontOfSize:12];
    self.notesView.textColor = UIColor.secondaryLabelColor;
    self.notesView.backgroundColor = UIColor.clearColor;
    self.notesView.text = @"说明会显示在这里。";

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.rowHeight = 88;
    [self.table registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *sources = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self switchRow:@"DMM" sw:self.dmmSwitch],
        [self switchRow:@"MGS" sw:self.mgsSwitch],
        [self switchRow:@"Avbase" sw:self.avbaseSwitch],
        [self switchRow:@"JavBus" sw:self.javbusSwitch],
    ]];
    sources.axis = UILayoutConstraintAxisVertical;
    sources.spacing = 4;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        hint, self.keywordField, sources, search, self.cancelButton, clear,
        self.spinner, self.statusLabel, self.notesView
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
        [self.notesView.heightAnchor constraintEqualToConstant:90],
        [scroll.bottomAnchor constraintEqualToAnchor:self.table.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [self.table.heightAnchor constraintGreaterThanOrEqualToConstant:260],
    ]];
}

- (UIView *)switchRow:(NSString *)title sw:(UISwitch *)sw {
    UILabel *l = [self caption:title];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[l, sw]];
    row.axis = UILayoutConstraintAxisHorizontal;
    return row;
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

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self resolve];
    return YES;
}

- (void)applyResult:(AVDB115CoverResolveResult *)result busy:(BOOL)busy {
    self.result = result;
    self.notesView.text = [result.notes componentsJoinedByString:@"\n"] ?: @"";
    NSUInteger ok = 0, n = result.candidates.count;
    for (AVDB115CoverCandidate *c in result.candidates) if (c.reachable) ok += 1;
    self.statusLabel.text = busy
        ? [NSString stringWithFormat:@"查询中… 已确认 %lu / %lu，缓存 %lu 项", (unsigned long)ok, (unsigned long)n, (unsigned long)AVDB115CoverResolver.shared.cacheFileCount]
        : [NSString stringWithFormat:@"完成：可达 %lu / %lu。JavDB 原界面封面未被替换。", (unsigned long)ok, (unsigned long)n];
    [self.table reloadData];
}

- (void)resolve {
    [self.view endEditing:YES];
    AVDB115CoverResolver *r = AVDB115CoverResolver.shared;
    r.enableDMM = self.dmmSwitch.on;
    r.enableMGS = self.mgsSwitch.on;
    r.enableAvbase = self.avbaseSwitch.on;
    r.enableJavBus = self.javbusSwitch.on;
    [self.spinner startAnimating];
    self.statusLabel.text = @"正在按番号去重查询…";
    __weak typeof(self) weakSelf = self;
    [r resolveNumber:self.keywordField.text ?: @"" progress:^(AVDB115CoverResolveResult *partial) {
        [weakSelf applyResult:partial busy:YES];
    } completion:^(AVDB115CoverResolveResult *result, NSError *error) {
        [weakSelf.spinner stopAnimating];
        if (error) {
            weakSelf.statusLabel.text = error.localizedDescription;
            return;
        }
        [weakSelf applyResult:result busy:NO];
    }];
}

- (void)cancelResolve {
    [AVDB115CoverResolver.shared cancel];
    [self.spinner stopAnimating];
    self.statusLabel.text = @"已取消";
}

- (void)clearCache {
    [AVDB115CoverResolver.shared clearCache];
    self.statusLabel.text = @"已清除封面缓存";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.result.candidates.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    if (cell.imageView.tag != 115) {
        // Keep a predictable layout for reused cells.
        cell.imageView.tag = 115;
    }
    AVDB115CoverCandidate *item = self.result.candidates[indexPath.row];
    NSString *state = item.probed ? (item.message ?: @"") : @"等待探测";
    cell.textLabel.numberOfLines = 4;
    cell.textLabel.font = [UIFont systemFontOfSize:12];
    cell.textLabel.text = [NSString stringWithFormat:@"[%@] %@\n%@", item.source, state, item.url];
    UIImage *img = nil;
    if (item.cachePath.length) img = [UIImage imageWithContentsOfFile:item.cachePath];
    cell.imageView.image = img ?: [self placeholder];
    cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
    return cell;
}

- (UIImage *)placeholder {
    static UIImage *img;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(54, 76), YES, 0);
        [[UIColor secondarySystemFillColor] setFill];
        UIRectFill(CGRectMake(0, 0, 54, 76));
        img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    });
    return img;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    AVDB115CoverCandidate *item = self.result.candidates[indexPath.row];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:item.source message:item.url preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"复制图片 URL" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        UIPasteboard.generalPasteboard.string = item.url;
        self.statusLabel.text = @"已复制封面 URL";
    }]];
    if (item.cachePath.length) {
        [alert addAction:[UIAlertAction actionWithTitle:@"查看缓存图" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            UIImage *img = [UIImage imageWithContentsOfFile:item.cachePath];
            if (!img) return;
            UIViewController *vc = [[UIViewController alloc] init];
            vc.view.backgroundColor = UIColor.blackColor;
            UIImageView *iv = [[UIImageView alloc] initWithImage:img];
            iv.contentMode = UIViewContentModeScaleAspectFit;
            iv.frame = vc.view.bounds;
            iv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [vc.view addSubview:iv];
            [self presentViewController:vc animated:YES completion:nil];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    alert.popoverPresentationController.sourceView = tableView;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)dealloc {
    [AVDB115CoverResolver.shared cancel];
}


- (void)closePanel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
