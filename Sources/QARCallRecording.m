#import "QARCallRecording.h"
#import "QARAdapter.h"
#import "QARHook.h"
#include <stdatomic.h>

static NSString *const preference = @"QARCallRecordingSuppressionEnabled";
static IMP original;
static QARHookResult result = QARHookMissingClass;
static BOOL supportedHost;
static atomic_ullong calls, suppressed, forwarded;

BOOL QARCallRecordingSuppressionEnabled(void) {
    // Opt in independently of recall protection and flash retention.
    return [NSUserDefaults.standardUserDefaults boolForKey:preference];
}
void QARSetCallRecordingSuppressionEnabled(BOOL enabled) {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:preference];
}
static void sendRecordState(id receiver, SEL selector, int state) {
    atomic_fetch_add(&calls, 1);
    if (QARCallRecordingSuppressionEnabled()) {
        // This is the dedicated outbound recording-state sender, including
        // start/end and retransmissions. Keep the local recording state machine,
        // recording APIs, incoming peer notifications and other call traffic intact.
        atomic_fetch_add(&suppressed, 1);
        return;
    }
    atomic_fetch_add(&forwarded, 1);
    ((void (*)(id, SEL, int))original)(receiver, selector, state);
}
void QARInstallCallRecording(NSDictionary *info) {
    if (!QARVersionSupported(info)) return;
    supportedHost = YES;
    if (original) return;
    result = QARInstallHook(NSClassFromString(@"QQRTCP2PRecordPart"),
        NSSelectorFromString(@"sendRecordState:"), "v20@0:8i16",
        (IMP)sendRecordState, &original);
}
NSDictionary *QARCallRecordingStatus(void) {
    Class cls = NSClassFromString(@"QQRTCP2PRecordPart");
    BOOL active = original && cls &&
        class_getMethodImplementation(cls, NSSelectorFromString(@"sendRecordState:")) == (IMP)sendRecordState;
    return @{
        @"enabled": @(QARCallRecordingSuppressionEnabled()),
        @"supported_host": @(supportedHost),
        @"scope": @"p2p_call_outgoing_recording_state",
        @"hook_result": @(result),
        @"hook_results": @{@"QQRTCP2PRecordPart -sendRecordState:": @(result)},
        @"installed_hooks": @(original != NULL),
        @"hook_active": @(active),
        @"sender_calls": @(atomic_load(&calls)),
        @"suppressed_notifications": @(atomic_load(&suppressed)),
        @"forwarded_notifications": @(atomic_load(&forwarded)),
        @"runtime_qq_verified": @NO,
        @"friend_visible_verified": @NO
    };
}
void QARResetCallRecordingCounters(void) {
    atomic_store(&calls, 0);
    atomic_store(&suppressed, 0);
    atomic_store(&forwarded, 0);
}
