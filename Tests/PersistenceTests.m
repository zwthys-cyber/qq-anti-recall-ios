#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "QARSnapshot.h"
#import "QARStore.h"
#import "QARHistory.h"
#import "QARAdapter.h"
#import "QARBadgeRecord.h"
#import "ModelFixtures.h"
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>

static void check(BOOL ok, const char *message) {
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static NSArray *lastMessages;
static id lastError;
static int lastCode;
static BOOL lastMore;
static long long lastStatus;
static unsigned int lastQuery;
static void first(id self, SEL cmd, int code, id error, id messages, BOOL more) {
    (void)self; (void)cmd; lastCode = code; lastError = error; lastMessages = messages; lastMore = more;
}
static void status(id self, SEL cmd, int code, id error, long long value, id messages) {
    (void)self; (void)cmd; lastCode = code; lastError = error; lastMessages = messages; lastStatus = value;
}
static void query(id self, SEL cmd, unsigned int ident, int code, id error, id messages) {
    (void)self; (void)cmd; lastCode = code; lastError = error; lastMessages = messages; lastQuery = ident;
}
static void registerCallback(const char *name, const char *selector, const char *types, IMP imp) {
    Class cls = objc_allocateClassPair(NSObject.class, name, 0);
    check(cls != Nil, "allocate callback fixture");
    class_addMethod(cls, sel_registerName(selector), imp, types);
    objc_registerClassPair(cls);
}
@interface RecordHolder : NSObject
@property(nonatomic,strong) id record;
@end
@implementation RecordHolder @end
@interface WrongRecordABI : NSObject
- (long long)record;
@end
@implementation WrongRecordABI
- (long long)record { check(NO, "mismatched object getter must never be called"); return 0; }
@end
int main(int argc, const char **argv) {
    @autoreleasepool {
        check(argc == 3, "mode and test directory supplied");
        QARFixtureModels();
        QARSetEnabled(YES);
        NSURL *directory = [NSURL fileURLWithPath:@(argv[2]) isDirectory:YES];
        QARStoreUseTestDirectory(directory);
        id original = QARFixtureMessage(101, 99, @"fixture-peer", 0, @"Synthetic message — preserved");
        id recalled = QARFixtureMessage(101, 99, @"fixture-peer", 1700000000, nil);
        if (strcmp(argv[1], "write") == 0) {
            QARClearSavedMessages();
            QARRememberMessages(@[original]);
            QARMarkRecalledUpdates(@[recalled]);
            check(QARIsMarkedRecord(original), "received update marks saved original");
            check([QARStoreStatus()[@"snapshots_saved"] unsignedIntegerValue] == 1, "snapshot reached disk");
            puts("PASS: independent writer process persisted the original and recall marker");
            return 0;
        }
        NSArray *restored = QARRestoreHistory(@[recalled]);
        check([QARFixtureBody(restored[0]) isEqual:QARFixtureBody(original)], "fresh reader process restores original body from disk");
        check(QARIsMarkedRecord(restored[0]), "badge marker survives a new process");
        check(!QARIsMarkedRecord(recalled), "unrestored recalled placeholder cannot claim retained content");
        QARStoreDropMemoryForTest();
        check([QARFixtureBody(QARRestoreHistory(@[recalled])[0]) isEqual:QARFixtureBody(original)], "discarding RAM retains disk restore");
        QARClearSavedMessages();
        QARRememberMessages(@[original]);
        QARModelWrite(QARModelRead([QARModelRead(original, @"elements", NULL) firstObject], @"textElement", NULL),
            @"content", @"Mutated after receive");
        restored = QARRestoreHistory(@[recalled]);
        check([QARFixtureBody(restored[0]) isEqual:@"Synthetic message — preserved"], "snapshot is a deep copy taken before mutation");

        id normal = QARFixtureMessage(102, 100, @"fixture-peer", 0, @"Normal");
        id missing = QARFixtureMessage(103, 101, @"fixture-peer", 1700000000, nil);
        NSArray *mixed = @[normal, recalled, @"unknown payload item", missing];
        NSArray *prepared = QARRestoreHistory(mixed);
        check(prepared.count == 4 && prepared[0] == normal && prepared[2] == mixed[2] &&
              prepared[3] == missing && prepared[1] != recalled, "history preserves order and unknown/missing items");
        id otherPeer = QARFixtureMessage(101, 99, @"different-peer", 1700000000, nil);
        NSArray *other = @[otherPeer];
        check(QARRestoreHistory(other) == other, "identical IDs in another peer cannot cross-restore");
        id otherChannel = QARFixtureMessage(101, 99, @"fixture-peer", 1700000000, nil);
        QARModelWrite(otherChannel, @"channelId", @"other-channel");
        other = @[otherChannel];
        check(QARRestoreHistory(other) == other, "channel identity is isolated");
        QARFixtureAccount(20002);
        other = @[recalled];
        check(QARRestoreHistory(other) == other && !QARIsMarkedRecord(original), "switching account isolates snapshots and markers");
        QARFixtureAccount(0);
        check(QARRestoreHistory(other) == other && !QARCurrentOwner(), "logged-out context never uses an anonymous shared store");
        QARFixtureAccount(10001);
        id changedID = QARFixtureMessage(999, 99, @"fixture-peer", 1700000000, nil);
        id bySequence = QARRestoreHistory(@[changedID])[0];
        check([QARFixtureBody(bySequence) isEqual:@"Synthetic message — preserved"] &&
            [QARModelRead(bySequence, @"msgId", NULL) longLongValue] == 999, "unambiguous same-peer sequence fallback preserves current local ID");
        QARSetEnabled(NO);
        check(QARRestoreHistory(other) == other && !QARIsMarkedRecord(restored[0]), "disabled mode is exact pass-through and hides markers");
        QARSetEnabled(YES);

        registerCallback("_TtC13GuildNTKernel35SWIGetAioFirstViewLatestMsgCallback",
            "onResult:errMsg:msgList:needContinueGetMsg:", "v40@0:8i16@20@28B36", (IMP)first);
        registerCallback("_TtC13GuildNTKernel27SWIGetMsgWithStatusCallback",
            "onResult:errMsg:status:msgList:", "v44@0:8i16@20q28@36", (IMP)status);
        registerCallback("_TtC13GuildNTKernel25SWIKernelMsgQueryListener",
            "onMsgQueryResult:result:errMsg:msgList:", "v40@0:8I16i20@24@32", (IMP)query);
        NSMutableDictionary *wrong = [QARFixtureInfo() mutableCopy]; wrong[@"CFBundleVersion"] = @"wrong";
        QARInstallHistory(wrong);
        check([QARHistoryStatus()[@"installed_hooks"] unsignedIntegerValue] == 0, "wrong QQ build installs no history hook");
        QARInstallHistory(QARFixtureInfo());
        check([QARHistoryStatus()[@"installed_hooks"] unsignedIntegerValue] == 3, "verified callback ABIs installed");
        id callback = [NSClassFromString(@"_TtC13GuildNTKernel35SWIGetAioFirstViewLatestMsgCallback") new];
        id error = @"synthetic error";
        SEL selector = NSSelectorFromString(@"onResult:errMsg:msgList:needContinueGetMsg:");
        ((void (*)(id, SEL, int, id, id, BOOL))objc_msgSend)(callback, selector, 0, error, @[recalled], YES);
        check(lastCode == 0 && lastError == error && lastMore && [QARFixtureBody(lastMessages[0]) isEqual:@"Synthetic message — preserved"],
            "actual first-view hook restores and forwards BOOL/error arguments");
        ((void (*)(id, SEL, int, id, id, BOOL))objc_msgSend)(callback, selector, -7, error, other, NO);
        check(lastCode == -7 && lastMessages == other && !lastMore, "error callbacks preserve original payload");
        callback = [NSClassFromString(@"_TtC13GuildNTKernel27SWIGetMsgWithStatusCallback") new];
        selector = NSSelectorFromString(@"onResult:errMsg:status:msgList:");
        ((void (*)(id, SEL, int, id, long long, id))objc_msgSend)(callback, selector, 0, error, LLONG_MIN + 77, @[recalled]);
        check(lastStatus == LLONG_MIN + 77 && lastMessages[0] != recalled, "64-bit status ABI and payload preserved");
        callback = [NSClassFromString(@"_TtC13GuildNTKernel25SWIKernelMsgQueryListener") new];
        selector = NSSelectorFromString(@"onMsgQueryResult:result:errMsg:msgList:");
        ((void (*)(id, SEL, unsigned int, int, id, id))objc_msgSend)(callback, selector, UINT_MAX, 0, error, @[recalled]);
        check(lastQuery == UINT_MAX && lastMessages[0] != recalled, "unsigned query ID ABI preserved");

        RecordHolder *holder = [RecordHolder new]; holder.record = restored[0];
        check(QARBadgeRecord(holder) == restored[0], "verified record getter finds the badge record");
        check(QARBadgeRecord([WrongRecordABI new]) == nil, "badge resolver rejects non-object record ABI");
        holder.record = holder;
        check(QARBadgeRecord(holder) == nil, "badge resolver bounds cyclic object graphs");
        NSData *encoded = QAREncodeRecord(restored[0]);
        NSMutableDictionary *graph = [[NSPropertyListSerialization propertyListWithData:encoded
            options:NSPropertyListMutableContainersAndLeaves format:NULL error:nil] mutableCopy];
        graph[@"c"] = @"NSInvocation";
        NSData *invalid = [NSPropertyListSerialization dataWithPropertyList:graph
            format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
        check(!QARDecodeRecord(invalid) && !QARDecodeRecord([encoded subdataWithRange:NSMakeRange(0, 10)]),
            "unknown classes and truncated archives rejected");
        id unsupported = QARFixtureMessage(800, 800, @"fixture-peer", 0, @"Unknown nested type");
        QARModelWrite(unsupported, @"elements", @[[NSObject new]]);
        check(QAREncodeRecord(unsupported) == nil, "unsupported element fails the entire snapshot rather than losing content");
        // Exercise every model primitive at its limits, including unsigned 64-bit values.
        for (NSString *name in QARModelSchemas()) for (NSDictionary *spec in QARModelSchemas()[name]) {
            if ([spec[@"type"] isEqual:@"@"]) continue;
            id object = QARModelCreate(name);
            NSDictionary *edge = @{@"q": @(LLONG_MIN), @"Q": @(ULLONG_MAX), @"i": @(INT_MIN), @"I": @(UINT_MAX), @"B": @YES};
            id value = edge[spec[@"type"]];
            check(QARModelWrite(object, spec[@"name"], value) && [QARModelRead(object, spec[@"name"], NULL) isEqual:value],
                "primitive model ABI round trip");
        }
        QARStoreDropMemoryForTest();
        QARForgetMessageIDs(@[@999]);
        other = @[recalled];
        check(QARRestoreHistory(other) == other && !QARIsMarkedRecord(restored[0]),
            "ordinary deletion by a changed local ID removes persisted aliases and cannot resurrect content");
        QARClearSavedMessages();
        check(!QARIsMarkedRecord(normal), "clear removes markers");
        NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:
            [[directory URLByAppendingPathComponent:[QARCurrentOwner() stringByAppendingString:@".plist"]] path] error:nil];
        check(([attrs[NSFilePosixPermissions] unsignedIntValue] & 0777) == 0600, "private snapshot file permissions");
        NSString *diagnostics = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:QARStoreStatus()
            options:0 error:nil] encoding:NSUTF8StringEncoding];
        check(![diagnostics containsString:@"Synthetic message"] && ![diagnostics containsString:@"fixture-peer"],
            "diagnostics never include message text or peer identifiers");
        QARClearSavedMessages();
        for (int batch = 0; batch < 5; batch++) {
            NSMutableArray *records = [NSMutableArray new];
            for (int index = 0; index < 110; index++) {
                long long ident = 10000 + batch * 110 + index;
                [records addObject:QARFixtureMessage(ident, ident, @"bounded-peer", 0, @"Synthetic bounded snapshot")];
            }
            QARRememberMessages(records);
        }
        check([QARStoreStatus()[@"evicted_snapshots"] unsignedIntegerValue] == 38, "512-record retention limit evicts the oldest records");
        NSURL *storage = [directory URLByAppendingPathComponent:[QARCurrentOwner() stringByAppendingString:@".plist"]];
        NSDictionary *envelope = [NSDictionary dictionaryWithContentsOfURL:storage];
        check([envelope[@"entries"] count] == 512, "persisted envelope is bounded");
        check([[@"truncated" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:storage atomically:YES], "write corrupt test storage");
        QARStoreDropMemoryForTest();
        other = @[QARFixtureMessage(10549, 10549, @"bounded-peer", 1700000000, nil)];
        check(QARRestoreHistory(other) == other, "corrupt storage never substitutes a record");
        QARClearSavedMessages();
        NSURL *blockedRoot = [directory URLByAppendingPathComponent:@"temporarily-unavailable"];
        check([[@"fixture obstruction" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:blockedRoot atomically:YES],
            "create blocked storage fixture");
        QARStoreUseTestDirectory(blockedRoot);
        QARRememberMessages(@[normal]);
        check(![QARStoreStatus()[@"last_disk_write_succeeded"] boolValue], "storage write failure reported");
        check([NSFileManager.defaultManager removeItemAtURL:blockedRoot error:nil], "remove fixture obstruction");
        QARRememberMessages(@[normal]);
        check([QARStoreStatus()[@"last_disk_write_succeeded"] boolValue], "unchanged messages retry an earlier failed disk write");
        QARStoreDropMemoryForTest();
        check([QARFixtureBody(QARRestoreHistory(@[QARFixtureMessage(102, 100, @"fixture-peer", 1700000000, nil)])[0])
            isEqual:@"Normal"], "retried snapshot survives a new memory session");
        puts("PASS: disk restart, deep copy, history callbacks, identity isolation, deletion, badge resolution and archive guards");
    }
    return 0;
}
