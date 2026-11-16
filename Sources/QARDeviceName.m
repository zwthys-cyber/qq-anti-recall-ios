#import "QARDeviceName.h"
#import "QARHook.h"
#import "QARStore.h"
#import <objc/message.h>
#import <objc/runtime.h>
#include "QARDeviceNameScript.inc"
static char ownerKey, controllerKey, editorKey;
static NSHashTable<WKWebView *> *views;
static NSDictionary *receipt;
static NSString *receiptOwner;
static unsigned long long preparationFailures;
static BOOL target(NSURL *url) {
    return [url.scheme.lowercaseString isEqual:@"https"] && [url.host.lowercaseString isEqual:@"club.vip.qq.com"] &&
        [url.path isEqual:@"/onlinestatus/set"];
}
static NSString *accountID(void) {
    Class cls = NSClassFromString(@"QQAccountsManager");
    SEL factory = NSSelectorFromString(@"GetInstance"), current = NSSelectorFromString(@"currentUin");
    Method method = class_getClassMethod(cls, factory);
    if (!method || !QARSignaturesMatch(method_getTypeEncoding(method), "@16@0:8")) return nil;
    @try {
        id manager = ((id (*)(id,SEL))objc_msgSend)(cls,factory);
        method = class_getInstanceMethod(object_getClass(manager), current);
        if (![manager isKindOfClass:cls] || !method || !QARSignaturesMatch(method_getTypeEncoding(method), "Q16@0:8")) return nil;
        unsigned long long value = ((unsigned long long (*)(id,SEL))objc_msgSend)(manager,current);
        return value ? [NSString stringWithFormat:@"%llu",value] : nil;
    } @catch (__unused NSException *exception) { return nil; }
}
static NSString *preferenceKey(void) {
    NSString *owner = QARCurrentOwner();
    return owner ? [@"QARCustomDeviceName." stringByAppendingString:owner] : nil;
}
static NSString *customName(void) {
    NSString *key = preferenceKey(); id value = key ? [NSUserDefaults.standardUserDefaults objectForKey:key] : nil;
    return [value isKindOfClass:NSString.class] && [value length] <= 256 ? value : @"";
}
NSString *QARDeviceNameScript(NSDictionary *config) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:config options:0 error:nil];
    if (!data) return nil;
    return [NSString stringWithFormat:@"(%@)(%@)", [NSString stringWithUTF8String:QARDeviceNameJS],
        [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
}
@interface QARDeviceReceiptHandler : NSObject <WKScriptMessageHandler> @end
@implementation QARDeviceReceiptHandler
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    (void)controller;
    NSString *owner = objc_getAssociatedObject(message.webView, &ownerKey);
    if (!message.frameInfo.isMainFrame || !target(message.frameInfo.request.URL) || !target(message.webView.URL) ||
        !owner || ![owner isEqual:QARCurrentOwner()] || ![message.body isKindOfClass:NSDictionary.class]) return;
    NSMutableDictionary *safe = [NSMutableDictionary new];
    for (NSString *key in @[@"installed", @"patched_requests", @"unsupported_requests", @"accepted_responses",
                            @"rejected_responses", @"unrecognized_responses", @"last_result", @"last_code", @"http_status", @"outer_code", @"inner_code", @"has_outer_code", @"has_inner_code"]) {
        id value = message.body[key];
        if ([value isKindOfClass:NSNumber.class]) safe[key] = @(MAX(-1000000000LL, MIN(1000000000LL, [value longLongValue])));
    }
    receipt = safe; receiptOwner = owner;
}
@end
void QARApplyDeviceNamePage(WKWebView *view) {
    if (!NSThread.isMainThread || !target(view.URL)) return;
    NSString *owner = objc_getAssociatedObject(view, &ownerKey);
    NSString *uin = [owner isEqual:QARCurrentOwner()] ? accountID() : nil;
    NSDictionary *config = uin ? @{@"text":customName(), @"uin":uin} : @{};
    NSString *script = QARDeviceNameScript(config);
    if (script) [view evaluateJavaScript:script completionHandler:nil];
}
void QARPrepareDeviceNamePage(WKWebView *view) {
    if (!NSThread.isMainThread || !view) return;
    if (!views) views = [NSHashTable weakObjectsHashTable];
    [views addObject:view];
    objc_setAssociatedObject(view, &ownerKey, QARCurrentOwner(), OBJC_ASSOCIATION_COPY_NONATOMIC);
    WKUserContentController *controller = view.configuration.userContentController;
    if (objc_getAssociatedObject(controller, &controllerKey)) return;
    @try {
        QARDeviceReceiptHandler *handler = [QARDeviceReceiptHandler new];
        [controller addScriptMessageHandler:handler name:@"QARDeviceNameReceipt"];
        WKUserScript *script = [[WKUserScript alloc] initWithSource:QARDeviceNameScript(@{})
            injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
        [controller addUserScript:script];
        objc_setAssociatedObject(controller, &controllerKey, handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @catch (__unused NSException *exception) { preparationFailures++; }
}
NSDictionary *QARDeviceNameStatus(void) {
    NSDictionary *latest = [receiptOwner isEqual:QARCurrentOwner()] ? receipt : nil;
    return @{@"configured": @(customName().length > 0), @"submission_implemented": @YES,
        @"mode": @"official_page_paired_model_adapter", @"friend_visible_verified": @NO,
        @"receipt": latest ?: @{}, @"preparation_failures": @(preparationFailures),
        @"captures_cookies": @NO, @"diagnostics_include_name": @NO,
        @"diagnostics_include_request_parameters": @NO};
}
@interface QARDeviceInputLimit : NSObject <UITextFieldDelegate> @end
@implementation QARDeviceInputLimit
- (BOOL)textField:(UITextField *)field shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)text {
    return [[(field.text ?: @"") stringByReplacingCharactersInRange:range withString:text] length] <= 256;
}
@end
void QARPresentDeviceNameEditor(UIViewController *presenter) {
    if (!presenter || !NSThread.isMainThread) return;
    NSString *owner = QARCurrentOwner(); if (!owner) return;
    UIAlertController *editor = [UIAlertController alertControllerWithTitle:@"自定义机型"
        message:@"替换机型本身，保留官方自定义文字。填写后回到 QQ 的“自定义设备名”页面，点击 QQ 自己的保存按钮提交。服务器接受后，请让好友确认显示。实际允许的文字以 QQ 返回为准。"
        preferredStyle:UIAlertControllerStyleAlert];
    [editor addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = customName(); field.placeholder = @"输入想显示的机型";
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    QARDeviceInputLimit *inputLimit = [QARDeviceInputLimit new];
    objc_setAssociatedObject(editor, &editorKey, inputLimit, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    editor.textFields.firstObject.delegate = inputLimit;
    editor.textFields.firstObject.autocorrectionType = UITextAutocorrectionTypeNo;
    editor.textFields.firstObject.autocapitalizationType = UITextAutocapitalizationTypeNone;
    __weak UIAlertController *weakEditor = editor;
    [editor addAction:[UIAlertAction actionWithTitle:@"保存到插件" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *text = weakEditor.textFields.firstObject.text ?: @"";
        if (![owner isEqual:QARCurrentOwner()] || text.length > 256) return;
        NSString *key = preferenceKey(); if (!key) return;
        if (text.length) [NSUserDefaults.standardUserDefaults setObject:text forKey:key];
        else [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
        receipt = nil; receiptOwner = nil;
        for (WKWebView *view in views.allObjects) QARApplyDeviceNamePage(view);
    }]];
    [editor addAction:[UIAlertAction actionWithTitle:@"关闭自定义覆盖" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        if (![owner isEqual:QARCurrentOwner()]) return;
        NSString *key = preferenceKey(); if (key) [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
        receipt = nil; receiptOwner = nil;
        for (WKWebView *view in views.allObjects) QARApplyDeviceNamePage(view);
    }]];
    [editor addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:editor animated:YES completion:nil];
}
