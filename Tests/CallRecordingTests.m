#import <Foundation/Foundation.h>
#import <objc/message.h>
#import "QARCallRecording.h"
#import "QARHook.h"
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static NSUInteger sent, localStarts, localStops, peerUpdates, pendingAcks;
static int lastState;
static void sender(id self, SEL cmd, int state) { (void)self; (void)cmd; sent++; lastState = state; }
static void wrongSender(id self, SEL cmd, long long state) { (void)self; (void)cmd; sent++; lastState = (int)state; }
// Mirror only the statically observed routing: start -> notify(1), end ->
// notify(8), notify -> sender followed by ACK bookkeeping for 1/3/5.
static void notify(id self, SEL cmd, int state) {
    (void)cmd;
    ((void (*)(id, SEL, int))objc_msgSend)(self, NSSelectorFromString(@"sendRecordState:"), state);
    if (state == 1 || state == 3 || state == 5) pendingAcks++;
}
static BOOL start(id self, SEL cmd) {
    (void)cmd; localStarts++;
    ((void (*)(id, SEL, int))objc_msgSend)(self, NSSelectorFromString(@"notifyPeerRecordState:"), 1);
    return YES;
}
static void stop(id self, SEL cmd) {
    (void)cmd; localStops++;
    ((void (*)(id, SEL, int))objc_msgSend)(self, NSSelectorFromString(@"notifyPeerRecordState:"), 8);
}
static void receive(id self, SEL cmd, int state) { (void)self; (void)cmd; (void)state; peerUpdates++; }
static void check(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static void send(id receiver, int state) {
    ((void (*)(id, SEL, int))objc_msgSend)(receiver, NSSelectorFromString(@"sendRecordState:"), state);
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *mode = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"normal";
        NSDictionary *info = @{@"CFBundleShortVersionString": @"9.3.86",
            @"CFBundleVersion": @"9.3.86.617", @"CFBundleExecutable": @"QQ"};
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"QARCallRecordingSuppressionEnabled"];
        check(!QARCallRecordingSuppressionEnabled(), "new feature defaults off");
        QARSetCallRecordingSuppressionEnabled(YES);
        check([NSUserDefaults.standardUserDefaults boolForKey:@"QARCallRecordingSuppressionEnabled"], "persist independent preference");

        if ([mode isEqual:@"missing-class"]) {
            QARInstallCallRecording(info);
            check([QARCallRecordingStatus()[@"hook_result"] integerValue] == QARHookMissingClass, "missing class rejected");
            check([QARCallRecordingStatus()[@"installed_hooks"] intValue] == 0, "missing class installs nothing");
            return 0;
        }
        Class cls = objc_allocateClassPair(NSObject.class, "QQRTCP2PRecordPart", 0);
        check(cls != Nil, "allocate call fixture");
        if (![mode isEqual:@"missing-method"]) {
            BOOL wrong = [mode isEqual:@"wrong-abi"];
            class_addMethod(cls, NSSelectorFromString(@"sendRecordState:"),
                wrong ? (IMP)wrongSender : (IMP)sender, wrong ? "v24@0:8q16" : "v20@0:8i16");
        }
        class_addMethod(cls, NSSelectorFromString(@"onRecordStart"), (IMP)start, "B16@0:8");
        class_addMethod(cls, NSSelectorFromString(@"notifyPeerRecordState:"), (IMP)notify, "v20@0:8i16");
        class_addMethod(cls, NSSelectorFromString(@"stopRecord"), (IMP)stop, "v16@0:8");
        class_addMethod(cls, NSSelectorFromString(@"handlePeerRecordState:"), (IMP)receive, "v20@0:8i16");
        objc_registerClassPair(cls);
        id receiver = [cls new];
        IMP before = class_getMethodImplementation(cls, NSSelectorFromString(@"sendRecordState:"));
        if ([mode isEqual:@"wrong-version"] || [mode isEqual:@"wrong-build"] || [mode isEqual:@"wrong-executable"]) {
            NSMutableDictionary *wrong = [info mutableCopy];
            NSString *key = [mode isEqual:@"wrong-version"] ? @"CFBundleShortVersionString" :
                [mode isEqual:@"wrong-build"] ? @"CFBundleVersion" : @"CFBundleExecutable";
            wrong[key] = @"unsupported";
            QARInstallCallRecording(wrong);
            check([QARCallRecordingStatus()[@"installed_hooks"] intValue] == 0, "unsupported host installs nothing");
            check(class_getMethodImplementation(cls, NSSelectorFromString(@"sendRecordState:")) == before, "unsupported host preserves IMP");
            send(receiver, INT_MIN);
            check(sent == 1 && lastState == INT_MIN, "unsupported host preserves notifications");
            return 0;
        }
        QARInstallCallRecording(info);
        if ([mode isEqual:@"wrong-abi"] || [mode isEqual:@"missing-method"]) {
            QARHookResult expected = [mode isEqual:@"wrong-abi"] ? QARHookSignatureMismatch : QARHookMissingMethod;
            check([QARCallRecordingStatus()[@"hook_result"] integerValue] == expected, "invalid target rejected");
            check([QARCallRecordingStatus()[@"installed_hooks"] intValue] == 0, "invalid target installs nothing");
            check(class_getMethodImplementation(cls, NSSelectorFromString(@"sendRecordState:")) == before, "rejection preserves IMP");
            if ([mode isEqual:@"wrong-abi"]) {
                ((void (*)(id, SEL, long long))objc_msgSend)(receiver, NSSelectorFromString(@"sendRecordState:"), 7);
                check(sent == 1 && lastState == 7, "ABI rejection preserves behavior");
            }
            return 0;
        }
        check([QARCallRecordingStatus()[@"hook_active"] boolValue], "sender hook active");
        QARInstallCallRecording(info);
        check([QARCallRecordingStatus()[@"installed_hooks"] intValue] == 1, "repeat installation is idempotent");
        // All recording states, including start/end, direct calls and retries.
        int states[] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, INT_MIN, INT_MAX};
        for (NSUInteger i=0; i<sizeof(states)/sizeof(states[0]); i++) send(receiver, states[i]);
        check(sent == 0 && [QARCallRecordingStatus()[@"suppressed_notifications"] intValue] == 12, "suppress every outbound recording state");
        check(((BOOL (*)(id, SEL))objc_msgSend)(receiver, NSSelectorFromString(@"onRecordStart")), "local recording still reports success");
        ((void (*)(id, SEL, int))objc_msgSend)(receiver, NSSelectorFromString(@"handlePeerRecordState:"), 1);
        ((void (*)(id, SEL))objc_msgSend)(receiver, NSSelectorFromString(@"stopRecord"));
        check(localStarts == 1 && localStops == 1 && peerUpdates == 1 && pendingAcks == 1, "local recording, bookkeeping and incoming methods remain callable");
        check(sent == 0 && [QARCallRecordingStatus()[@"suppressed_notifications"] intValue] == 14, "both start(1) and end(8) routes suppress notifications");
        QARSetCallRecordingSuppressionEnabled(NO);
        for (NSUInteger i=0; i<sizeof(states)/sizeof(states[0]); i++) {
            send(receiver, states[i]); check(lastState == states[i], "disabled forwards exact signed 32-bit state");
        }
        check(sent == 12 && [QARCallRecordingStatus()[@"forwarded_notifications"] intValue] == 12, "disabled forwards once per call");
        ((BOOL (*)(id, SEL))objc_msgSend)(receiver, NSSelectorFromString(@"onRecordStart"));
        check(sent == 13 && lastState == 1 && localStarts == 2, "disabled start records and sends original reminder");
        ((void (*)(id, SEL))objc_msgSend)(receiver, NSSelectorFromString(@"stopRecord"));
        check(sent == 14 && lastState == 8 && localStops == 2, "disabled end stops recording and sends original reminder");
        QARSetCallRecordingSuppressionEnabled(YES); send(receiver, 1);
        check(sent == 14, "re-enable immediately suppresses start state");
        QARResetCallRecordingCounters();
        check([QARCallRecordingStatus()[@"sender_calls"] intValue] == 0 &&
            [QARCallRecordingStatus()[@"suppressed_notifications"] intValue] == 0 &&
            [QARCallRecordingStatus()[@"forwarded_notifications"] intValue] == 0, "reset counters");
        check(![QARCallRecordingStatus()[@"runtime_qq_verified"] boolValue] &&
            ![QARCallRecordingStatus()[@"friend_visible_verified"] boolValue], "fixtures never claim real QQ verification");
        puts("PASS: call recording sender suppression, passthrough, exact host/ABI guards and isolation.");
    }
    return 0;
}
