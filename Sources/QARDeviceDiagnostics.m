#import "QARDeviceDiagnostics.h"
#import "QARAdapter.h"
#import "QARHook.h"
#import <WebKit/WebKit.h>
#include <stdatomic.h>
static IMP original;
static QARHookResult result = QARHookMissingClass;
static atomic_ullong pageLoads, observations, evaluationErrors;
static NSDictionary *scanCounts;
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
            !([host hasSuffix:@".qq.com"] || [host hasSuffix:@".gtimg.cn"] || [host hasSuffix:@".qpic.cn"] || [host hasSuffix:@".gtimg.com"] || [host hasSuffix:@".idqqimg.com"]) ||
            !([url.path.lowercaseString hasSuffix:@".js"] || [url.path.lowercaseString hasSuffix:@".mjs"]) || url.path.length > 512) continue;
        url.query = nil; url.fragment = nil;
        if (url.string) [safe addObject:url.string];
    }
    return safe.array;
}
NSString *QARDeviceDiagnosticScript(void) {
    return @"(()=>{const out={assets:[],script_tags:0,inline_scripts:0,resource_entries:0,frames_scanned:0,frames_unavailable:0};"
    "const seen=new Set();function add(s){if(typeof s==='string'&&s.length<=2048&&!seen.has(s)&&out.assets.length<256){seen.add(s);out.assets.push(s);}}"
    "function scan(w,depth){if(depth>1||out.frames_scanned>=9)return;"
    "try{if(w.location.origin!==window.location.origin){out.frames_unavailable++;return;}"
    "const scripts=Array.from(w.document.scripts).slice(0,256);out.frames_scanned++;out.script_tags+=scripts.length;"
    "scripts.forEach(s=>{if(s.src)add(s.src);else out.inline_scripts++;});"
    "const entries=w.performance.getEntriesByType('resource').slice(-512);out.resource_entries+=entries.length;"
    "entries.forEach(e=>{if(typeof e.name==='string'&&/\\.(?:m?js)$/i.test(e.name.split(/[?#]/)[0]))add(e.name);});"
    "for(let i=0;i<Math.min(w.frames.length,8);i++)scan(w.frames[i],depth+1);"
    "}catch(_){out.frames_unavailable++;}}scan(window,0);return out;})()";
}
void QARDeviceRecordObservation(id value) {
    if (![value isKindOfClass:NSDictionary.class] || ![value[@"assets"] isKindOfClass:NSArray.class]) return;
    atomic_fetch_add(&observations, 1);
    NSArray *candidates = value[@"assets"];
    NSArray *sanitized = QARDevicePublicAssets(candidates);
    NSMutableDictionary *counts = [NSMutableDictionary new];
    for (NSString *key in @[@"script_tags", @"inline_scripts", @"resource_entries", @"frames_scanned", @"frames_unavailable"]) {
        id number = value[key];
        counts[key] = [number isKindOfClass:NSNumber.class] ? @(MIN(100000, MAX(0, [number longLongValue]))) : @0;
    }
    counts[@"candidate_urls"] = @(candidates.count);
    counts[@"accepted_assets"] = @(sanitized.count);
    scanCounts = counts;
    if (sanitized.count) {
        NSMutableOrderedSet *combined = [NSMutableOrderedSet orderedSetWithArray:assets ?: @[]];
        [combined addObjectsFromArray:sanitized];
        assets = [combined.array subarrayWithRange:NSMakeRange(0, MIN(32, combined.count))];
    }
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
            [strongView evaluateJavaScript:QARDeviceDiagnosticScript()
                completionHandler:^(id values, NSError *error) {
                    if (!devicePage(weakView.URL)) return;
                    if (error) { atomic_fetch_add(&evaluationErrors, 1); return; }
                    QARDeviceRecordObservation(values);
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
        @"collector_version": @2, @"last_scan_counts": scanCounts ?: @{},
        @"evaluation_errors": @(atomic_load(&evaluationErrors)), @"public_script_assets": assets ?: @[], @"hook_result": @(result),
        @"captures_cookies": @NO, @"captures_request_parameters": @NO};
}
