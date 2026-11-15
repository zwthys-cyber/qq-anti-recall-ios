#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "QARIncoming.h"
#import "QARAdapter.h"
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>

static NSUInteger recalls, received, updated, deleted, parsed, inout, codecs;
static int receivedType, parseLength, parseCommand;
static unsigned long long receivedSeq;
static id object1, object2;
static const void *parseBytes;
static void *parseModel;
static void check(BOOL ok, const char *why) {
    if (!ok) { fprintf(stderr, "FAIL: %s\n", why); exit(1); }
}
static void recallFixture(id self, SEL cmd, int type, id peer, unsigned long long seq) {
    (void)self; (void)cmd; recalls++; receivedType = type; object1 = peer; receivedSeq = seq;
}
static void receiveFixture(id self, SEL cmd, id messages) {
    (void)self; (void)cmd; received++; object1 = messages;
}
static void updateFixture(id self, SEL cmd, id messages) {
    (void)self; (void)cmd; updated++; object1 = messages;
}
static void deleteFixture(id self, SEL cmd, id contact, id ids) {
    (void)self; (void)cmd; deleted++; object1 = contact; object2 = ids;
}
static BOOL parseFixture(id self, SEL cmd, const void *bytes, int length, int subcommand, void *model) {
    (void)self; (void)cmd; parsed++; parseBytes = bytes; parseLength = length;
    parseCommand = subcommand; parseModel = model;
    *(int *)model = 1234;
    return YES;
}
static void inoutFixture(id self, SEL cmd, void *model) {
    (void)self; (void)cmd; inout++; parseModel = model;
}
static void codecFixture(id self, SEL cmd, id value) {
    (void)self; (void)cmd; codecs++; object1 = value;
}
static Class makeClass(const char *name) {
    Class cls = objc_allocateClassPair(NSObject.class, name, 0);
    check(cls != Nil, "create independent synthetic receiver");
    return cls;
}
int main(int argc, const char *argv[]) {
    (void)argv;
    @autoreleasepool {
        NSDictionary *info = @{@"CFBundleShortVersionString": @"9.3.86",
            @"CFBundleVersion": @"9.3.86.617", @"CFBundleExecutable": @"QQ"};
        SEL recall = sel_registerName("onMsgRecall:peerUid:seq:");
        SEL receive = sel_registerName("onRecvMsg:");
        SEL update = sel_registerName("onMsgInfoListUpdate:");
        SEL deletion = sel_registerName("onMsgDelete:msgIds:");
        SEL parse = sel_registerName("parseC2CRecallNotify:bufferLen:subcmd:model:");
        SEL inoutSEL = sel_registerName("parseC2CRecallInOut:");
        SEL codec = sel_registerName("setKt_recallTimeFromCodec:");
        Class swi = makeClass("_TtC13GuildNTKernel20SWIKernelMsgListener");
        class_addMethod(swi, recall, (IMP)recallFixture, "v36@0:8i16@20Q28");
        // The mismatch invocation runs in a separate process and never calls this method.
        class_addMethod(swi, receive, (IMP)receiveFixture, argc > 1 ? "v32@0:8@16@24" : "v24@0:8@16");
        class_addMethod(swi, update, (IMP)updateFixture, "v24@0:8@16");
        class_addMethod(swi, deletion, (IMP)deleteFixture, "v32@0:8@16@24");
        objc_registerClassPair(swi);
        Class net = makeClass("QQMessageRecallNetEngine");
        class_addMethod(net, parse, (IMP)parseFixture, "B40@0:8r^v16i24i28^{RecallModel=}32");
        objc_registerClassPair(net);
        Class package = makeClass("QQMessageRecallPackageHandler");
        class_addMethod(object_getClass(package), parse, (IMP)parseFixture, "B40@0:8r^v16i24i28^v32");
        class_addMethod(object_getClass(package), inoutSEL, (IMP)inoutFixture, "v24@0:8^v16");
        objc_registerClassPair(package);
        Class record = makeClass("OCMsgRecord");
        class_addMethod(record, codec, (IMP)codecFixture, "v24@0:8@16");
        objc_registerClassPair(record);
        NSMutableDictionary *wrong = [info mutableCopy];
        wrong[@"CFBundleVersion"] = @"9.3.86.618";
        QARInstallIncoming(wrong);
        check([QARIncomingStatus()[@"installed_hooks"] unsignedIntegerValue] == 0, "exact build gate on extra adapters");
        QARInstallIncoming(info);
        if (argc > 1) {
            check([QARIncomingStatus()[@"installed_hooks"] unsignedIntegerValue] == 7, "incompatible ABI is not installed");
            NSString *receiveKey = @"_TtC13GuildNTKernel20SWIKernelMsgListener -onRecvMsg:";
            check([QARIncomingStatus()[@"hook_results"][receiveKey] integerValue] == 3, "mismatch is explicit");
            puts("PASS: incompatible incoming observer ABI rejected.");
            return 0;
        }
        QARInstallIncoming(info);
        check([QARIncomingStatus()[@"installed_hooks"] unsignedIntegerValue] == 8, "compatible retry is idempotent");
        check(class_getInstanceMethod(package, parse) == NULL, "parser hook stays on the metaclass");

        id listener = [swi new], engine = [net new], model = [record new];
        id messages = @[@"synthetic private text"], peer = @"synthetic private peer", ids = @[@7];
        QARSetEnabled(NO);
        ((void (*)(id, SEL, int, id, unsigned long long))objc_msgSend)(listener, recall, INT_MAX, peer, ULLONG_MAX);
        check(recalls == 1 && receivedType == INT_MAX && object1 == peer && receivedSeq == ULLONG_MAX,
              "disabled SWI recall preserves widths and identity");
        int output = 77;
        const char bytes[] = "synthetic packet";
        BOOL ok = ((BOOL (*)(id, SEL, const void *, int, int, void *))objc_msgSend)(engine, parse, bytes, INT_MAX, INT_MIN, &output);
        check(ok && output == 1234 && parseBytes == bytes && parseLength == INT_MAX &&
              parseCommand == INT_MIN && parseModel == &output, "disabled parser preserves pointers, signed integers and return value");
        output = 77;
        ok = ((BOOL (*)(id, SEL, const void *, int, int, void *))objc_msgSend)(package, parse, bytes, 3, 4, &output);
        check(ok && output == 1234 && parsed == 2, "class parser is forwarded while disabled");
        ((void (*)(id, SEL, void *))objc_msgSend)(package, inoutSEL, &output);
        check(inout == 1 && parseModel == &output, "in/out parser preserves pointer");

        QARSetEnabled(YES);
        ((void (*)(id, SEL, int, id, unsigned long long))objc_msgSend)(listener, recall, 1, peer, 9);
        check(recalls == 1, "enabled incoming SWI recall is suppressed");
        for (id receiver in @[engine, package]) {
            output = 77;
            ok = ((BOOL (*)(id, SEL, const void *, int, int, void *))objc_msgSend)(receiver, parse, bytes, 3, 4, &output);
            check(!ok && output == 77 && parsed == 2, "suppressed parser leaves output storage untouched");
        }
        ((void (*)(id, SEL, void *))objc_msgSend)(package, inoutSEL, &output);
        check(inout == 1, "enabled incoming in/out parser is suppressed");
        for (NSNumber *enabled in @[@YES, @NO]) {
            QARSetEnabled(enabled.boolValue);
            ((void (*)(id, SEL, id))objc_msgSend)(listener, receive, messages);
            check(object1 == messages, "ordinary receive arguments preserved");
            ((void (*)(id, SEL, id))objc_msgSend)(listener, update, messages);
            check(object1 == messages, "ordinary update arguments preserved");
            ((void (*)(id, SEL, id, id))objc_msgSend)(listener, deletion, peer, ids);
            check(object1 == peer && object2 == ids, "ordinary deletion is never suppressed");
            ((void (*)(id, SEL, id))objc_msgSend)(model, codec, @LLONG_MAX);
            check([object1 longLongValue] == LLONG_MAX, "boxed codec value is forwarded unchanged");
        }
        check(received == 2 && updated == 2 && deleted == 2 && codecs == 2, "observer paths forward in both modes");
        NSDictionary *status = QARIncomingStatus();
        check([status[@"intercepted_events"] unsignedLongLongValue] == 4, "only four explicit recall calls counted as suppressed");
        for (NSNumber *active in [status[@"hook_still_active"] allValues])
            check(active.boolValue, "installed replacements are still active");
        class_replaceMethod(swi, update, (IMP)updateFixture, "v24@0:8@16");
        check(![QARIncomingStatus()[@"hook_still_active"][@"_TtC13GuildNTKernel20SWIKernelMsgListener -onMsgInfoListUpdate:"] boolValue],
              "later replacement is visible in diagnostics");
        NSData *json = [NSJSONSerialization dataWithJSONObject:QARStatus() options:0 error:nil];
        NSString *diagnostic = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
        check(![diagnostic containsString:@"synthetic private"] && ![diagnostic containsString:@"synthetic packet"],
              "no messages, peers or packet bytes enter diagnostics");
        QARResetDiagnostics();
        check([QARIncomingStatus()[@"intercepted_events"] unsignedLongLongValue] == 0, "reset clears new counters");
        puts("PASS: extra incoming adapters, exact ABI, metaclass isolation, pass-through, integrity and privacy.");
    }
    return 0;
}
