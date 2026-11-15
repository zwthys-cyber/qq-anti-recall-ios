#import "QARUpdateFilter.h"
#import "QARAdapter.h"
#import "QARHook.h"
#import "QARTrace.h"
#import <objc/message.h>
#include <stdatomic.h>

static atomic_uint_fast64_t inspectedItems, removedItems, changedBatches;
static atomic_uint_fast64_t mixedBatches, droppedBatches, unknownPayloads;
static atomic_uint_fast64_t unknownItems, rejectedABI, failedReads;

static BOOL validGetter(Class cls) {
    Method method = cls ? class_getInstanceMethod(cls, sel_registerName("recallTime")) : NULL;
    return method && QARSignaturesMatch(method_getTypeEncoding(method), "q16@0:8");
}
static BOOL isRecalled(id item, Class recordClass) {
    if (!recordClass || ![item isKindOfClass:recordClass]) {
        atomic_fetch_add(&unknownItems, 1);
        return NO;
    }
    // Check the actual receiver as well as the base class: a subclass may change ABI.
    if (object_getClass(item) != recordClass && !validGetter(object_getClass(item))) {
        atomic_fetch_add(&rejectedABI, 1);
        return NO;
    }
    @try {
        long long value = ((long long (*)(id, SEL))objc_msgSend)(item, sel_registerName("recallTime"));
        return value > 0;
    } @catch (__unused NSException *exception) {
        atomic_fetch_add(&failedReads, 1);
        return NO;
    }
}
id QARFilterMessageUpdates(id payload, BOOL *shouldForward) {
    if (shouldForward) *shouldForward = YES;
    // Disabled mode must not inspect records or replace the payload.
    if (!QAREnabled() || !payload) return payload;
    if (![payload isKindOfClass:NSArray.class]) {
        atomic_fetch_add(&unknownPayloads, 1);
        return payload;
    }
    NSArray *items = payload;
    if (items.count == 0) return payload;
    Class recordClass = objc_getClass("OCMsgRecord");
    if (!validGetter(recordClass)) {
        atomic_fetch_add(&rejectedABI, 1);
        return payload;
    }
    NSMutableArray *filtered = nil;
    NSUInteger index = 0, removed = 0;
    for (id item in items) {
        atomic_fetch_add(&inspectedItems, 1);
        if (isRecalled(item, recordClass)) {
            if (!filtered) {
                filtered = [[items subarrayWithRange:NSMakeRange(0, index)] mutableCopy];
            }
            removed++;
        } else if (filtered) {
            [filtered addObject:item];
        }
        index++;
    }
    if (!removed) return payload;
    atomic_fetch_add(&removedItems, removed);
    atomic_fetch_add(&changedBatches, 1);
    QARTraceEvent(@"recalled_list_items_filtered");
    if (filtered.count == 0) {
        atomic_fetch_add(&droppedBatches, 1);
        // Do not deliver an artificial empty list: some consumers treat it as a clear.
        if (shouldForward) *shouldForward = NO;
        return nil;
    }
    atomic_fetch_add(&mixedBatches, 1);
    // Preserve identity and relative ordering of every unrelated record.
    return [filtered copy];
}
NSDictionary *QARUpdateFilterStatus(void) {
    return @{
        @"recall_update_filter_ready": @(validGetter(objc_getClass("OCMsgRecord"))),
        @"inspected_update_items": @(atomic_load(&inspectedItems)),
        @"filtered_recall_update_items": @(atomic_load(&removedItems)),
        @"filtered_update_batches": @(atomic_load(&changedBatches)),
        @"forwarded_mixed_update_batches": @(atomic_load(&mixedBatches)),
        @"dropped_recall_only_batches": @(atomic_load(&droppedBatches)),
        @"unrecognized_update_payloads": @(atomic_load(&unknownPayloads)),
        @"unrecognized_update_items": @(atomic_load(&unknownItems)),
        @"record_abi_rejections": @(atomic_load(&rejectedABI)),
        @"record_read_failures": @(atomic_load(&failedReads))
    };
}
void QARResetUpdateFilter(void) {
    atomic_store(&inspectedItems, 0);
    atomic_store(&removedItems, 0);
    atomic_store(&changedBatches, 0);
    atomic_store(&mixedBatches, 0);
    atomic_store(&droppedBatches, 0);
    atomic_store(&unknownPayloads, 0);
    atomic_store(&unknownItems, 0);
    atomic_store(&rejectedABI, 0);
    atomic_store(&failedReads, 0);
}
