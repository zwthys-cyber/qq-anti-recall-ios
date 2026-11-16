#import "QARAdapter.h"
#import "QARHook.h"
#import "QARTrace.h"
#import "QARIncoming.h"
#import "QARUpdateFilter.h"
#import "QARStore.h"
#import "QARHistory.h"
#include <stdatomic.h>
#include <stdbool.h>

static atomic_bool enabled = true;
static atomic_uint_fast64_t ntEvents, uiEvents, preventedFlags;
static IMP ntOriginal, uiOriginal, flagOriginal;
static NSDictionary *hostInfo;
static NSMutableDictionary<NSString *, NSNumber *> *results;
static BOOL configured;
static NSString * const preference = @"QQAntiRecall.Enabled";

BOOL QARVersionSupported(NSDictionary *info) {
    return [info[@"CFBundleShortVersionString"] isEqual:@"9.3.86"] &&
           [info[@"CFBundleVersion"] isEqual:@"9.3.86.617"] &&
           [info[@"CFBundleExecutable"] isEqual:@"QQ"];
}
BOOL QAREnabled(void) { return atomic_load(&enabled); }
void QARSetEnabled(BOOL value) {
    atomic_store(&enabled, value);
    [NSUserDefaults.standardUserDefaults setBool:value forKey:preference];
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:QARStoreChangedNotification object:nil];
    });
}
static void onKernelRecall(id self, SEL cmd, int chatType, id peerUid, unsigned long long seq) {
    if (QAREnabled()) {
        atomic_fetch_add(&ntEvents, 1);
        QARTraceEvent(@"kernel_recall");
        return;
    }
    ((void (*)(id, SEL, int, id, unsigned long long))ntOriginal)(self, cmd, chatType, peerUid, seq);
}
static void onUIRecall(id self, SEL cmd, id notification) {
    if (QAREnabled()) {
        atomic_fetch_add(&uiEvents, 1);
        QARTraceEvent(@"ui_recall");
        return;
    }
    ((void (*)(id, SEL, id))uiOriginal)(self, cmd, notification);
}
static void setRecallTime(id self, SEL cmd, long long value) {
    if (value > 0) {
        atomic_fetch_add(&preventedFlags, 1);
        QARTraceEvent(@"positive_recall_time_observed");
    }
    // A timestamp is not the message content. Clearing it alone did not preserve the
    // message in the reported single-chat test.
    ((void (*)(id, SEL, long long))flagOriginal)(self, cmd, value);
}
static void install(NSString *className, NSString *selector, const char *types,
                    IMP replacement, IMP *original) {
    if (*original) return;
    QARHookResult result = QARInstallHook(NSClassFromString(className),
        NSSelectorFromString(selector), types, replacement, original);
    results[[className stringByAppendingFormat:@" -%@", selector]] = @(result);
}
static BOOL preflight(NSString *className, NSString *selector, const char *types) {
    Class cls = NSClassFromString(className);
    Method method = cls ? class_getInstanceMethod(cls, NSSelectorFromString(selector)) : NULL;
    QARHookResult result = !cls ? QARHookMissingClass : !method ? QARHookMissingMethod :
        QARSignaturesMatch(method_getTypeEncoding(method), types) ? QARHookInstalled : QARHookSignatureMismatch;
    results[[className stringByAppendingFormat:@" -%@", selector]] = @(result);
    return result == QARHookInstalled;
}
void QARInstallAdapters(NSDictionary *info) {
    hostInfo = [info copy];
    if (!QARVersionSupported(info)) return;
    if (!configured) {
        configured = YES;
        results = [NSMutableDictionary new];
        [NSUserDefaults.standardUserDefaults registerDefaults:@{preference: @YES}];
        atomic_store(&enabled, [NSUserDefaults.standardUserDefaults boolForKey:preference]);
    }
    QARInstallIncoming(info);
    QARInstallHistory(info);
    if (ntOriginal && uiOriginal && flagOriginal) return;
    BOOL ready = preflight(@"KTIKernelMsgListener", @"onMsgRecall:peerUid:seq:", "v36@0:8i16@20Q28");
    ready &= preflight(@QAR_UI_RECALL_CLASS, @"onRecvRecallMsg:", "v24@0:8@16");
    ready &= preflight(@"OCMsgRecord", @"setRecallTime:", "v24@0:8q16");
    if (!ready) return;
    install(@"KTIKernelMsgListener", @"onMsgRecall:peerUid:seq:",
            "v36@0:8i16@20Q28", (IMP)onKernelRecall, &ntOriginal);
    // This receiver is enabled only when its version-specific metadata is verified.
#ifdef QAR_HAS_UI_RECALL
    install(@QAR_UI_RECALL_CLASS, @"onRecvRecallMsg:",
            "v24@0:8@16", (IMP)onUIRecall, &uiOriginal);
#else
    (void)onUIRecall;
#endif
    install(@"OCMsgRecord", @"setRecallTime:", "v24@0:8q16",
            (IMP)setRecallTime, &flagOriginal);
}
void QARResetDiagnostics(void) {
    atomic_store(&ntEvents, 0);
    atomic_store(&uiEvents, 0);
    atomic_store(&preventedFlags, 0);
    QARResetIncoming();
    QARResetUpdateFilter();
    QARResetStoreCounters();
    QARResetHistoryCounters();
    QARResetTrace();
}
NSDictionary *QARStatus(void) {
    NSDictionary *incoming = QARIncomingStatus();
    NSDictionary *history = QARHistoryStatus();
    NSMutableDictionary *allResults = [results mutableCopy] ?: [NSMutableDictionary new];
    [allResults addEntriesFromDictionary:incoming[@"hook_results"]];
    [allResults addEntriesFromDictionary:history[@"hook_results"]];
    NSUInteger installed = (ntOriginal != NULL) + (uiOriginal != NULL) + (flagOriginal != NULL) + [incoming[@"installed_hooks"] unsignedIntegerValue] + [history[@"installed_hooks"] unsignedIntegerValue];
    return @{
        @"plugin_version": @"0.8.1-experimental",
        @"short_version": hostInfo[@"CFBundleShortVersionString"] ?: @"",
        @"build_version": hostInfo[@"CFBundleVersion"] ?: @"",
        @"supported_version": @(QARVersionSupported(hostInfo ?: @{})),
        @"enabled": @(QAREnabled()),
        @"installed_hooks": @(installed),
        @"hook_results": [allResults copy],
        @"incoming_hook_calls": incoming[@"hook_calls"],
        @"update_filter": QARUpdateFilterStatus(),
        @"message_store": QARStoreStatus(),
        @"history_hook_calls": history[@"hook_calls"],
        @"history_hook_still_active": history[@"hook_still_active"],
        @"incoming_suppressed_calls": incoming[@"suppressed_calls"],
        @"incoming_hook_still_active": incoming[@"hook_still_active"],
        @"intercepted_events": @(atomic_load(&ntEvents) + atomic_load(&uiEvents) + [incoming[@"intercepted_events"] unsignedLongLongValue]),
        @"kernel_recall_events": @(atomic_load(&ntEvents)),
        @"ui_recall_events": @(atomic_load(&uiEvents)),
        @"prevented_recall_flag_writes": @0,
        @"positive_recall_time_writes": @(atomic_load(&preventedFlags)),
        @"trace_samples": QARTraceSnapshot(),
        @"runtime_qq_verified": @NO,
        @"records_message_contents": @YES
    };
}
