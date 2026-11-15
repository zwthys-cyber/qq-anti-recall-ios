#import "QARTrace.h"
#include <dlfcn.h>
#include <string.h>

// Bounded metadata only: labels from our code and offsets within the QQ image.
// Never serialize receiver/arguments, symbol strings, paths, peers or contents.
static NSObject *traceLock;
static NSMutableArray<NSDictionary *> *entries;
static NSMutableDictionary<NSString *, NSNumber *> *counts;
static NSUInteger generation;
static NSTimeInterval started;

static void prepare(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        traceLock = [NSObject new];
        entries = [NSMutableArray new];
        counts = [NSMutableDictionary new];
        started = NSProcessInfo.processInfo.systemUptime;
    });
}
void QARTraceEvent(NSString *event) {
    prepare();
    NSUInteger slot, epoch;
    @synchronized (traceLock) {
        NSUInteger count = [counts[event] unsignedIntegerValue];
        if (count >= 2 || entries.count >= 24) return;
        counts[event] = @(count + 1);
        epoch = generation;
        slot = entries.count;
        [entries addObject:@{@"event": event, @"qq_image_offsets": @[]}];
    }
    NSMutableArray<NSString *> *frames = [NSMutableArray new];
    for (NSNumber *address in NSThread.callStackReturnAddresses) {
        uintptr_t pointer = (uintptr_t)address.unsignedLongLongValue;
        Dl_info info = {0};
        if (!dladdr((void *)pointer, &info) || !info.dli_fname || !info.dli_fbase) continue;
        const char *name = strrchr(info.dli_fname, '/');
        name = name ? name + 1 : info.dli_fname;
        if (strcmp(name, "QQ") != 0 || pointer < (uintptr_t)info.dli_fbase) continue;
        [frames addObject:[NSString stringWithFormat:@"0x%llx",
            (unsigned long long)(pointer - (uintptr_t)info.dli_fbase)]];
        if (frames.count >= 12) break;
    }
    @synchronized (traceLock) {
        if (epoch != generation) return;
        entries[slot] = @{@"event": event, @"qq_image_offsets": [frames copy],
            @"elapsed_ms": @((NSUInteger)((NSProcessInfo.processInfo.systemUptime - started) * 1000))};
    }
}
void QARResetTrace(void) {
    prepare();
    @synchronized (traceLock) {
        generation++;
        [entries removeAllObjects];
        [counts removeAllObjects];
        started = NSProcessInfo.processInfo.systemUptime;
    }
}
NSArray<NSDictionary *> *QARTraceSnapshot(void) {
    prepare();
    @synchronized (traceLock) { return [entries copy]; }
}
