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

@interface QARControl : NSObject
@property(nonatomic,weak) UIViewController *settingsPresenter;
- (void)showPanel;
@end
@implementation QARControl
- (UIViewController *)presenter {
    UIViewController *controller = self.settingsPresenter;
    while (controller) {
        if (controller.presentedViewController) controller = controller.presentedViewController;
        else if ([controller isKindOfClass:UINavigationController.class])
            controller = ((UINavigationController *)controller).visibleViewController;
        else if ([controller isKindOfClass:UITabBarController.class])
            controller = ((UITabBarController *)controller).selectedViewController;
        else break;
    }
    return controller;
}
- (void)showPanel {
    UIViewController *presenter = [self presenter];
    if (!presenter || [presenter isKindOfClass:UIAlertController.class]) return;
    NSDictionary *status = controlStatus();
    NSString *message = [NSString stringWithFormat:
        @"插件 %@\nQQ %@\n已加载接口：%@\n本次保存：%@ · 历史恢复：%@\n\n已保留的撤回消息下方显示精美标识。打开闪照后保留本机副本，在对应聊天消息下方点击“闪照 · 再次查看”，最多 100 张 / 128 MB。闪照保留使用独立开关。\n开启后会在本机保存消息副本，按账号隔离，最多 512 条 / 16 MB；不上传，诊断不含消息内容。旧版没有保存的消息无法补回。",
        status[@"plugin_version"], status[@"build_version"], status[@"installed_hooks"],
        status[@"message_store"][@"snapshots_saved"], status[@"message_store"][@"history_records_restored"]];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"QQ 防撤回 · 实验版"
        message:message preferredStyle:UIAlertControllerStyleAlert];
    if ([status[@"installed_hooks"] unsignedIntegerValue] > 0) {
        [alert addAction:[UIAlertAction actionWithTitle:QAREnabled() ? @"关闭防撤回" : @"开启防撤回"
            style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                QARSetEnabled(!QAREnabled());
            }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:QARFlashEnabled() ? @"关闭闪照保留" : @"开启闪照保留"
        style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            QARSetFlashEnabled(!QARFlashEnabled());
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清除当前账号的闪照" style:UIAlertActionStyleDestructive
        handler:^(__unused UIAlertAction *action) { QARClearFlash(); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"自定义设备名" style:UIAlertActionStyleDefault
        handler:^(__unused UIAlertAction *action) {
            dispatch_async(dispatch_get_main_queue(), ^{ QARPresentDeviceNameEditor([self presenter]); });
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清零并开始测试" style:UIAlertActionStyleDefault
        handler:^(__unused UIAlertAction *action) { QARResetDiagnostics(); QARResetBadgeCounters(); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清除当前账号的消息备份" style:UIAlertActionStyleDestructive
        handler:^(__unused UIAlertAction *action) { QARClearSavedMessages(); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"导出诊断" style:UIAlertActionStyleDefault
        handler:^(__unused UIAlertAction *action) {
            NSData *data = [NSJSONSerialization dataWithJSONObject:controlStatus()
                           options:NSJSONWritingPrettyPrinted error:nil];
            if (!data) return;
            NSURL *file = [NSURL fileURLWithPath:[NSTemporaryDirectory()
                          stringByAppendingPathComponent:@"QQAntiRecall-diagnostics.json"]];
            if (![data writeToURL:file options:NSDataWritingAtomic error:nil]) return;
            UIActivityViewController *share = [[UIActivityViewController alloc]
                initWithActivityItems:@[file] applicationActivities:nil];
            share.popoverPresentationController.sourceView = presenter.view;
            share.popoverPresentationController.sourceRect = CGRectMake(presenter.view.bounds.size.width / 2, presenter.view.bounds.size.height / 2, 1, 1);
            dispatch_async(dispatch_get_main_queue(), ^{
                [[self presenter] presentViewController:share animated:YES completion:nil];
            });
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭面板" style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}
@end

static QARControl *control;
void QAROpenSettingsPanel(UIViewController *presenter) {
    if (!control) control = [QARControl new];
    control.settingsPresenter = presenter; [control showPanel];
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
