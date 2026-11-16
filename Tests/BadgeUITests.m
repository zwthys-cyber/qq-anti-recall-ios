#import <UIKit/UIKit.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import <objc/runtime.h>
#import "QARBadge.h"
#import "QARFlash.h"
#import "QARSettings.h"
#import "QARTheme.h"
#import "QARDeviceDiagnostics.h"
#import "QARDeviceName.h"
#import <objc/message.h>
#import "QARSnapshot.h"
#import "QARStore.h"
#import "QARAdapter.h"
#import "ModelFixtures.h"
#include <stdio.h>
#include <math.h>
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
@property(nonatomic,strong) id payload;
- (double)tableView:(id)table heightForRowAtIndexPath:(id)path;
@end
@implementation FixtureModel
- (double)tableView:(id)table heightForRowAtIndexPath:(id)path { (void)table; (void)path; check(NO, "opaque view model height is not the UIKit delegate"); return 78; }
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
    self.body = [NSClassFromString(@"_TtC6AIOLib13AIOBubbleView") new];
    self.body.font = [UIFont systemFontOfSize:16];
    self.body.numberOfLines = 2;
    self.body.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.body.layer.cornerRadius = 12; self.body.clipsToBounds = YES;
    [self.contentView addSubview:self.avatar]; [self.contentView addSubview:self.body];
    return self;
}
- (_Bool)bindViewModel:(FixtureModel *)model {
    self.model = model; self.avatar.record = model.payload;
    self.body.text = [@"  " stringByAppendingString:QARFixtureBody(model.payload) ?: (QARFlashURLForRecord(model.payload) ? @"闪照（合成测试图片）" : @"")];
    [self setNeedsLayout]; return NO; // False does not imply the visible avatar failed to bind.
}
- (void)unbindViewModel { self.model = nil; self.avatar.record = nil; self.body.text = nil; }
- (void)prepareForReuse { [super prepareForReuse]; [self unbindViewModel]; }
- (void)layoutSubviews {
    [super layoutSubviews];
    self.avatar.frame = CGRectMake(12, 18, 36, 36);
    self.body.frame = CGRectMake(56, 14, MIN(280, self.bounds.size.width - 72), 50);
}
@end
@interface FixtureTable : UITableView
@property(nonatomic) BOOL fixtureUpdatesPending;
@property(nonatomic) BOOL fixtureDragging;
@end
@implementation FixtureTable
- (BOOL)isDragging { return self.fixtureDragging || [super isDragging]; }
- (BOOL)hasUncommittedUpdates { return self.fixtureUpdatesPending || [super hasUncommittedUpdates]; }
- (UITableViewCell *)cellForRowAtIndexPath:(NSIndexPath *)path {
    check(!QARBadgeHeightCallbackForTest(), "row-height hooks must never recursively query UITableView cells");
    return [super cellForRowAtIndexPath:path];
}
@end
@interface FixtureController : UITableViewController
@property(nonatomic,strong) NSArray<FixtureModel *> *models;
@end
@implementation FixtureController
- (void)loadView {
    self.tableView = [[FixtureTable alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { (void)table; (void)section; return self.models.count; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    FixtureCell *cell = [table dequeueReusableCellWithIdentifier:@"fixture"];
    if (!cell) cell = [[FixtureCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"fixture"];
    [cell bindViewModel:self.models[path.row]]; return cell;
}
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    (void)table; (void)path;
    return 78; // The actual delegate does not call the view model's height helper.
}
@end
static void registerFixture(Class base, const char *name) {
    Class cls = objc_allocateClassPair(base, name, 0); check(cls != Nil, "allocate UI fixture class"); objc_registerClassPair(cls);
}
static FixtureModel *model(id record) {
    FixtureModel *result = [NSClassFromString(@"AIOBaseCellViewModel") new]; result.payload = record; return result;
}
static void after(dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), block);
}
static void waitUntil(BOOL (^condition)(void), dispatch_block_t done, NSUInteger remaining) {
    if (condition()) { done(); return; }
    check(remaining > 0, "UI transition must finish within ten seconds");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 10), dispatch_get_main_queue(), ^{
        waitUntil(condition, done, remaining - 1);
    });
}
static void testDeviceCollector(void) {
    JSContext *context = [JSContext new];
    [context evaluateScript:
        @"const same={location:{origin:'https://club.vip.qq.com'},document:{scripts:[{src:'https://imgcache.qq.com/frame.mjs?token=fixture'}]},performance:{getEntriesByType:()=>[]},frames:[]};"
        "const foreign={location:{origin:'https://other.invalid'}};"
        "const window={location:{origin:'https://club.vip.qq.com'},document:{scripts:[{src:''}]},"
        "performance:{getEntriesByType:()=>[{name:'https://g.gtimg.com/dynamic.js?token=fixture#secret'},{name:'https://club.vip.qq.com/api/private?token=fixture'}]},frames:[same,foreign]};"];
    id observation = [[context evaluateScript:QARDeviceDiagnosticScript()] toDictionary];
    check(context.exception == nil && [observation isKindOfClass:NSDictionary.class], "browser collector JavaScript executes");
    QARDeviceRecordObservation(observation);
    NSDictionary *status = QARDeviceDiagnosticsStatus(), *counts = status[@"last_scan_counts"];
    check([status[@"public_script_assets"] isEqual:@[@"https://g.gtimg.com/dynamic.js", @"https://imgcache.qq.com/frame.mjs"]],
        "removed dynamic scripts and same-origin frame modules are captured without tokens");
    check([counts[@"inline_scripts"] intValue] == 1 && [counts[@"frames_scanned"] intValue] == 2 &&
        [counts[@"frames_unavailable"] intValue] == 1 && [counts[@"resource_entries"] intValue] == 2,
        "collector distinguishes inline scripts, resources and unavailable frames");
    check(![[status description] containsString:@"fixture"] && ![[status description] containsString:@"private"],
        "diagnostics omit request tokens and API resource paths");
    report(@"STEP: device collector dynamic resources, same-origin frames, module assets and privacy passed");
}
static void testDeviceNameAdapter(void) {
    JSContext *context = [JSContext new];
    [context evaluateScript:
        @"var window=this;var location={protocol:'https:',hostname:'club.vip.qq.com',pathname:'/onlinestatus/set',origin:'https://club.vip.qq.com'};"
        "var document={body:null};var posted=[];var webkit={messageHandlers:{QARDeviceNameReceipt:{postMessage:x=>posted.push(x)}}};"
        "var defer=false;function XMLHttpRequest(){this.responseType='json';this.response={ret:0,data:{rsp:{iRet:0}}};this.status=200;this.listeners=[];}"
        "XMLHttpRequest.prototype.open=function(method,url){this.method=method;this.url=url;};"
        "XMLHttpRequest.prototype.addEventListener=function(name,fn){this.listeners.push(fn);};"
        "XMLHttpRequest.prototype.send=function(body){this.sent=body;if(!defer)this.listeners.splice(0).forEach(fn=>fn());};"
        "var fetchSeen,fetchReply={status:200,clone:()=>({json:()=>({then:ok=>ok({ret:0,data:{rsp:{iRet:0}}})})})};"
        "var fetch=function(input,init){fetchSeen={input:input,init:init};return {then:fn=>fn(fetchReply)};};"];
    NSString *name = @"我的设备 🌈 \"quoted\"";
    [context evaluateScript:QARDeviceNameScript(@{@"uin":@"10001", @"text":name})];
    NSDictionary *arg = @{@"lUin":@10001, @"sModel":@"iPhone", @"sModelShow":@"iPhone", @"sIMei":@"synthetic-device",
        @"iAppType":@1, @"sDesc":@"existing description", @"sVer":@"9.3.86", @"bShowInfo":@YES};
    NSDictionary *payload = @{@"servicesName":@"VIP.CustomOnlineStatusServer.CustomOnlineStatusObj", @"cmd":@"SetCustomOnlineStatus", @"args":@[arg]};
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    context[@"fixtureBody"] = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSDictionary *changed = [[context evaluateScript:
        @"var first=new XMLHttpRequest();first.open('POST','/srf-cgi-node?srfname=fixture');first.send(fixtureBody);JSON.parse(first.sent).args[0]"] toDictionary];
    check(context.exception == nil && [changed[@"sModelShow"] isEqual:name] && [changed[@"sModel"] isEqual:name], "device adapter supports arbitrary Unicode and quotes");
    NSMutableDictionary *preserved = [changed mutableCopy]; preserved[@"sModel"] = @"iPhone"; preserved[@"sModelShow"] = @"iPhone";
    check([preserved isEqual:arg], "device adapter preserves account, device binding, version, custom prefix and all other fields");
    check([[context evaluateScript:@"posted[posted.length-1].last_result"] toInt32] == 1, "both server success codes are required for acceptance");
    [context evaluateScript:
        @"var denied=new XMLHttpRequest();denied.response={ret:0,data:{rsp:{iRet:9}}};denied.open('POST','/srf-cgi-node');denied.send(fixtureBody);"];
    check([[context evaluateScript:@"posted[posted.length-1].last_result"] toInt32] == -1, "server rejection is never reported as success");
    BOOL isolated = [[context evaluateScript:
        @"var other=JSON.parse(fixtureBody);other.args[0].lUin=20002;var otherBody=JSON.stringify(other);var mismatch=new XMLHttpRequest();mismatch.open('POST','/srf-cgi-node');mismatch.send(otherBody);mismatch.sent===otherBody"] toBool];
    check(isolated, "device adapter refuses another account");
    BOOL unrelated = [[context evaluateScript:
        @"var foreign=new XMLHttpRequest();foreign.open('POST','https://club.vip.qq.com.evil.invalid/srf-cgi-node');foreign.send(fixtureBody);foreign.sent===fixtureBody"] toBool];
    check(unrelated, "device adapter leaves unrelated hosts unchanged");
    check([[context evaluateScript:
        @"var missing=JSON.parse(fixtureBody);delete missing.args[0].sModel;var missingBody=JSON.stringify(missing);"
        "var unsupported=new XMLHttpRequest();unsupported.open('POST','/srf-cgi-node');unsupported.send(missingBody);unsupported.sent===missingBody"] toBool],
        "unknown model schema passes through unchanged");
    BOOL fetchOK = [[context evaluateScript:
        @"var init=Object.freeze({method:'POST',credentials:'include',body:fixtureBody,headers:{'Content-Type':'application/json'}});"
        "var answer=fetch('/srf-cgi-node',init);answer===fetchReply&&fetchSeen.init.credentials===init.credentials&&fetchSeen.init.headers===init.headers&&init.body===fixtureBody"] toBool];
    check(fetchOK && [[[context evaluateScript:@"JSON.parse(fetchSeen.init.body).args[0].sModelShow"] toString] isEqual:name],
        "fetch adapter preserves original options and response without mutating input");
    [context evaluateScript:@"defer=true;var stale=new XMLHttpRequest();stale.open('POST','/srf-cgi-node');stale.send(fixtureBody);"];
    [context evaluateScript:QARDeviceNameScript(@{@"uin":@"10001", @"text":@"新的设备名"})];
    check([[context evaluateScript:@"var before=posted.length;stale.listeners.forEach(fn=>fn());posted.length===before"] toBool],
        "a response for an old configured name cannot confirm the new name");
    NSString *exported = [[context evaluateScript:@"JSON.stringify(posted)"] toString];
    check(![exported containsString:@"10001"] && ![exported containsString:@"synthetic-device"] &&
        ![exported containsString:@"我的设备"] && context.exception == nil, "device receipt bridge contains no account, name or request fields");
    report(@"STEP: device-name XHR/fetch adapter, Unicode, account isolation, response validation and privacy passed");
}
static UIViewController *settingsResult;
static id settingsFactory(id receiver, SEL cmd) { (void)receiver; (void)cmd; return settingsResult; }
@interface FixtureSettingsController : UITableViewController @end
@implementation FixtureSettingsController @end
static void testSettings(void) {
    Class cls = objc_allocateClassPair(NSObject.class, "QQSettingsEntranceHelper", 0);
    class_addMethod(object_getClass(cls), NSSelectorFromString(@"createSettingsViewController"), (IMP)settingsFactory, "@16@0:8");
    objc_registerClassPair(cls);
    QARInstallSettings(QARFixtureInfo());
    FixtureSettingsController *controller = [FixtureSettingsController new]; settingsResult = controller;
    [controller loadViewIfNeeded];
    UIView *previous = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 300, 20)];
    controller.tableView.tableFooterView = previous;
    check(((id (*)(id, SEL))objc_msgSend)(cls, NSSelectorFromString(@"createSettingsViewController")) == controller,
        "settings factory preserves original controller");
    [controller viewDidAppear:NO];
    UIView *footer = controller.tableView.tableFooterView;
    check(footer != previous && previous.superview == footer && footer.subviews.count == 2,
        "plugin entry is inside settings and preserves previous footer");
    [controller viewDidAppear:NO];
    check(controller.tableView.tableFooterView == footer && footer.subviews.count == 2, "settings entry does not duplicate");
    UIButton *entryButton = nil;
    for (UIView *view in footer.subviews) if ([view isKindOfClass:UIButton.class]) entryButton = (UIButton *)view;
    controller.tableView.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    controller.tableView.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1];
    [entryButton setNeedsLayout]; [entryButton layoutIfNeeded];
    check(QARSurfaceIsDark(entryButton.backgroundColor, entryButton.traitCollection),
        "settings entry follows a dark QQ surface even when inherited traits are light");
    controller.tableView.backgroundColor = UIColor.whiteColor;
    [entryButton setNeedsLayout]; [entryButton layoutIfNeeded];
    check(!QARSurfaceIsDark(entryButton.backgroundColor, entryButton.traitCollection),
        "settings entry returns to light with a light host");
    check(![QARSettingsStatus()[@"floating_button"] boolValue], "settings integration has no floating button");
    FixtureSettingsController *unrelated = [FixtureSettingsController new];
    [unrelated loadViewIfNeeded]; [unrelated viewDidAppear:NO];
    check(unrelated.tableView.tableFooterView == nil, "another instance of the same class does not gain a settings entry");
    settingsResult = nil;
    report(@"STEP: settings factory, in-menu entry, original footer and duplicate prevention passed");
}
static id flashResult, flashChatRecord;
static id flashDecode(id receiver, SEL cmd, id path) { (void)receiver; (void)cmd; (void)path; return flashResult; }
static void testFlash(void) {
    Class service = objc_allocateClassPair(NSObject.class, "PhotoBrowserFlashPictureService", 0);
    class_addMethod(object_getClass(service), NSSelectorFromString(@"decryptImageWithImagePath:"), (IMP)flashDecode, "@24@0:8@16");
    objc_registerClassPair(service);
    QARInstallFlash(QARFixtureInfo());
    QARFlashUseTestDirectory([NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"flash-fixture"]]);
    QARClearFlash(); QARSetFlashEnabled(YES);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(16, 16)];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [UIColor.systemTealColor setFill]; CGContextFillRect(context.CGContext, CGRectMake(0, 0, 16, 16));
    }];
    NSString *source = [NSTemporaryDirectory() stringByAppendingPathComponent:@"synthetic-flash.png"];
    check([UIImagePNGRepresentation(image) writeToFile:source atomically:YES], "create synthetic flash source");
    flashResult = source;
    SEL selector = NSSelectorFromString(@"decryptImageWithImagePath:");
    id returned = ((id (*)(id, SEL, id))objc_msgSend)(service, selector, @"synthetic");
    check(returned == flashResult && QARFlashFiles().count == 1, "flash hook preserves original result and copies the decrypted image");
    [NSFileManager.defaultManager removeItemAtPath:source error:nil];
    NSURL *savedURL = QARFlashFiles().firstObject;
    check([UIImage imageWithContentsOfFile:savedURL.path] && [UIImage imageWithContentsOfFile:savedURL.path],
        "flash copy remains repeatedly viewable after original deletion");
    flashResult = image;
    ((id (*)(id, SEL, id))objc_msgSend)(service, selector, @"synthetic");
    check(QARFlashFiles().count == 1, "duplicate decrypted image is not duplicated");
    QARClearFlash(); QARSetFlashEnabled(NO);
    ((id (*)(id, SEL, id))objc_msgSend)(service, selector, @"synthetic");
    check(QARFlashFiles().count == 0, "disabled mode saves no flash images");
    QARSetFlashEnabled(YES);
    ((id (*)(id, SEL, id))objc_msgSend)(service, selector, @"synthetic");
    QARFixtureAccount(20002);
    check(QARFlashFiles().count == 0, "flash gallery is account isolated");
    QARFixtureAccount(10001);
    check(QARFlashFiles().count == 1, "original account retains its flash copy");
    id record = QARFixtureMessage(44, 44, @"flash-peer", 0, nil);
    id pic = QARModelCreate(@"OCPicElement"), element = QARModelCreate(@"OCMsgElement");
    QARModelWrite(pic, @"isFlashPic", @YES); QARModelWrite(pic, @"sourcePath", @"synthetic");
    QARModelWrite(element, @"picElement", pic); QARModelWrite(record, @"elements", @[element]);
    check(QARFlashURLForRecord(record) != nil, "chat message resolves only its retained flash image");
    QARSetEnabled(NO);
    check(QARFlashURLForRecord(record) != nil, "flash retention works independently of anti-recall switch");
    QARSetEnabled(YES);
    QARModelWrite(pic, @"sourcePath", @"different-message");
    check(QARFlashURLForRecord(record) == nil, "unmatched chat message cannot open another image");
    QARModelWrite(pic, @"sourcePath", @"synthetic"); QARModelWrite(pic, @"isFlashPic", @NO);
    check(QARFlashURLForRecord(record) == nil, "ordinary pictures never receive flash replay controls");
    QARModelWrite(pic, @"isFlashPic", @YES); QARSetFlashEnabled(NO);
    check(QARFlashURLForRecord(record) == nil, "flash switch disables chat replay");
    QARSetFlashEnabled(YES);
    QARClearFlash(); check(QARFlashFiles().count == 0 && QARFlashURLForRecord(record) == nil, "explicit clear removes retained images and chat lookup");
    ((id (*)(id, SEL, id))objc_msgSend)(service, selector, @"synthetic");
    flashChatRecord = record;
    flashResult = nil;
    report(@"STEP: flash copy, repeated viewing after deletion, pass-through, deduplication, disable, account isolation and clear passed");
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
    testFlash(); testSettings(); testDeviceCollector(); testDeviceNameAdapter();
    NSArray *publicAssets = QARDevicePublicAssets(@[
        @"https://imgcache.qq.com/app/device.js?token=private-fixture#secret",
        @"https://imgcache.qq.com/app/device.js?uin=private-fixture",
        @"https://user:private-fixture@imgcache.qq.com/app/other.js",
        @"https://imgcache.qq.com.evil.invalid/app/device.js",
        @"http://imgcache.qq.com/app/device.js", @"https://club.vip.qq.com/private?cookie=secret",
        @"https://qzonestyle.gtimg.cn/assets/device-v2.js", @123]);
    check([publicAssets isEqual:@[@"https://imgcache.qq.com/app/device.js",
        @"https://qzonestyle.gtimg.cn/assets/device-v2.js"]], "device diagnostics reject credentials and unrelated hosts, strip query/fragment and deduplicate");
    check(![QARDeviceDiagnosticsStatus()[@"friend_visible_verified"] boolValue], "friend-visible verification is never inferred from installing an adapter");
    registerFixture(UILabel.class, "_TtC6AIOLib13AIOBubbleView");
    registerFixture(FixtureAvatar.class, "QQNTAIOMessageAvatarView");
    registerFixture(FixtureCell.class, "_TtC6AIOLib7AIOCell");
    registerFixture(FixtureModel.class, "AIOBaseCellViewModel");
    QARInstallBadge(QARFixtureInfo());
    check([QARBadgeStatus()[@"installed_hooks"] unsignedIntegerValue] == 8, "static avatar and cell hooks installed before discovering the actual delegate");
    QARStoreUseTestDirectory([NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"badge-fixtures"]]);
    QARClearSavedMessages();
    id original = QARFixtureMessage(1, 1, @"fixture", 0, @"这条消息已为你保留。");
    id recalled = QARFixtureMessage(1, 1, @"fixture", 1700000000, nil);
    id normal = QARFixtureMessage(2, 2, @"fixture", 0, @"普通消息保持原样。");
    QARRememberMessages(@[original]); QARMarkRecalledUpdates(@[recalled]);
    self.controller = [[FixtureController alloc] initWithStyle:UITableViewStylePlain];
    self.controller.models = @[model(original), model(normal), model(flashChatRecord)];
    self.controller.title = @"防撤回标识 · 模拟数据";
    self.controller.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.controller.tableView.estimatedRowHeight = 0;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:self.controller];
    ((FixtureTable *)self.controller.tableView).fixtureUpdatesPending = YES;
    ((FixtureTable *)self.controller.tableView).fixtureDragging = YES;
    [self.window makeKeyAndVisible];
    for (NSUInteger n=0; n<64; n++) for (UITableViewCell *cell in self.controller.tableView.visibleCells)
        QARBadgeRefreshCellForTest(cell);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 5), dispatch_get_main_queue(), ^{
        ((FixtureTable *)self.controller.tableView).fixtureUpdatesPending = NO;
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
        check([QARBadgeStatus()[@"height_refreshes"] unsignedIntegerValue] == 0, "footer height work waits until dragging stops");
        ((FixtureTable *)self.controller.tableView).fixtureDragging = NO;
    });
    after(^{
        UITableView *table = self.controller.tableView;
        FixtureCell *cell = [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        UIView *pill = QARBadgeViewForTest(cell);
        check(pill && !pill.hidden, "retained message displays a badge despite burst layouts during QQ batch updates");
        check([QARBadgeStatus()[@"deferred_height_updates"] unsignedIntegerValue] > 0, "busy QQ updates defer footer work without exhausting attempts");
        check(CGRectGetMinY(pill.frame) >= CGRectGetMaxY(cell.body.frame) &&
              CGRectGetMaxY(pill.frame) <= cell.contentView.bounds.size.height, "badge is below the body and inside its own row");
        check(fabs(CGRectGetMinY(pill.frame) - CGRectGetMaxY(cell.body.frame) - 4) <= 1, "badge sits four points below its message bubble");
        UITableViewCell *second = [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
        check(!QARBadgeViewForTest(second) || QARBadgeViewForTest(second).hidden, "normal row has no recall badge");
        check([QARBadgeStatus()[@"rows_with_footer_reserved"] unsignedIntegerValue] > 0 &&
            [QARBadgeStatus()[@"delegate_height_calls"] unsignedIntegerValue] > 0, "actual table delegate reserves footer space");
        UITableView *unrelated = [UITableView new];
        check([self.controller tableView:unrelated heightForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]] == 78,
            "same delegate class preserves an unrelated table");
        check(second.bounds.size.height == 78, "ordinary row keeps its original height");
        UITableViewCell *flashCell = [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:0]];
        UIView *flashPill = QARBadgeViewForTest(flashCell);
        check(flashPill && !flashPill.hidden && flashPill.userInteractionEnabled &&
            [flashPill.accessibilityLabel isEqual:@"闪照 · 再次查看"], "flash replay entry appears on its chat message");
        check(CGRectGetMaxY(flashPill.frame) <= flashCell.contentView.bounds.size.height,
            "flash replay footer stays within its own message row");
        QARBadgeRefreshCellForTest(flashCell);
        unsigned long long lookups = [QARFlashStatus()[@"chat_record_lookups"] unsignedLongLongValue];
        unsigned long long refreshes = [QARBadgeStatus()[@"height_refreshes"] unsignedLongLongValue];
        for (NSUInteger i=0; i<128; i++) QARBadgeRefreshCellForTest(flashCell);
        check([QARFlashStatus()[@"chat_record_lookups"] unsignedLongLongValue] <= lookups + 2,
            "stable layout burst reuses flash lookup instead of synchronously reading storage each time");
        check([QARBadgeStatus()[@"height_refreshes"] unsignedLongLongValue] == refreshes,
            "stable layout burst does not refresh table height");
        report(@"STEP: opaque view model, false bind result, actual delegate, badge geometry and ordinary rows passed");
        [self savePreview:@"badge-light.png"];
        self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        after(^{
            [self savePreview:@"badge-dark.png"];
            report(@"STEP: light and dark previews saved");
            [cell prepareForReuse]; [cell bindViewModel:model(normal)]; [cell layoutIfNeeded];
            check(!QARBadgeViewForTest(cell) || QARBadgeViewForTest(cell).hidden, "reuse clears the previous message badge");
            QARStoreDropMemoryForTest();
            self.controller.models = @[model(QARRestoreHistory(@[recalled])[0]), model(normal), model(flashChatRecord)];
            [table reloadData];
            after(^{
                UITableViewCell *restoredCell = [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
                if (!QARBadgeViewForTest(restoredCell) || QARBadgeViewForTest(restoredCell).hidden)
                    fprintf(stderr, "Synthetic badge state: %s\\n", [[QARBadgeStatus() description] UTF8String]);
                check(QARBadgeViewForTest(restoredCell) && !QARBadgeViewForTest(restoredCell).hidden,
                    "badge returns after history reload from disk");
                report(@"STEP: reuse and disk reload assertions passed");
                QARSetEnabled(NO);
                after(^{
                    check(!QARBadgeViewForTest(restoredCell) || QARBadgeViewForTest(restoredCell).hidden, "disabling hides the badge");
                    QARSetEnabled(YES); QARFixtureAccount(20002);
                    QARBadgeRefreshCellForTest(restoredCell);
                    check(!QARBadgeViewForTest(restoredCell) || QARBadgeViewForTest(restoredCell).hidden, "account switch hides old markers");
                    QARFixtureAccount(10001);
                    QARPresentFlashRecord(self.controller, flashChatRecord);
                    after(^{
                        check(self.controller.presentedViewController != nil, "chat replay opens retained image");
                        [self.controller dismissViewControllerAnimated:NO completion:^{
                            QARPresentFlashRecord(self.controller, flashChatRecord);
                            after(^{
                                check(self.controller.presentedViewController != nil, "same chat message opens its image repeatedly");
                                QARSetFlashEnabled(NO);
                                waitUntil(^BOOL{ return self.controller.presentedViewController == nil; }, ^{
                                    check(self.controller.presentedViewController == nil, "turning off flash retention closes replay");
                                    [self verifyScrollFollowing];
                                }, 100);
                            });
                        }];
                    });
                });
            });
        });
    });
}
- (void)verifyScrollFollowing {
    QARFixtureAccount(10001); QARSetEnabled(YES);
    NSMutableArray *records = [NSMutableArray new], *models = [NSMutableArray new];
    for (NSInteger i=0; i<36; i++) {
        id record = QARFixtureMessage(1000+i, 1000+i, @"scroll-fixture", 0, @"滚动位置测试");
        [records addObject:record]; [models addObject:model(record)];
    }
    QARRememberMessages(records);
    UITableView *table = self.controller.tableView;
    table.contentInset = UIEdgeInsetsMake(0, 0, 96, 0); // Simulated composer/keyboard space.
    self.controller.models = models; [table reloadData]; [table layoutIfNeeded];
    [table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:35 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:NO];
    after(^{
        [table setContentOffset:CGPointMake(0, MAX(-table.adjustedContentInset.top,
            table.contentSize.height + table.adjustedContentInset.bottom - table.bounds.size.height)) animated:NO];
        QARMarkRecalledUpdates(@[QARFixtureMessage(1035, 1035, @"scroll-fixture", 1700000000, nil)]);
        after(^{
            CGFloat visibleBottom = table.contentOffset.y + table.bounds.size.height - table.adjustedContentInset.bottom;
            CGRect lastRow = [table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:35 inSection:0]];
            if (CGRectGetMaxY(lastRow) > visibleBottom + 2) {
                report([NSString stringWithFormat:@"FAIL: bottom following geometry row=%g visible=%g offset=%g content=%g inset=%g",
                    CGRectGetMaxY(lastRow), visibleBottom, table.contentOffset.y, table.contentSize.height, table.adjustedContentInset.bottom]); exit(1);
            }
            [table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:12 inSection:0] atScrollPosition:UITableViewScrollPositionTop animated:NO];
            after(^{
                QARMarkRecalledUpdates(@[QARFixtureMessage(1012, 1012, @"scroll-fixture", 1700000000, nil)]);
                after(^{
                    CGFloat bottom = MAX(-table.adjustedContentInset.top,
                        table.contentSize.height + table.adjustedContentInset.bottom - table.bounds.size.height);
                    check(bottom - table.contentOffset.y > 100, "reading history is not forced to the latest message");
                    [self verifyPreferences];
                });
            });
        });
    });
}

