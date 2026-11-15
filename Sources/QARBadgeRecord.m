#import "QARBadgeRecord.h"
#import "QARHook.h"
#import <objc/message.h>
#include <string.h>
#include <stdlib.h>

static id resolve(id object, unsigned depth, NSMutableSet *seen) {
    if (!object || depth > 3) return nil;
    NSValue *address = [NSValue valueWithNonretainedObject:object];
    if ([seen containsObject:address]) return nil;
    [seen addObject:address];
    if ([NSStringFromClass(object_getClass(object)) isEqual:@"OCMsgRecord"]) return object;
    for (NSString *field in @[@"record", @"msgRecord", @"messageRecord", @"viewModel", @"cellViewModel"]) {
        SEL selector = NSSelectorFromString(field);
        Method method = class_getInstanceMethod(object_getClass(object), selector);
        if (!method || !QARSignaturesMatch(method_getTypeEncoding(method), "@16@0:8")) continue;
        @try {
            id record = resolve(((id (*)(id, SEL))objc_msgSend)(object, selector), depth + 1, seen);
            if (record) return record;
        } @catch (__unused NSException *exception) {}
    }
    for (Class cls = object_getClass(object); cls && cls != NSObject.class; cls = class_getSuperclass(cls)) {
        unsigned count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        id result = nil;
        for (unsigned i = 0; i < count && !result; i++) {
            const char *type = ivar_getTypeEncoding(ivars[i]);
            const char *name = ivar_getName(ivars[i]);
            if (!type || type[0] != '@' || type[1] == '?' || !name) continue;
            NSString *field = [[NSString stringWithUTF8String:name] lowercaseString];
            if (![field containsString:@"record"] && ![field containsString:@"viewmodel"]) continue;
            // Runtime-provided object ivars only; never read guessed offsets or Swift value fields.
            @try { result = resolve(object_getIvar(object, ivars[i]), depth + 1, seen); }
            @catch (__unused NSException *exception) {}
        }
        free(ivars);
        if (result) return result;
    }
    return nil;
}
id QARBadgeRecord(id object) {
    return resolve(object, 0, [NSMutableSet new]);
}
