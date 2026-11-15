#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "QARAdapter.h"
#import "QARTrace.h"
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>

static NSUInteger forwarded, uiForwarded, sent;
static int receivedType;
static id receivedPeer;
static unsigned long long receivedSeq;

@interface KTIKernelMsgListener : NSObject
- (void)onMsgRecall:(int)chatType peerUid:(id)peerUid seq:(unsigned long long)seq;
- (void)sendRecall;
@end
@implementation KTIKernelMsgListener
- (void)onMsgRecall:(int)chatType peerUid:(id)peerUid seq:(unsigned long long)seq {
    forwarded++; receivedType = chatType; receivedPeer = peerUid; receivedSeq = seq;
}
- (void)sendRecall { sent++; }
@end
@interface OCMsgRecord : NSObject
@property(nonatomic) long long recallTime;
@end
@implementation OCMsgRecord
@end
static void uiOriginalFixture(id self, SEL cmd, id note) {
    (void)self; (void)cmd; (void)note; uiForwarded++;
}
static void check(BOOL value, const char *why) {
    if (!value) { fprintf(stderr, "FAIL: %s\n", why); exit(1); }
}
int main(void) {
    @autoreleasepool {
        NSDictionary *supported = @{
            @"CFBundleShortVersionString": @"9.3.86",
            @"CFBundleVersion": @"9.3.86.617",
            @"CFBundleExecutable": @"QQ"
        };
        NSMutableDictionary *wrong = [supported mutableCopy];
        wrong[@"CFBundleVersion"] = @"9.3.86.618";
        check(!QARVersionSupported(wrong), "exact build gate");
        wrong[@"CFBundleVersion"] = @"9.3.86.617";
        wrong[@"CFBundleExecutable"] = @"UnrelatedApp";
        check(!QARVersionSupported(wrong), "host executable gate");
        QARInstallAdapters(wrong);
        check([QARStatus()[@"installed_hooks"] integerValue] == 0, "unsupported target does not hook");
#ifdef QAR_HAS_UI_RECALL
        QARInstallAdapters(supported);
        check([QARStatus()[@"installed_hooks"] integerValue] == 0, "missing required UI receiver leaves all hooks uninstalled");
        Class uiClass = objc_allocateClassPair(NSObject.class, QAR_UI_RECALL_CLASS, 0);
        check(uiClass != Nil, "create synthetic UI receiver");
        class_addMethod(uiClass, NSSelectorFromString(@"onRecvRecallMsg:"), (IMP)uiOriginalFixture, "v@:@");
        objc_registerClassPair(uiClass);
#else
        (void)uiOriginalFixture;
#endif
        QARInstallAdapters(supported);
        NSUInteger expectedHooks = 2;
#ifdef QAR_HAS_UI_RECALL
        expectedHooks++;
#endif
        check([QARStatus()[@"installed_hooks"] unsignedIntegerValue] == expectedHooks, "expected verified interfaces installed");
        QARInstallAdapters(supported);
        check([QARStatus()[@"installed_hooks"] unsignedIntegerValue] == expectedHooks, "repeat initialization is idempotent");
        KTIKernelMsgListener *listener = [KTIKernelMsgListener new];
        OCMsgRecord *record = [OCMsgRecord new];
        QARSetEnabled(NO);
        [listener onMsgRecall:INT_MAX peerUid:@"synthetic-peer" seq:ULLONG_MAX];
        check(forwarded == 1 && receivedType == INT_MAX &&
              [receivedPeer isEqual:@"synthetic-peer"] && receivedSeq == ULLONG_MAX,
              "disabled callback preserves all argument widths and values");
        record.recallTime = LLONG_MAX;
        check(record.recallTime == LLONG_MAX, "disabled setter preserves value");
        QARSetEnabled(YES);
        [listener onMsgRecall:1 peerUid:nil seq:0];
        check(forwarded == 1, "enabled callback is suppressed");
        record.recallTime = 123456789;
        check(record.recallTime == 123456789, "timestamp alone does not erase recall state without preserving content");
        record.recallTime = -1;
        check(record.recallTime == -1, "non-recall sentinel preserved");
        [listener sendRecall];
        check(sent == 1, "outgoing recall method is untouched");
#ifdef QAR_HAS_UI_RECALL
        id receiver = [uiClass new];
        SEL callback = NSSelectorFromString(@"onRecvRecallMsg:");
        ((void (*)(id, SEL, id))objc_msgSend)(receiver, callback, nil);
        check(uiForwarded == 0, "enabled UI recall suppressed");
        QARSetEnabled(NO);
        ((void (*)(id, SEL, id))objc_msgSend)(receiver, callback, @"synthetic");
        check(uiForwarded == 1, "disabled UI callback forwarded");
        QARSetEnabled(YES);
#endif
        dispatch_apply(1000, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t i) {
            [listener onMsgRecall:2 peerUid:nil seq:i];
        });
        check([QARStatus()[@"kernel_recall_events"] unsignedLongLongValue] == 1001,
              "concurrent event counters are exact");
        NSData *json = [NSJSONSerialization dataWithJSONObject:QARStatus() options:0 error:nil];
        NSString *text = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
        check(![text containsString:@"synthetic-peer"], "diagnostics contain no peer IDs");
        check(![QARStatus()[@"runtime_qq_verified"] boolValue], "fixture success is not QQ runtime proof");
        QARResetDiagnostics();
        check([QARStatus()[@"kernel_recall_events"] unsignedLongLongValue] == 0 &&
              [QARStatus()[@"positive_recall_time_writes"] unsignedLongLongValue] == 0 &&
              [QARStatus()[@"trace_samples"] count] == 0, "reset isolates the next device experiment");
        dispatch_apply(500, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t i) {
            if (i % 17 == 0) QARResetTrace();
            QARTraceEvent(@"synthetic_bounded_event");
        });
        check(QARTraceSnapshot().count <= 2, "trace remains bounded across concurrent reset and capture");
        for (NSDictionary *sample in QARTraceSnapshot()) {
            check(sample.count <= 3 && sample[@"event"] && sample[@"qq_image_offsets"],
                  "trace exports only controlled event metadata");
        }
        puts("PASS: exact build gates, recall adapters, full-width forwarding, concurrency, privacy.");
    }
    return 0;
}
