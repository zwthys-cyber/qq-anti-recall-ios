#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "QARAdapter.h"
#import "QARIncoming.h"
#import "QARUpdateFilter.h"
#include <limits.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>

static atomic_uint_fast64_t flagReads, bodyReads, invalidGetterCalls;
static void check(BOOL condition, const char *why) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", why); exit(1); }
}
@interface QARFixtureRecord : NSObject {
    long long _recallValue;
    NSString *_bodyValue;
}
@property(nonatomic) long long recallTime;
@property(nonatomic) long long msgId;
@property(nonatomic,copy) NSString *body;
@end
@implementation QARFixtureRecord
- (long long)recallTime { atomic_fetch_add(&flagReads, 1); return _recallValue; }
- (void)setRecallTime:(long long)value { _recallValue = value; }
- (NSString *)body { atomic_fetch_add(&bodyReads, 1); return _bodyValue; }
- (void)setBody:(NSString *)value { _bodyValue = [value copy]; }
@end
@interface QARFixtureListener : NSObject
@property(nonatomic,strong) NSMutableDictionary<NSNumber *, QARFixtureRecord *> *visible;
@property(nonatomic,strong) NSArray *lastUpdate;
@property(nonatomic) NSUInteger updateCalls;
@property(nonatomic) NSUInteger recallCalls;
- (void)onRecvMsg:(id)messages;
- (void)onMsgInfoListUpdate:(id)messages;
- (void)onMsgRecall:(int)type peerUid:(id)peer seq:(unsigned long long)seq;
- (void)onMsgDelete:(id)contact msgIds:(id)ids;
@end
@implementation QARFixtureListener
- (instancetype)init {
    if ((self = [super init])) _visible = [NSMutableDictionary new];
    return self;
}
- (void)onRecvMsg:(id)messages {
    for (QARFixtureRecord *record in messages) self.visible[@(record.msgId)] = record;
}
- (void)onMsgInfoListUpdate:(id)messages {
    self.updateCalls++;
    self.lastUpdate = messages;
    for (QARFixtureRecord *record in messages) {
        if (record.recallTime > 0) [self.visible removeObjectForKey:@(record.msgId)];
        else self.visible[@(record.msgId)] = record;
    }
}
- (void)onMsgRecall:(int)type peerUid:(id)peer seq:(unsigned long long)seq {
    (void)type; (void)peer; self.recallCalls++;
    [self.visible removeObjectForKey:@(seq)];
}
- (void)onMsgDelete:(id)contact msgIds:(id)ids {
    (void)contact;
    [self.visible removeObjectsForKeys:ids];
}
@end
static id invalidObjectGetter(id self, SEL cmd) {
    (void)self; (void)cmd; atomic_fetch_add(&invalidGetterCalls, 1);
    return @"must not be called through a 64-bit integer ABI";
}
static long long throwingGetter(id self, SEL cmd) {
    (void)self; (void)cmd;
    @throw [NSException exceptionWithName:@"SyntheticReadFailure" reason:nil userInfo:nil];
}
static QARFixtureRecord *record(Class cls, long long msgId, long long recall, NSString *body) {
    QARFixtureRecord *value = [cls new];
    value.msgId = msgId; value.recallTime = recall; value.body = body;
    return value;
}
int main(void) {
    @autoreleasepool {
        Class records = objc_allocateClassPair(QARFixtureRecord.class, "OCMsgRecord", 0);
        Class listeners = objc_allocateClassPair(QARFixtureListener.class,
            "_TtC13GuildNTKernel20SWIKernelMsgListener", 0);
        check(records && listeners, "create bridge record and listener fixtures");
        objc_registerClassPair(records);
        objc_registerClassPair(listeners);
        NSDictionary *info = @{@"CFBundleShortVersionString": @"9.3.86",
            @"CFBundleVersion": @"9.3.86.617", @"CFBundleExecutable": @"QQ"};
        QARInstallIncoming(info);
        check([QARIncomingStatus()[@"installed_hooks"] unsignedIntegerValue] == 4,
              "all four verified SWI callbacks installed");
        check([QARUpdateFilterStatus()[@"recall_update_filter_ready"] boolValue],
              "record getter ABI accepted");
        QARSetEnabled(YES);
        QARFixtureRecord *original = record(records, 1, 0, @"synthetic original body");
        QARFixtureRecord *recalled = record(records, 1, 1700000000, nil);
        QARFixtureListener *lateOnly = [listeners new];
        [lateOnly onRecvMsg:@[original]];
        // Reproduce 0.2: forward the destructive update, then suppress the late notice.
        IMP oldUpdate = class_getMethodImplementation(QARFixtureListener.class,
            @selector(onMsgInfoListUpdate:));
        ((void (*)(id, SEL, id))oldUpdate)(lateOnly, @selector(onMsgInfoListUpdate:), @[recalled]);
        [lateOnly onMsgRecall:1 peerUid:@"synthetic private peer" seq:1];
        check(lateOnly.visible[@1] == nil && lateOnly.recallCalls == 0,
              "reproduction: late recall suppression alone loses the visible message");

        QARFixtureListener *fixed = [listeners new];
        [fixed onRecvMsg:@[original]];
        [fixed onMsgInfoListUpdate:@[recalled]];
        [fixed onMsgRecall:1 peerUid:@"synthetic private peer" seq:1];
        check(fixed.visible[@1] == original && fixed.updateCalls == 0 && fixed.recallCalls == 0,
              "regression: update-before-notification retains the original visible object");
        check([fixed.visible[@1].body isEqual:@"synthetic original body"],
              "original displayed content remains available");
        check(recalled.recallTime > 0 && original.recallTime == 0,
              "filter neither rewrites input flags nor mutates the displayed record");

        QARFixtureRecord *second = record(records, 2, 0, @"before normal edit");
        QARFixtureRecord *edited = record(records, 2, 0, @"after normal edit");
        QARFixtureRecord *sentinel = record(records, 3, -1, @"negative sentinel");
        [fixed onRecvMsg:@[second]];
        NSArray *batch = @[recalled, edited, sentinel];
        [fixed onMsgInfoListUpdate:batch];
        check(fixed.visible[@1] == original && fixed.visible[@2] == edited &&
              fixed.visible[@3] == sentinel && fixed.updateCalls == 1,
              "mixed batch keeps recalled message while delivering normal updates");
        check(fixed.lastUpdate.count == 2 && fixed.lastUpdate[0] == edited &&
              fixed.lastUpdate[1] == sentinel && batch.count == 3 && batch[0] == recalled,
              "mixed batch preserves identity, ordering and original payload");
        [fixed onMsgDelete:nil msgIds:@[@2]];
        check(fixed.visible[@2] == nil, "ordinary user deletion is preserved");

        QARSetEnabled(NO);
        QARFixtureListener *disabled = [listeners new];
        [disabled onRecvMsg:@[original]];
        NSArray *recallBatch = @[recalled];
        [disabled onMsgInfoListUpdate:recallBatch];
        [disabled onMsgRecall:1 peerUid:nil seq:1];
        check(disabled.visible[@1] == nil && disabled.lastUpdate == recallBatch &&
              disabled.recallCalls == 1, "disabled mode preserves original QQ deletion semantics");

        BOOL forward = NO;
        atomic_store(&flagReads, 0);
        check(QARFilterMessageUpdates(recallBatch, &forward) == recallBatch && forward &&
              atomic_load(&flagReads) == 0, "disabled filter does not even read record getters");
        QARSetEnabled(YES);
        NSArray *empty = @[];
        check(QARFilterMessageUpdates(empty, &forward) == empty && forward, "real empty update is forwarded");
        check(QARFilterMessageUpdates(nil, &forward) == nil && forward, "nil update is forwarded");
        NSDictionary *unknown = @{@"synthetic": @1};
        check(QARFilterMessageUpdates(unknown, &forward) == unknown && forward, "unknown container is not altered");
        NSArray *ordinary = @[edited, sentinel];
        check(QARFilterMessageUpdates(ordinary, &forward) == ordinary && forward,
              "unrelated batch retains payload identity");

        QARFixtureRecord *impostor = record(QARFixtureRecord.class, 4, 20, @"unrelated class");
        NSArray *nonQQ = @[impostor, NSNull.null];
        check(QARFilterMessageUpdates(nonQQ, &forward) == nonQQ && forward,
              "matching property names on unrelated classes never trigger suppression");
        Class invalid = objc_allocateClassPair(records, "QARInvalidGetterRecord", 0);
        class_addMethod(invalid, @selector(recallTime), (IMP)invalidObjectGetter, "@16@0:8");
        objc_registerClassPair(invalid);
        NSArray *bad = @[[invalid new]];
        check(QARFilterMessageUpdates(bad, &forward) == bad && forward &&
              atomic_load(&invalidGetterCalls) == 0, "subclass ABI mismatch is rejected without calling it");
        Class throwing = objc_allocateClassPair(records, "QARThrowingGetterRecord", 0);
        class_addMethod(throwing, @selector(recallTime), (IMP)throwingGetter, "q16@0:8");
        objc_registerClassPair(throwing);
        NSArray *throws = @[[throwing new]];
        check(QARFilterMessageUpdates(throws, &forward) == throws && forward,
              "unreadable record preserves original behavior without plugin exception");

        atomic_store(&bodyReads, 0);
        QARFixtureRecord *maximum = record(records, 5, LLONG_MAX, @"must not inspect this body");
        QARFixtureRecord *minimum = record(records, 6, LLONG_MIN, @"also unread");
        NSArray *limits = @[maximum, minimum];
        NSArray *result = QARFilterMessageUpdates(limits, &forward);
        check(forward && result.count == 1 && result[0] == minimum && atomic_load(&bodyReads) == 0,
              "signed 64-bit boundaries are exact and message contents are never read");
        QARResetDiagnostics();
        dispatch_apply(1000, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t i) {
            (void)i;
            @autoreleasepool {
                BOOL deliver = NO;
                NSArray *out = QARFilterMessageUpdates(limits, &deliver);
                check(deliver && out.count == 1 && out[0] == minimum, "concurrent filtering result");
            }
        });
        check([QARUpdateFilterStatus()[@"filtered_recall_update_items"] unsignedLongLongValue] == 1000 &&
              [QARUpdateFilterStatus()[@"forwarded_mixed_update_batches"] unsignedLongLongValue] == 1000,
              "concurrent diagnostic counters are exact");
        NSData *data = [NSJSONSerialization dataWithJSONObject:QARStatus() options:0 error:nil];
        NSString *diagnostic = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        check(![diagnostic containsString:@"synthetic original body"] &&
              ![diagnostic containsString:@"synthetic private peer"] &&
              ![diagnostic containsString:@"must not inspect this body"],
              "diagnostics contain neither messages nor peer values");
        QARResetDiagnostics();
        check([QARUpdateFilterStatus()[@"filtered_recall_update_items"] unsignedLongLongValue] == 0,
              "user reset clears filter counters");
        puts("PASS: reproduced late-hook loss; early recall filtering preserves displayed content and mixed normal updates.");
    }
    return 0;
}
