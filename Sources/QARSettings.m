#import "QARSettings.h"
#import "QARHook.h"
#import "QARAdapter.h"
#import <objc/runtime.h>
static IMP factoryOriginal;
static QARHookResult factoryResult = QARHookMissingClass;
static NSMutableArray *appearHooks;
static char footerKey, entryKey;
@interface QARSettingsEntry : NSObject
@property(nonatomic,weak) UIViewController *controller;
- (void)open;
@end
@implementation QARSettingsEntry
- (void)open { if (self.controller) QAROpenSettingsPanel(self.controller); }
@end
@interface QARSettingsAppearHook : NSObject
@property(nonatomic) Class target;
@property(nonatomic) IMP original;
@property(nonatomic) IMP replacement;
@end
@implementation QARSettingsAppearHook @end
static UITableView *findTable(UIView *view, NSUInteger *count) {
    if (++*count > 256) return nil;
    if ([view isKindOfClass:UITableView.class]) return (UITableView *)view;
    for (UIView *child in view.subviews) { UITableView *table = findTable(child, count); if (table) return table; }
    return nil;
}
static void attach(UIViewController *controller) {
    if (!NSThread.isMainThread || ![controller isKindOfClass:UIViewController.class]) return;
    NSUInteger visited = 0; UITableView *table = findTable(controller.view, &visited); if (!table) return;
    if (objc_getAssociatedObject(table.tableFooterView, &footerKey)) return;
    UIView *previous = table.tableFooterView;
    CGFloat oldHeight = previous ? previous.frame.size.height : 0;
    // Detach through UITableView before reparenting; its setter removes the old footer.
    table.tableFooterView = nil;
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, table.bounds.size.width, oldHeight + 76)];
    footer.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    if (previous) { previous.frame = CGRectMake(0, 0, footer.bounds.size.width, oldHeight); [footer addSubview:previous]; }
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(16, oldHeight + 12, MAX(0, footer.bounds.size.width - 32), 48);
    button.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    button.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    button.layer.cornerRadius = 12;
    [button setTitle:@"防撤回与闪照 · 插件设置  ›" forState:UIControlStateNormal];
    QARSettingsEntry *entry = [QARSettingsEntry new]; entry.controller = controller;
    objc_setAssociatedObject(button, &entryKey, entry, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [button addTarget:entry action:@selector(open) forControlEvents:UIControlEventTouchUpInside];
    [footer addSubview:button]; objc_setAssociatedObject(footer, &footerKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    table.tableFooterView = footer;
}
static id createSettings(id receiver, SEL cmd) {
    id controller = ((id (*)(id, SEL))factoryOriginal)(receiver, cmd);
    if (![controller isKindOfClass:UIViewController.class] || !NSThread.isMainThread) return controller;
    Class cls = object_getClass(controller);
    if (!appearHooks) appearHooks = [NSMutableArray new];
    for (QARSettingsAppearHook *entry in appearHooks) if (entry.target == cls) return controller;
    if (appearHooks.count >= 8) return controller;
    QARSettingsAppearHook *entry = [QARSettingsAppearHook new]; entry.target = cls;
    entry.replacement = imp_implementationWithBlock(^(UIViewController *self, BOOL animated) {
        ((void (*)(id, SEL, BOOL))entry.original)(self, @selector(viewDidAppear:), animated);
        attach(self);
    });
    IMP original = NULL;
    if (QARInstallHook(cls, @selector(viewDidAppear:), "v20@0:8B16", entry.replacement, &original) == QARHookInstalled) {
        entry.original = original; [appearHooks addObject:entry];
    } else imp_removeBlock(entry.replacement);
    return controller;
}
void QARInstallSettings(NSDictionary *info) {
    if (!QARVersionSupported(info) || factoryOriginal) return;
    factoryResult = QARInstallHook(object_getClass(NSClassFromString(@"QQSettingsEntranceHelper")),
        NSSelectorFromString(@"createSettingsViewController"), "@16@0:8", (IMP)createSettings, &factoryOriginal);
}
NSDictionary *QARSettingsStatus(void) {
    return @{@"factory_hook_result": @(factoryResult), @"factory_installed": @(factoryOriginal != NULL),
        @"settings_controller_classes": @(appearHooks.count), @"floating_button": @NO};
}