- (void)verifyPreferences {
    QAROpenSettingsPanel(self.controller);
    after(^{
        UINavigationController *nav = (id)self.controller.presentedViewController;
        check([nav isKindOfClass:UINavigationController.class], "settings presents native navigation");
        UITableViewController *page = (id)nav.topViewController;
        check([page isKindOfClass:UITableViewController.class] && page.tableView.numberOfSections == 4,
            "settings uses four native grouped sections");
        NSIndexPath *recallPath = [NSIndexPath indexPathForRow:0 inSection:0];
        NSIndexPath *flashPath = [NSIndexPath indexPathForRow:1 inSection:0];
        UISwitch *recall = (id)[page.tableView cellForRowAtIndexPath:recallPath].accessoryView;
        UISwitch *flash = (id)[page.tableView cellForRowAtIndexPath:flashPath].accessoryView;
        check([recall isKindOfClass:UISwitch.class] && [flash isKindOfClass:UISwitch.class], "settings provides native accessible switches");
        BOOL originalRecall = QAREnabled(), originalFlash = QARFlashEnabled();
        recall.on = !originalRecall; [recall sendActionsForControlEvents:UIControlEventValueChanged];
        check(QAREnabled() != originalRecall && QARFlashEnabled() == originalFlash, "recall switch leaves flash preference unchanged");
        recall.on = originalRecall; [recall sendActionsForControlEvents:UIControlEventValueChanged];
        flash.on = !originalFlash; [flash sendActionsForControlEvents:UIControlEventValueChanged];
        check(QARFlashEnabled() != originalFlash && QAREnabled() == originalRecall, "flash switch leaves recall preference unchanged");
        flash.on = originalFlash; [flash sendActionsForControlEvents:UIControlEventValueChanged];
        self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
        after(^{
            [nav.view setNeedsLayout]; [nav.view layoutIfNeeded];
            check(!QARSurfaceIsDark(nav.navigationBar.standardAppearance.backgroundColor, nav.traitCollection),
                "plugin navigation uses explicit light appearance");
            [self savePreview:@"settings-light.png"];
            self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
            after(^{
                [nav.view setNeedsLayout]; [nav.view layoutIfNeeded];
                check(QARSurfaceIsDark(nav.navigationBar.standardAppearance.backgroundColor, nav.traitCollection) &&
                    QARSurfaceIsDark(nav.navigationBar.scrollEdgeAppearance.backgroundColor, nav.traitCollection),
                    "standard and scroll-edge navigation surfaces follow dark mode");
                [self savePreview:@"settings-dark.png"];
                NSUInteger savedBefore = QARFlashFiles().count;
                [page tableView:page.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:1]];
                after(^{
                    UIAlertController *confirmation = (id)page.presentedViewController;
                    check([confirmation isKindOfClass:UIAlertController.class] && confirmation.actions.count == 2,
                        "clearing cached images requires explicit confirmation");
                    check(QARFlashFiles().count == savedBefore, "opening clear confirmation never deletes data");
                    [page dismissViewControllerAnimated:NO completion:^{
                        [nav setOverrideTraitCollection:[UITraitCollection traitCollectionWithPreferredContentSizeCategory:UIContentSizeCategoryAccessibilityExtraExtraExtraLarge]
                            forChildViewController:page];
                        [page.tableView reloadData]; [page.tableView layoutIfNeeded];
                        after(^{
                            check(page.tableView.contentSize.height > 0, "large-text settings remains a scrollable table");
                            [self savePreview:@"settings-large-text.png"];
                            report(@"PASS: UIKit footer geometry, chat replay, scroll position, native settings switches, deletion confirmation and large text");
                            fflush(stdout); exit(0);
                        });
                    }];
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
