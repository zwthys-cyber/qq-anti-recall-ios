#import <UIKit/UIKit.h>
#import "QARAdapter.h"

@interface QARControl : NSObject
@property(nonatomic,strong) UIButton *button;
@property(nonatomic,weak) UIWindow *host;
- (void)attach;
- (void)applicationActive:(NSNotification *)notification;
@end
@implementation QARControl
- (void)applicationActive:(NSNotification *)notification { (void)notification; [self attach]; }
- (UIWindow *)activeWindow {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows)
            if (window.isKeyWindow) return window;
    }
    return nil;
}
- (void)attach {
    UIWindow *window = [self activeWindow];
    if (!window) return;
    if (!self.button) {
        self.button = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.button setTitle:@"防撤回" forState:UIControlStateNormal];
        self.button.accessibilityLabel = @"QQ 防撤回实验版设置";
        self.button.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.9];
        [self.button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        self.button.layer.cornerRadius = 16;
        self.button.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        [self.button addTarget:self action:@selector(showPanel) forControlEvents:UIControlEventTouchUpInside];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [self.button addGestureRecognizer:pan];
    }
    if (self.host != window) {
        [self.button removeFromSuperview];
        self.button.frame = CGRectMake(MAX(8, window.bounds.size.width - 80),
                                       window.safeAreaInsets.top + 80, 72, 34);
        self.button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                                      UIViewAutoresizingFlexibleBottomMargin;
        [window addSubview:self.button];
        self.host = window;
    }
    [window bringSubviewToFront:self.button];
}
- (void)drag:(UIPanGestureRecognizer *)gesture {
    UIWindow *window = self.host;
    if (!window) return;
    CGPoint shift = [gesture translationInView:window];
    CGPoint center = self.button.center;
    center.x = MIN(MAX(center.x + shift.x, 40), window.bounds.size.width - 40);
    center.y = MIN(MAX(center.y + shift.y, window.safeAreaInsets.top + 22),
                   window.bounds.size.height - window.safeAreaInsets.bottom - 22);
    self.button.center = center;
    [gesture setTranslation:CGPointZero inView:window];
}
- (UIViewController *)presenter {
    UIViewController *controller = self.host.rootViewController;
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
    NSDictionary *status = QARStatus();
    NSString *message = [NSString stringWithFormat:
        @"QQ %@\n已加载接口：%@\n已拦截通知：%@\n\n实验适配：请检查单聊、群聊及重启后的消息保留情况。",
        status[@"build_version"], status[@"installed_hooks"], status[@"intercepted_events"]];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"QQ 防撤回 · 实验版"
        message:message preferredStyle:UIAlertControllerStyleAlert];
    if ([status[@"installed_hooks"] unsignedIntegerValue] > 0) {
        [alert addAction:[UIAlertAction actionWithTitle:QAREnabled() ? @"关闭防撤回" : @"开启防撤回"
            style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                QARSetEnabled(!QAREnabled());
            }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"导出诊断" style:UIAlertActionStyleDefault
        handler:^(__unused UIAlertAction *action) {
            NSData *data = [NSJSONSerialization dataWithJSONObject:QARStatus()
                           options:NSJSONWritingPrettyPrinted error:nil];
            if (!data) return;
            NSURL *file = [NSURL fileURLWithPath:[NSTemporaryDirectory()
                          stringByAppendingPathComponent:@"QQAntiRecall-diagnostics.json"]];
            if (![data writeToURL:file options:NSDataWritingAtomic error:nil]) return;
            UIActivityViewController *share = [[UIActivityViewController alloc]
                initWithActivityItems:@[file] applicationActivities:nil];
            share.popoverPresentationController.sourceView = self.button;
            share.popoverPresentationController.sourceRect = self.button.bounds;
            dispatch_async(dispatch_get_main_queue(), ^{
                [[self presenter] presentViewController:share animated:YES completion:nil];
            });
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭面板" style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}
@end

static QARControl *control;
__attribute__((constructor)) static void QARStart(void) {
    @autoreleasepool {
        // The signed host may use a different bundle identifier. Exact QQ version/build
        // and presence of QQ's recall classes are checked by the adapter.
        NSDictionary *info = NSBundle.mainBundle.infoDictionary;
        if (!QARVersionSupported(info)) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            QARInstallAdapters(NSBundle.mainBundle.infoDictionary);
            control = [QARControl new];
            [NSNotificationCenter.defaultCenter addObserver:control selector:@selector(applicationActive:)
                name:UIApplicationDidBecomeActiveNotification object:nil];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                dispatch_get_main_queue(), ^{
                    QARInstallAdapters(NSBundle.mainBundle.infoDictionary);
                    [control attach];
                });
        });
    }
}
