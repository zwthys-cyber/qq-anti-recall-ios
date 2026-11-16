#import <UIKit/UIKit.h>
#import "QARAdapter.h"
#import "QARStore.h"
#import "QARBadge.h"
#import "QARFlash.h"
#import "QARSettings.h"
#import "QARDeviceDiagnostics.h"
#import "QARDeviceName.h"

static NSDictionary *controlStatus(void) {
    NSMutableDictionary *status = [QARStatus() mutableCopy];
    NSDictionary *badge = QARBadgeStatus();
    status[@"recall_badge"] = badge;
    status[@"flash_retention"] = QARFlashStatus();
    status[@"settings_entry"] = QARSettingsStatus();
    status[@"device_name_integration"] = QARDeviceDiagnosticsStatus();
    status[@"installed_hooks"] = @([status[@"installed_hooks"] unsignedIntegerValue] + [badge[@"installed_hooks"] unsignedIntegerValue]);
    NSMutableDictionary *hooks = [status[@"hook_results"] mutableCopy];
    [hooks addEntriesFromDictionary:badge[@"hook_results"]];
    status[@"hook_results"] = hooks;
    return status;
}


@interface QARPreferencesController : UITableViewController
@property(nonatomic,strong) NSDictionary *snapshot;
@end
@implementation QARPreferencesController
- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) self.title = @"QQ 增强";
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.tintColor = UIColor.systemTealColor;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
    self.tableView.accessibilityIdentifier = @"qar.settings";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        target:self action:@selector(close)];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated]; [self reloadStatus];
}
- (void)reloadStatus {
    self.snapshot = controlStatus(); [self.tableView reloadData];
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { (void)table; return 4; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    (void)table; return section == 0 ? 3 : 2;
}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    (void)table; return @[@"聊天与个性化", @"本机存储", @"诊断与支持", @"关于"][section];
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    (void)table;
    return @[
        @"闪照正常打开后，可在原消息下方再次查看。自定义机型需在 QQ 官方页面点击保存。",
        @"副本按账号隔离，仅保存在本机。关闭功能不会删除已有副本；清理后无法恢复。消息最多 512 条 / 16 MiB，闪照最多 100 张 / 128 MiB。",
        @"诊断包含功能计数和错误码，不包含聊天正文、图片、账号或填写的机型。",
        @"独立实验项目，与腾讯无隶属关系。仅适配 QQ 9.3.86（9.3.86.617）。"
    ][section];
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"preference"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"preference"];
    NSArray *titles = @[@[@"消息防撤回", @"闪照保留", @"自定义机型"],
        @[@"清理消息副本", @"清理闪照副本"], @[@"导出诊断", @"重置诊断计数"], @[@"插件版本", @"适配版本"]];
    NSArray *symbols = @[@[@"arrow.uturn.backward.circle", @"photo.on.rectangle", @"iphone"],
        @[@"tray", @"photo"], @[@"square.and.arrow.up", @"arrow.counterclockwise"], @[@"shippingbox", @"checkmark.shield"]];
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = titles[path.section][path.row];
    content.image = [UIImage systemImageNamed:symbols[path.section][path.row]];
    content.imageProperties.tintColor = path.section == 1 ? UIColor.secondaryLabelColor : UIColor.systemTealColor;
    content.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    content.secondaryTextProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    content.textProperties.numberOfLines = 0; content.secondaryTextProperties.numberOfLines = 0;
    cell.accessoryView = nil; cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    if (path.section == 0 && path.row < 2) {
        UISwitch *toggle = [UISwitch new]; toggle.tag = path.row;
        toggle.onTintColor = UIColor.systemTealColor;
        toggle.on = path.row == 0 ? QAREnabled() : QARFlashEnabled();
        toggle.accessibilityLabel = content.text;
        toggle.accessibilityIdentifier = path.row == 0 ? @"qar.recall.toggle" : @"qar.flash.toggle";
        [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle; cell.selectionStyle = UITableViewCellSelectionStyleNone;
        content.secondaryText = path.row == 0 ? @"保留已接收消息，显示撤回标识" : @"打开后保留，在聊天中重复查看";
    } else if (path.section == 0) {
        content.secondaryText = @"替换机型本身，不添加文字前缀";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (path.section == 1) {
        content.secondaryText = path.row == 0 ? @"删除当前账号的已保存消息" :
            [NSString stringWithFormat:@"当前账号已保存 %@ 张", self.snapshot[@"flash_retention"][@"saved_images_current_account"] ?: @0];
    } else if (path.section == 2) {
        content.secondaryText = path.row == 0 ? @"分享排查所需的诊断文件" : @"开始新的观察，不删除消息";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        content.secondaryText = path.row == 0 ? self.snapshot[@"plugin_version"] : @"QQ 9.3.86 · 9.3.86.617";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    cell.contentConfiguration = content;
    cell.accessibilityIdentifier = [NSString stringWithFormat:@"qar.settings.%ld.%ld", (long)path.section, (long)path.row];
    return cell;
}
- (void)toggleChanged:(UISwitch *)sender {
    if (sender.tag == 0) QARSetEnabled(sender.on); else QARSetFlashEnabled(sender.on);
}
- (void)confirmClear:(BOOL)flash {
    NSString *owner = QARCurrentOwner();
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:flash ? @"清理闪照副本？" : @"清理消息副本？"
        message:@"仅删除当前账号在插件中保存的副本。此操作无法撤销。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清理" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        if (!owner || ![owner isEqual:QARCurrentOwner()]) return;
        if (flash) QARClearFlash(); else QARClearSavedMessages();
        [self reloadStatus];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)exportDiagnostics:(NSIndexPath *)path {
    NSData *data = [NSJSONSerialization dataWithJSONObject:controlStatus() options:NSJSONWritingPrettyPrinted error:nil];
    NSURL *file = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"QQAntiRecall-diagnostics.json"]];
    if (!data || ![data writeToURL:file options:NSDataWritingAtomic error:nil]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"暂时无法导出"
            message:@"请稍后重试。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil]; return;
    }
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[file] applicationActivities:nil];
    share.popoverPresentationController.sourceView = self.tableView;
    share.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:path];
    [self presentViewController:share animated:YES completion:nil];
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section == 0 && path.row == 2) QARPresentDeviceNameEditor(self);
    else if (path.section == 1) [self confirmClear:path.row == 1];
    else if (path.section == 2 && path.row == 0) [self exportDiagnostics:path];
    else if (path.section == 2) {
        QARResetDiagnostics(); QARResetBadgeCounters(); [self reloadStatus];
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, @"诊断计数已重置");
    }
}
@end
void QAROpenSettingsPanel(UIViewController *presenter) {
    if (!NSThread.isMainThread || !presenter || presenter.presentedViewController) return;
    QARPreferencesController *settings = [QARPreferencesController new];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:settings];
    navigation.navigationBar.prefersLargeTitles = YES;
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    [presenter presentViewController:navigation animated:YES completion:nil];
}
static void installAll(void) {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    QARInstallAdapters(info); QARInstallBadge(info); QARInstallFlash(info); QARInstallSettings(info); QARInstallDeviceDiagnostics(info);
}
__attribute__((constructor)) static void QARStart(void) {
    @autoreleasepool {
        if (!QARVersionSupported(NSBundle.mainBundle.infoDictionary)) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            installAll();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ installAll(); });
        });
    }
}
