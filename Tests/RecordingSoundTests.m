#import <Foundation/Foundation.h>
#import <objc/message.h>
#import "QARCallRecording.h"
#import "QARHook.h"
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>

static id player, recorder;
static NSMutableArray *played;
static NSUInteger completions, saves;
static unsigned long long receivedReason, receivedResult;
static BOOL throwInCompletion, nestedCompletion, otherThread;
static void check(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static void emit(id name, int loops) {
    ((void (*)(id, SEL, id, int))objc_msgSend)(player, NSSelectorFromString(@"playAudio:andLoopTime:"), name, loops);
}
static void finish(unsigned long long reason, unsigned long long result) {
    ((void (*)(id, SEL, unsigned long long, unsigned long long))objc_msgSend)(recorder,
        NSSelectorFromString(@"recordAVTinyVideoFinished:RecordStopResult:"), reason, result);
}
static void audio(id self, SEL cmd, id name, int loops) {
    (void)self; (void)cmd;
    [played addObject:@{@"name": name ?: NSNull.null, @"loops": @(loops)}];
}
static void wrongAudio(id self, SEL cmd, id name, long long loops) {
    (void)self; (void)cmd; (void)name; (void)loops;
}
static void sender(id self, SEL cmd, int state) { (void)self; (void)cmd; (void)state; }
static void completed(id self, SEL cmd, unsigned long long reason, unsigned long long result) {
    (void)self; (void)cmd;
    completions++; receivedReason = reason; receivedResult = result;
    if (nestedCompletion) { nestedCompletion = NO; finish(reason, result); }
    emit(@"recordDing", 0);
    emit(@"unrelated-call-tone", INT_MIN);
    emit(@"recordDing", 1);
    emit(NSNull.null, 0);
    emit(@"recordDing.wav", 0);
    if (otherThread) {
        NSThread *origin = NSThread.currentThread;
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            check(NSThread.currentThread != origin, "fixture audio runs on another thread");
            emit(@"recordDing", 0);
            dispatch_semaphore_signal(done);
        });
        check(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) == 0,
            "cross-thread fixture completes within deadline");
    }
    if (throwInCompletion) @throw [NSException exceptionWithName:@"FixtureCompletionError" reason:nil userInfo:nil];
    // Stand in for original save/UI/callback work after the audio request.
    saves++;
}
static void wrongCompletion(id self, SEL cmd, int reason, unsigned long long result) {
    (void)self; (void)cmd; (void)reason; (void)result;
}
static Class registerPlayer(BOOL missingMethod, BOOL wrongABI) {
    Class cls = objc_allocateClassPair(NSObject.class, "AVRingPlayer", 0);
    check(cls != Nil, "allocate player");
    if (!missingMethod) class_addMethod(cls, NSSelectorFromString(@"playAudio:andLoopTime:"),
        wrongABI ? (IMP)wrongAudio : (IMP)audio, wrongABI ? "v32@0:8@16q24" : "v28@0:8@16i24");
    objc_registerClassPair(cls); player = [cls new]; return cls;
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *mode = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"normal";
        BOOL late = [mode isEqual:@"late-class"];
        BOOL missingPlayer = [mode isEqual:@"missing-player"];
        BOOL missingAudio = [mode isEqual:@"missing-audio"];
        BOOL wrongAudioABI = [mode isEqual:@"wrong-audio-abi"];
        BOOL wrongCompletionABI = [mode isEqual:@"wrong-completion-abi"];
        BOOL wrongVersion = [mode isEqual:@"wrong-version"];
        BOOL missingCompletion = [mode isEqual:@"missing-completion"];
        Class part = objc_allocateClassPair(NSObject.class, "QQRTCP2PRecordPart", 0);
        check(part != Nil, "allocate recorder");
        class_addMethod(part, NSSelectorFromString(@"sendRecordState:"), (IMP)sender, "v20@0:8i16");
        if (!missingCompletion) class_addMethod(part, NSSelectorFromString(@"recordAVTinyVideoFinished:RecordStopResult:"),
            wrongCompletionABI ? (IMP)wrongCompletion : (IMP)completed,
            wrongCompletionABI ? "v28@0:8i16Q20" : "v32@0:8Q16Q24");
        objc_registerClassPair(part); recorder = [part new]; played = [NSMutableArray new];
        Class ring = Nil;
        if (!late && !missingPlayer) ring = registerPlayer(missingAudio, wrongAudioABI);
        SEL completion = NSSelectorFromString(@"recordAVTinyVideoFinished:RecordStopResult:");
        SEL sound = NSSelectorFromString(@"playAudio:andLoopTime:");
        IMP beforeCompletion = class_getMethodImplementation(part, completion);
        IMP beforeAudio = ring ? class_getMethodImplementation(ring, sound) : NULL;
        NSDictionary *info = @{@"CFBundleShortVersionString": @"9.3.86",
            @"CFBundleVersion": wrongVersion ? @"other" : @"9.3.86.617", @"CFBundleExecutable": @"QQ"};
        QARInstallCallRecording(info);
        if (late || missingPlayer || missingAudio || wrongAudioABI || wrongCompletionABI || wrongVersion || missingCompletion) {
            check(![QARCallRecordingStatus()[@"completion_tone_hook_active"] boolValue], "invalid or incomplete pair remains inactive");
            check(class_getMethodImplementation(part, completion) == beforeCompletion, "pair rejection preserves completion IMP");
            if (ring) check(class_getMethodImplementation(ring, sound) == beforeAudio, "pair rejection preserves audio IMP");
            check([QARCallRecordingStatus()[@"installed_hooks"] intValue] == (wrongVersion ? 0 : 1), "only independent sender may be installed");
            if (!late) { puts("PASS: completion-tone pair/version rejection."); return 0; }
            ring = registerPlayer(NO, NO);
            QARInstallCallRecording(info);
        }
        QARInstallCallRecording(info);
        check([QARCallRecordingStatus()[@"completion_tone_hook_active"] boolValue] &&
            [QARCallRecordingStatus()[@"installed_hooks"] intValue] == 3, "complete pair installs once, including retry");
        QARSetCallRecordingSuppressionEnabled(NO);
        finish(ULLONG_MAX, 0x100000001ULL);
        check(completions == 1 && saves == 1 && receivedReason == ULLONG_MAX && receivedResult == 0x100000001ULL,
            "completion forwards full-width arguments and save work");
        check(played.count == 5 && [QARCallRecordingStatus()[@"completion_tones_muted"] intValue] == 0,
            "disabled completion preserves audio requests");
        QARSetCallRecordingSuppressionEnabled(YES);
        NSUInteger before = played.count;
        finish(1, 2);
        check(played.count == before + 4 && completions == 2 && saves == 2,
            "enabled completion removes only exact cue and retains original work");
        check([QARCallRecordingStatus()[@"completion_tones_muted"] intValue] == 1, "one completion cue muted");
        NSArray *tail = [played subarrayWithRange:NSMakeRange(before, 4)];
        check([tail[0][@"name"] isEqual:@"unrelated-call-tone"] && [tail[0][@"loops"] intValue] == INT_MIN &&
            [tail[1][@"name"] isEqual:@"recordDing"] && [tail[1][@"loops"] intValue] == 1 &&
            tail[2][@"name"] == NSNull.null && [tail[3][@"name"] isEqual:@"recordDing.wav"],
            "other resources, loop counts and non-string objects pass intact");
        before = played.count;
        emit(@"recordDing", 0);
        check(played.count == before + 1, "same cue outside completion remains audible");
        otherThread = YES; before = played.count;
        finish(3, 4); otherThread = NO;
        check(played.count == before + 5, "completion scope does not mute another thread");
        before = played.count; NSUInteger beforeMuted = [QARCallRecordingStatus()[@"completion_tones_muted"] unsignedIntegerValue];
        nestedCompletion = YES; finish(5, 6);
        check(played.count == before + 8 &&
            [QARCallRecordingStatus()[@"completion_tones_muted"] unsignedIntegerValue] == beforeMuted + 2,
            "nested completions preserve outer scope");
        throwInCompletion = YES;
        BOOL caught = NO;
        @try { finish(7, 8); } @catch (NSException *error) { caught = [error.name isEqual:@"FixtureCompletionError"]; }
        throwInCompletion = NO;
        check(caught, "original completion exception propagates");
        before = played.count; emit(@"recordDing", 0);
        check(played.count == before + 1, "exception unwinds completion scope");
        QARResetCallRecordingCounters();
        check([QARCallRecordingStatus()[@"completion_tones_muted"] intValue] == 0, "tone counter resets");
        puts("PASS: exact completion-tone filtering, passthrough, save work, threads, nesting and exception cleanup.");
    }
    return 0;
}
