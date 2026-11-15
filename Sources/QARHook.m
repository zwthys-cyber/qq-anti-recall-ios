#import "QARHook.h"
#include <string.h>

BOOL QARSignaturesMatch(const char *actual, const char *expected) {
    if (!actual || !expected) return NO;
    NSMethodSignature *a = [NSMethodSignature signatureWithObjCTypes:actual];
    NSMethodSignature *b = [NSMethodSignature signatureWithObjCTypes:expected];
    if (!a || !b || a.numberOfArguments != b.numberOfArguments ||
        strcmp(a.methodReturnType, b.methodReturnType) != 0) return NO;
    for (NSUInteger i = 0; i < a.numberOfArguments; i++) {
        if (strcmp([a getArgumentTypeAtIndex:i], [b getArgumentTypeAtIndex:i]) != 0)
            return NO;
    }
    return YES;
}

QARHookResult QARInstallHook(Class cls, SEL selector, const char *expected,
                            IMP replacement, IMP *original) {
    if (!cls) return QARHookMissingClass;
    if (!selector || !expected || !replacement || !original || *original)
        return QARHookInvalidArgument;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return QARHookMissingMethod;
    const char *encoding = method_getTypeEncoding(method);
    if (!QARSignaturesMatch(encoding, expected)) return QARHookSignatureMismatch;
    // Publish the original before the replacement can be dispatched.
    *original = method_getImplementation(method);
    if (!class_addMethod(cls, selector, replacement, encoding)) {
        *original = method_setImplementation(method, replacement);
    }
    return QARHookInstalled;
}
