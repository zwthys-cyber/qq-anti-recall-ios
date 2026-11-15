#import "QARIncoming.h"
#import "QARAdapter.h"
#import "QARHook.h"
#import "QARTrace.h"
#include <stdatomic.h>

#define SWI "_TtC13GuildNTKernel20SWIKernelMsgListener"
enum { SWIRecall, SWIReceive, SWIUpdate, SWIDelete, NetParse, PackageParse, PackageInOut, CodecWrite, SlotCount };
typedef struct {
    const char *className;
    const char *selector;
    const char *types;
    BOOL meta;
    const char *event;
    IMP replacement;
    IMP original;
    QARHookResult result;
} Entry;
static void swiRecall(id, SEL, int, id, unsigned long long);
static void swiReceive(id, SEL, id);
static void swiUpdate(id, SEL, id);
static void swiDelete(id, SEL, id, id);
static BOOL netParse(id, SEL, const void *, int, int, void *);
static BOOL packageParse(id, SEL, const void *, int, int, void *);
static void packageInOut(id, SEL, void *);
static void codecWrite(id, SEL, id);
static Entry entries[] = {
    {SWI, "onMsgRecall:peerUid:seq:", "v36@0:8i16@20Q28", NO, "swi_recall", (IMP)swiRecall, NULL, QARHookMissingClass},
    {SWI, "onRecvMsg:", "v24@0:8@16", NO, "swi_received", (IMP)swiReceive, NULL, QARHookMissingClass},
    {SWI, "onMsgInfoListUpdate:", "v24@0:8@16", NO, "swi_list_update", (IMP)swiUpdate, NULL, QARHookMissingClass},
    {SWI, "onMsgDelete:msgIds:", "v32@0:8@16@24", NO, "swi_delete", (IMP)swiDelete, NULL, QARHookMissingClass},
    {"QQMessageRecallNetEngine", "parseC2CRecallNotify:bufferLen:subcmd:model:", "B40@0:8r^v16i24i28^{RecallModel=}32", NO, "c2c_net_parse", (IMP)netParse, NULL, QARHookMissingClass},
    {"QQMessageRecallPackageHandler", "parseC2CRecallNotify:bufferLen:subcmd:model:", "B40@0:8r^v16i24i28^v32", YES, "c2c_package_parse", (IMP)packageParse, NULL, QARHookMissingClass},
    {"QQMessageRecallPackageHandler", "parseC2CRecallInOut:", "v24@0:8^v16", YES, "c2c_inout", (IMP)packageInOut, NULL, QARHookMissingClass},
    {"OCMsgRecord", "setKt_recallTimeFromCodec:", "v24@0:8@16", NO, "recall_codec_write", (IMP)codecWrite, NULL, QARHookMissingClass}
};
static atomic_uint_fast64_t calls[SlotCount], blocked[SlotCount];
static void observe(unsigned slot) {
    atomic_fetch_add(&calls[slot], 1);
    QARTraceEvent([NSString stringWithUTF8String:entries[slot].event]);
}
static BOOL suppress(unsigned slot) {
    observe(slot);
    if (!QAREnabled()) return NO;
    atomic_fetch_add(&blocked[slot], 1);
    return YES;
}
static void swiRecall(id self, SEL cmd, int type, id peer, unsigned long long seq) {
    if (suppress(SWIRecall)) return;
    ((void (*)(id, SEL, int, id, unsigned long long))entries[SWIRecall].original)(self, cmd, type, peer, seq);
}
static void swiReceive(id self, SEL cmd, id messages) {
    observe(SWIReceive);
    ((void (*)(id, SEL, id))entries[SWIReceive].original)(self, cmd, messages);
}
static void swiUpdate(id self, SEL cmd, id messages) {
    observe(SWIUpdate);
    ((void (*)(id, SEL, id))entries[SWIUpdate].original)(self, cmd, messages);
}
static void swiDelete(id self, SEL cmd, id contact, id ids) {
    observe(SWIDelete);
    ((void (*)(id, SEL, id, id))entries[SWIDelete].original)(self, cmd, contact, ids);
}
static BOOL netParse(id self, SEL cmd, const void *bytes, int length, int subcommand, void *model) {
    if (suppress(NetParse)) return NO;
    return ((BOOL (*)(id, SEL, const void *, int, int, void *))entries[NetParse].original)(self, cmd, bytes, length, subcommand, model);
}
static BOOL packageParse(id self, SEL cmd, const void *bytes, int length, int subcommand, void *model) {
    if (suppress(PackageParse)) return NO;
    return ((BOOL (*)(id, SEL, const void *, int, int, void *))entries[PackageParse].original)(self, cmd, bytes, length, subcommand, model);
}
static void packageInOut(id self, SEL cmd, void *model) {
    if (suppress(PackageInOut)) return;
    ((void (*)(id, SEL, void *))entries[PackageInOut].original)(self, cmd, model);
}
static void codecWrite(id self, SEL cmd, id value) {
    observe(CodecWrite);
    ((void (*)(id, SEL, id))entries[CodecWrite].original)(self, cmd, value);
}
static Class target(Entry *entry) {
    Class cls = objc_getClass(entry->className);
    return entry->meta ? object_getClass(cls) : cls;
}
void QARInstallIncoming(NSDictionary *info) {
    if (!QARVersionSupported(info)) return;
    for (unsigned i = 0; i < SlotCount; i++) {
        Entry *entry = &entries[i];
        if (entry->original) continue;
        entry->result = QARInstallHook(target(entry), sel_registerName(entry->selector),
            entry->types, entry->replacement, &entry->original);
    }
}
void QARResetIncoming(void) {
    for (unsigned i = 0; i < SlotCount; i++) {
        atomic_store(&calls[i], 0);
        atomic_store(&blocked[i], 0);
    }
}
NSDictionary *QARIncomingStatus(void) {
    NSMutableDictionary *results = [NSMutableDictionary new];
    NSMutableDictionary *hits = [NSMutableDictionary new];
    NSMutableDictionary *suppressed = [NSMutableDictionary new];
    NSMutableDictionary *integrity = [NSMutableDictionary new];
    NSUInteger installed = 0;
    unsigned long long total = 0;
    for (unsigned i = 0; i < SlotCount; i++) {
        Entry *entry = &entries[i];
        NSString *key = [NSString stringWithFormat:@"%s %c%s",
            entry->className, entry->meta ? '+' : '-', entry->selector];
        results[key] = @(entry->result);
        hits[[NSString stringWithUTF8String:entry->event]] = @(atomic_load(&calls[i]));
        unsigned long long count = atomic_load(&blocked[i]);
        suppressed[[NSString stringWithUTF8String:entry->event]] = @(count);
        total += count;
        if (entry->original) installed++;
        Method method = class_getInstanceMethod(target(entry), sel_registerName(entry->selector));
        integrity[key] = @(entry->original && method && method_getImplementation(method) == entry->replacement);
    }
    return @{@"installed_hooks": @(installed), @"hook_results": results,
             @"hook_calls": hits, @"suppressed_calls": suppressed,
             @"hook_still_active": integrity, @"intercepted_events": @(total)};
}
