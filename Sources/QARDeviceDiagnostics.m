#import "QARDeviceDiagnostics.h"
#import "QARAdapter.h"
#import "QARHook.h"
#import <WebKit/WebKit.h>
#include <stdatomic.h>
static IMP original;
static QARHookResult result = QARHookMissingClass;
static atomic_ullong pageLoads, observations;
static NSArray *assets;
static BOOL devicePage(NSURL *url) {
    return [url.scheme.lowercaseString isEqual:@"https"] && [url.host.lowercaseString isEqual:@"club.vip.qq.com"] &&
        [url.path isEqual:@"/onlinestatus/set"];
}
NSArray<NSString *> *QARDevicePublicAssets(id values) {
    if (![values isKindOfClass:NSArray.class]) return @[];
    NSMutableOrderedSet *safe = [NSMutableOrderedSet new];
    for (id value in values) {
        if (safe.count >= 32) break;
        if (![value isKindOfClass:NSString.class] || [value length] > 2048) continue;
        NSURLComponents *url = [NSURLComponents componentsWithString:value];
        NSString *host = url.host.lowercaseString;
        if (![url.scheme.lowercaseString isEqual:@"https"] || url.user.length || url.password.length ||
            !([host hasSuffix:@".qq.com"] || [host hasSuffix:@".gtimg.cn"] || [host hasSuffix:@".qpic.cn"]) ||
            ![url.path.lowercaseString hasSuffix:@".js"] || url.path.length > 512) continue;
        url.query = nil; url.fragment = nil;
        if (url.string) [safe addObject:url.string];
    }
    return safe.array;
}
static id loadRequest(WKWebView *view, SEL cmd, NSURLRequest *request) {
    id navigation = ((id (*)(id, SEL, id))original)(view, cmd, request);
    if (!NSThread.isMainThread || !devicePage(request.URL)) return navigation;
    atomic_fetch_add(&pageLoads, 1);
    __weak WKWebView *weakView = view;
    for (NSNumber *delay in @[@2, @5, @10]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay.longLongValue * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            WKWebView *strongView = weakView;
            if (!strongView || !devicePage(strongView.URL)) return;
            [strongView evaluateJavaScript:@"Array.from(document.scripts).map(s => s.src).filter(Boolean).slice(0,64)"
                completionHandler:^(id values, NSError *error) {
                    if (error || !devicePage(weakView.URL)) return;
                    atomic_fetch_add(&observations, 1);
                    NSArray *sanitized = QARDevicePublicAssets(values);
                    if (sanitized.count) assets = sanitized;
                }];
        });
    }
    return navigation;
}
void QARInstallDeviceDiagnostics(NSDictionary *info) {
    if (!QARVersionSupported(info) || original) return;
    result = QARInstallHook(WKWebView.class, @selector(loadRequest:), "@24@0:8@16", (IMP)loadRequest, &original);
}
NSDictionary *QARDeviceDiagnosticsStatus(void) {
    return @{@"submission_implemented": @NO, @"friend_visible_verified": @NO,
        @"page_loads": @(atomic_load(&pageLoads)), @"page_observations": @(atomic_load(&observations)),
        @"public_script_assets": assets ?: @[], @"hook_result": @(result),
        @"captures_cookies": @NO, @"captures_request_parameters": @NO};
}
