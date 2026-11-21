#import "QARCallRecording.h"
#import "QARAdapter.h"
#import "QARHook.h"
#include <stdatomic.h>

static NSString *const preference = @"QARCallRecordingSuppressionEnabled";
static IMP original, audioOriginal, completionOriginal;
static QARHookResult result = QARHookMissingClass;
static BOOL supportedHost;
static QARHookResult audioResult = QARHookMissingClass, completionResult = QARHookMissingClass;
static _Thread_local unsigned completionDepth;
static atomic_ullong calls, suppressed, forwarded, mutedCompletionTones;

BOOL QARCallRecordingSuppressionEnabled(void) {
    // Opt in independently of recall protection and flash retention.
    return [NSUserDefaults.standardUserDefaults boolForKey:preference];
}
void QARSetCallRecordingSuppressionEnabled(BOOL enabled) {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:preference];
}
static void sendRecordState(id receiver, SEL selector, int state) {
    atomic_fetch_add(&calls, 1);
    if (QARCallRecordingSuppressionEnabled() && (state == 1 || state == 3 || state == 8)) {
        // Verified protocol: 1 = local start; 3/8 = local end/cancel paths.
        // Keep 5 (stop the peer's recording), ACKs and unknown states intact.
        // Retries use this same sender and the same state values.
        atomic_fetch_add(&suppressed, 1);
        return;
    }
    atomic_fetch_add(&forwarded, 1);
    ((void (*)(id, SEL, int))original)(receiver, selector, state);
}
static void playAudio(id receiver, SEL selector, id name, int loops) {
    if (completionDepth && QARCallRecordingSuppressionEnabled() && loops == 0 &&
        [name isKindOfClass:NSString.class] && [name isEqualToString:@"recordDing"]) {
        atomic_fetch_add(&mutedCompletionTones, 1);
        return;
    }
    ((void (*)(id, SEL, id, int))audioOriginal)(receiver, selector, name, loops);
}
static void recordingFinished(id receiver, SEL selector, unsigned long long reason, unsigned long long stopResult) {
    // The verified completion callback invokes the cue synchronously before
    // scheduling UI/save-result work. Scope to this thread and always unwind.
    completionDepth++;
    @try {
        ((void (*)(id, SEL, unsigned long long, unsigned long long))completionOriginal)(receiver, selector, reason, stopResult);
    } @finally {
        completionDepth--;
    }
}
static QARHookResult preflight(Class cls, SEL selector, const char *types) {
    if (!cls) return QARHookMissingClass;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return QARHookMissingMethod;
    return QARSignaturesMatch(method_getTypeEncoding(method), types) ? QARHookInstalled : QARHookSignatureMismatch;
}
static void installCompletionTone(void) {
    if (audioOriginal && completionOriginal) return;
    Class player = NSClassFromString(@"AVRingPlayer"), part = NSClassFromString(@"QQRTCP2PRecordPart");
    SEL audio = NSSelectorFromString(@"playAudio:andLoopTime:");
    SEL completion = NSSelectorFromString(@"recordAVTinyVideoFinished:RecordStopResult:");
    // Validate the complete pair before changing either method.
    audioResult = preflight(player, audio, "v28@0:8@16i24");
    completionResult = preflight(part, completion, "v32@0:8Q16Q24");
    if (audioResult != QARHookInstalled || completionResult != QARHookInstalled) return;
    if (!audioOriginal) audioResult = QARInstallHook(player, audio, "v28@0:8@16i24", (IMP)playAudio, &audioOriginal);
    if (!completionOriginal) completionResult = QARInstallHook(part, completion, "v32@0:8Q16Q24", (IMP)recordingFinished, &completionOriginal);
}
void QARInstallCallRecording(NSDictionary *info) {
    if (!QARVersionSupported(info)) return;
    supportedHost = YES;
    if (!original) result = QARInstallHook(NSClassFromString(@"QQRTCP2PRecordPart"),
        NSSelectorFromString(@"sendRecordState:"), "v20@0:8i16",
        (IMP)sendRecordState, &original);
    installCompletionTone();
}
NSDictionary *QARCallRecordingStatus(void) {
    Class cls = NSClassFromString(@"QQRTCP2PRecordPart");
    BOOL active = original && cls &&
        class_getMethodImplementation(cls, NSSelectorFromString(@"sendRecordState:")) == (IMP)sendRecordState;
    Class player = NSClassFromString(@"AVRingPlayer");
    BOOL audioActive = audioOriginal && player &&
        class_getMethodImplementation(player, NSSelectorFromString(@"playAudio:andLoopTime:")) == (IMP)playAudio;
    BOOL completionActive = completionOriginal && cls &&
        class_getMethodImplementation(cls, NSSelectorFromString(@"recordAVTinyVideoFinished:RecordStopResult:")) == (IMP)recordingFinished;
    return @{
        @"enabled": @(QARCallRecordingSuppressionEnabled()),
        @"supported_host": @(supportedHost),
        @"scope": @"p2p_call_local_start_end_notifications",
        @"preserves_peer_stop_controls": @YES,
        @"hook_result": @(result),
        @"hook_results": @{@"QQRTCP2PRecordPart -sendRecordState:": @(result),
            @"AVRingPlayer -playAudio:andLoopTime:": @(audioResult),
            @"QQRTCP2PRecordPart -recordAVTinyVideoFinished:RecordStopResult:": @(completionResult)},
        @"installed_hooks": @((original != NULL) + (audioOriginal != NULL) + (completionOriginal != NULL)),
        @"completion_tone_hook_active": @(audioActive && completionActive),
        @"completion_tones_muted": @(atomic_load(&mutedCompletionTones)),
        @"completion_audio_hook_result": @(audioResult),
        @"completion_scope_hook_result": @(completionResult),
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
    atomic_store(&mutedCompletionTones, 0);
}
