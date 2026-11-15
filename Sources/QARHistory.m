#import "QARHistory.h"
#import "QARStore.h"
#import "QARAdapter.h"
#import "QARHook.h"
#import "QARTrace.h"
#include <stdatomic.h>
static void firstView(id self, SEL cmd, int code, id error, id messages, BOOL more);
static void guildFirstView(id self, SEL cmd, int code, id error, id messages, BOOL more);
static void operateResult(id self, SEL cmd, int code, id error, id messages);
static void statusResult(id self, SEL cmd, int code, id error, long long status, id messages);
static void queryResult(id self, SEL cmd, unsigned int query, int code, id error, id messages);
static void multiResult(id self, SEL cmd, int code, id error, id messages);
static void listAdded(id self, SEL cmd, id messages);
typedef struct { const char *cls, *selector, *types, *event; IMP replacement, original; QARHookResult result; } HistoryEntry;
static HistoryEntry entries[] = {
    {"_TtC13GuildNTKernel35SWIGetAioFirstViewLatestMsgCallback", "onResult:errMsg:msgList:needContinueGetMsg:", "v40@0:8i16@20@28B36", "history_first_view", (IMP)firstView, NULL, QARHookMissingClass},
    {"_TtC13GuildNTKernel40SWIGetGuildAioFirstViewLatestMsgCallback", "onResult:errMsg:msgList:needContinueGetMsg:", "v40@0:8i16@20@28B36", "history_guild_first_view", (IMP)guildFirstView, NULL, QARHookMissingClass},
    {"_TtC13GuildNTKernel21SWIMsgOperateCallback", "onResult:errMsg:msgList:", "v36@0:8i16@20@28", "history_operate_result", (IMP)operateResult, NULL, QARHookMissingClass},
    {"_TtC13GuildNTKernel27SWIGetMsgWithStatusCallback", "onResult:errMsg:status:msgList:", "v44@0:8i16@20q28@36", "history_status_result", (IMP)statusResult, NULL, QARHookMissingClass},
    {"_TtC13GuildNTKernel25SWIKernelMsgQueryListener", "onMsgQueryResult:result:errMsg:msgList:", "v40@0:8I16i20@24@32", "history_query_result", (IMP)queryResult, NULL, QARHookMissingClass},
    {"_TtC13GuildNTKernel22SWIGetMultiMsgCallback", "onResult:errMsg:msgList:", "v36@0:8i16@20@28", "history_multi_result", (IMP)multiResult, NULL, QARHookMissingClass},
    {"_TtC13GuildNTKernel20SWIKernelMsgListener", "onMsgInfoListAdd:", "v24@0:8@16", "history_list_added", (IMP)listAdded, NULL, QARHookMissingClass},
};
static atomic_uint_fast64_t calls[7];
static void firstView(id self, SEL cmd, int code, id error, id messages, BOOL more) {
    atomic_fetch_add(&calls[0], 1);
    QARTraceEvent(@"history_first_view");
    id prepared = code == 0 ? QARRestoreHistory(messages) : messages;
    ((void (*)(id, SEL, int, id, id, BOOL))entries[0].original)(self, cmd, code, error, prepared, more);
}
static void guildFirstView(id self, SEL cmd, int code, id error, id messages, BOOL more) {
    atomic_fetch_add(&calls[1], 1);
    QARTraceEvent(@"history_guild_first_view");
    id prepared = code == 0 ? QARRestoreHistory(messages) : messages;
    ((void (*)(id, SEL, int, id, id, BOOL))entries[1].original)(self, cmd, code, error, prepared, more);
}
static void operateResult(id self, SEL cmd, int code, id error, id messages) {
    atomic_fetch_add(&calls[2], 1);
    QARTraceEvent(@"history_operate_result");
    id prepared = code == 0 ? QARRestoreHistory(messages) : messages;
    ((void (*)(id, SEL, int, id, id))entries[2].original)(self, cmd, code, error, prepared);
}
static void statusResult(id self, SEL cmd, int code, id error, long long status, id messages) {
    atomic_fetch_add(&calls[3], 1);
    QARTraceEvent(@"history_status_result");
    id prepared = code == 0 ? QARRestoreHistory(messages) : messages;
    ((void (*)(id, SEL, int, id, long long, id))entries[3].original)(self, cmd, code, error, status, prepared);
}
static void queryResult(id self, SEL cmd, unsigned int query, int code, id error, id messages) {
    atomic_fetch_add(&calls[4], 1);
    QARTraceEvent(@"history_query_result");
    id prepared = code == 0 ? QARRestoreHistory(messages) : messages;
    ((void (*)(id, SEL, unsigned int, int, id, id))entries[4].original)(self, cmd, query, code, error, prepared);
}
static void multiResult(id self, SEL cmd, int code, id error, id messages) {
    atomic_fetch_add(&calls[5], 1);
    QARTraceEvent(@"history_multi_result");
    id prepared = code == 0 ? QARRestoreHistory(messages) : messages;
    ((void (*)(id, SEL, int, id, id))entries[5].original)(self, cmd, code, error, prepared);
}
static void listAdded(id self, SEL cmd, id messages) {
    atomic_fetch_add(&calls[6], 1);
    QARTraceEvent(@"history_list_added");
    id prepared = QARRestoreHistory(messages);
    ((void (*)(id, SEL, id))entries[6].original)(self, cmd, prepared);
}
void QARInstallHistory(NSDictionary *info) {
    if (!QARVersionSupported(info)) return;
    for (unsigned i = 0; i < 7; i++) {
        HistoryEntry *entry = &entries[i];
        if (entry->original) continue;
        entry->result = QARInstallHook(objc_getClass(entry->cls), sel_registerName(entry->selector),
            entry->types, entry->replacement, &entry->original);
    }
}
void QARResetHistoryCounters(void) {
    for (unsigned i = 0; i < 7; i++) atomic_store(&calls[i], 0);
}
NSDictionary *QARHistoryStatus(void) {
    NSMutableDictionary *results = [NSMutableDictionary new], *hits = [NSMutableDictionary new], *active = [NSMutableDictionary new];
    NSUInteger installed = 0;
    for (unsigned i = 0; i < 7; i++) {
        HistoryEntry *entry = &entries[i];
        NSString *key = [NSString stringWithFormat:@"%s -%s", entry->cls, entry->selector];
        results[key] = @(entry->result);
        hits[[NSString stringWithUTF8String:entry->event]] = @(atomic_load(&calls[i]));
        if (entry->original) installed++;
        Method method = class_getInstanceMethod(objc_getClass(entry->cls), sel_registerName(entry->selector));
        active[key] = @(entry->original && method && method_getImplementation(method) == entry->replacement);
    }
    return @{@"installed_hooks": @(installed), @"hook_results": results, @"hook_calls": hits, @"hook_still_active": active};
}
