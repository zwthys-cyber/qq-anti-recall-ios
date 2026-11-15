#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "QARBadge.h"
#import "QARSnapshot.h"
#import "QARStore.h"
#import "QARAdapter.h"
#import "ModelFixtures.h"
#include <stdio.h>
#include <stdlib.h>

static void report(NSString *text) {
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    [NSFileManager.defaultManager createDirectoryAtURL:documents withIntermediateDirectories:YES attributes:nil error:nil];
    [text writeToURL:[documents URLByAppendingPathComponent:@"fixture-result.txt"]
         atomically:YES encoding:NSUTF8StringEncoding error:nil];
    fprintf(stderr, "%s\n", text.UTF8String); fflush(stderr);
}
static void check(BOOL condition, const char *why) {
    if (!condition) { report([@"FAIL: " stringByAppendingString:@(why)]); exit(1); }
}
@interface FixtureAvatar : UIView
@property(nonatomic,strong) id record;
@end
@implementation FixtureAvatar @end
@interface FixtureModel : NSObject
@property(nonatomic,strong) id record;
- (double)tableView:(id)table heightForRowAtIndexPath:(id)path;
@end
@implementation FixtureModel
- (double)tableView:(id)table heightForRowAtIndexPath:(id)path { (void)table; (void)path; return 78; }
@end
@interface FixtureCell : UITableViewCell
@property(nonatomic,strong) FixtureAvatar *avatar;
@property(nonatomic,strong) UILabel *body;
@property(nonatomic,strong) FixtureModel *model;
- (_Bool)bindViewModel:(FixtureModel *)model;
- (void)unbindViewModel;
@end
@implementation FixtureCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuse {
    if (!(self = [super initWithStyle:style reuseIdentifier:reuse])) return nil;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.avatar = [NSClassFromString(@"QQNTAIOMessageAvatarView") new];
    self.avatar.backgroundColor = UIColor.systemTealColor;
    self.avatar.layer.cornerRadius = 18;
    self.body = [UILabel new];
    self.body.font = [UIFont systemFontOfSize:16];
    self.body.numberOfLines = 2;
    self.body.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.body.layer.cornerRadius = 12; self.body.clipsToBounds = YES;
    [self.contentView addSubview:self.avatar]; [self.contentView addSubview:self.body];
    return self;
}
- (BOOL)bindViewModel:(FixtureModel *)model {
    self.model = model; self.avatar.record = model.record;
    self.body.text = [@"  " stringByAppendingString:QARFixtureBody(model.record) ?: @""];
    [self setNeedsLayout]; return YES;
}
- (void)unbindViewModel { self.model = nil; self.avatar.record = nil; self.body.text = nil; }
- (void)prepareForReuse { [super prepareForReuse]; [self unbindViewModel]; }
- (void)layoutSubviews {
    [super layoutSubviews];
    self.avatar.frame = CGRectMake(12, 18, 36, 36);
    self.body.frame = CGRectMake(56, 14, MIN(280, self.bounds.size.width - 72), 50);
}
@end
@interface FixtureController : UITableViewController
@property(nonatomic,strong) NSArray<FixtureModel *> *models;
@end
@implementation FixtureController
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { (void)table; (void)section; return self.models.count; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    FixtureCell *cell = [table dequeueReusableCellWithIdentifier:@"fixture"];
    if (!cell) cell = [[NSClassFromString(@"_TtC6AIOLib7AIOCell") alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"fixture"];
    [cell bindViewModel:self.models[path.row]]; return cell;
}
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    return [self.models[path.row] tableView:table heightForRowAtIndexPath:path];
}
@end
static void registerFixture(Class base, const char *name) {
    Class cls = objc_allocateClassPair(base, name, 0); check(cls != Nil, "allocate UI fixture class"); objc_registerClassPair(cls);
}
static FixtureModel *model(id record) {
    FixtureModel *result = [NSClassFromString(@"AIOBaseCellViewModel") new]; result.record = record; return result;
}
static void after(dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), block);
}
@interface FixtureScene : UIResponder <UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) FixtureController *controller;
@end
@interface FixtureApp : UIResponder <UIApplicationDelegate>
@end
@implementation FixtureApp
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)app; (void)options;
    report(@"START: application delegate");
    return YES;
}
- (UISceneConfiguration *)application:(UIApplication *)app
    configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)app; (void)options;
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Fixture" sessionRole:session.role];
    configuration.delegateClass = FixtureScene.class;
    return configuration;
}
@end
@implementation FixtureScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)session; (void)options;
    check([scene isKindOfClass:UIWindowScene.class], "UIKit window scene");
    report(@"START: scene connected");
    QARFixtureModels(); QARSetEnabled(YES);
    registerFixture(FixtureAvatar.class, "QQNTAIOMessageAvatarView");
    registerFixture(FixtureCell.class, "_TtC6AIOLib7AIOCell");
    registerFixture(FixtureModel.class, "AIOBaseCellViewModel");
    QARInstallBadge(QARFixtureInfo());
    check([QARBadgeStatus()[@"installed_hooks"] unsignedIntegerValue] == 7, "all verified badge hooks installed");
    QARStoreUseTestDirectory([NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"badge-fixtures"]]);
    QARClearSavedMessages();
    id original = QARFixtureMessage(1, 1, @"fixture", 0, @"这条消息已为你保留。");
    id recalled = QARFixtureMessage(1, 1, @"fixture", 1700000000, nil);
    id normal = QARFixtureMessage(2, 2, @"fixture", 0, @"普通消息保持原样。");
    QARRememberMessages(@[original]); QARMarkRecalledUpdates(@[recalled]);
    self.controller = [[FixtureController alloc] initWithStyle:UITableViewStylePlain];
    self.controller.models = @[model(original), model(normal)];
    self.controller.title = @"防撤回标识 · 模拟数据";
    self.controller.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.controller.tableView.estimatedRowHeight = 0;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:self.controller];
    [self.window makeKeyAndVisible];
    after(^{
        UITableView *table = self.controller.tableView;
        FixtureCell *cell = [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        UIView *pill = QARBadgeViewForTest(cell);
        check(pill && !pill.hidden, "retained message displays a badge");
        check(CGRectGetMinY(pill.frame) >= CGRectGetMaxY(cell.body.frame) &&
              CGRectGetMaxY(pill.frame) <= cell.contentView.bounds.size.height, "badge is below the body and inside its own row");
        UITableViewCell *second = [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
        check(!QARBadgeViewForTest(second) || QARBadgeViewForTest(second).hidden, "normal row has no recall badge");
        [self savePreview:@"badge-light.png"];
        self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        after(^{
            [self savePreview:@"badge-dark.png"];
            [cell prepareForReuse]; [cell bindViewModel:model(normal)]; [cell layoutIfNeeded];
            check(!QARBadgeViewForTest(cell) || QARBadgeViewForTest(cell).hidden, "reuse clears the previous message badge");
            QARStoreDropMemoryForTest();
            self.controller.models = @[model(QARRestoreHistory(@[recalled])[0]), model(normal)];
            [table reloadData];
            after(^{
                UITableViewCell *restoredCell = [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
                check(QARBadgeViewForTest(restoredCell) && !QARBadgeViewForTest(restoredCell).hidden,
                    "badge returns after history reload from disk");
                QARSetEnabled(NO);
                after(^{
                    check(!QARBadgeViewForTest(restoredCell) || QARBadgeViewForTest(restoredCell).hidden, "disabling hides the badge");
                    QARSetEnabled(YES); QARFixtureAccount(20002);
                    QARBadgeRefreshCellForTest(restoredCell);
                    check(!QARBadgeViewForTest(restoredCell) || QARBadgeViewForTest(restoredCell).hidden, "account switch hides old markers");
                    report(@"PASS: UIKit footer geometry, normal rows, cell reuse, history reload, dark mode, disable and account switch");
                    fflush(stdout); exit(0);
                });
            });
        });
    });
}
- (void)savePreview:(NSString *)name {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:self.window.bounds.size];
    UIImage *image = [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
        [self.window drawViewHierarchyInRect:self.window.bounds afterScreenUpdates:YES];
    }];
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    check([UIImagePNGRepresentation(image) writeToURL:[documents URLByAppendingPathComponent:name] atomically:YES],
        "write synthetic badge preview");
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { report(@"START: executable"); return UIApplicationMain(argc, argv, nil, NSStringFromClass(FixtureApp.class)); }
}
