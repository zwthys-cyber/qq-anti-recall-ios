#import <Foundation/Foundation.h>
#import <objc/runtime.h>

typedef NS_ENUM(NSInteger, QARHookResult) {
    QARHookInstalled,
    QARHookMissingClass,
    QARHookMissingMethod,
    QARHookSignatureMismatch,
    QARHookInvalidArgument
};

// Compares ABI types, ignoring encoded stack offsets.
BOOL QARSignaturesMatch(const char *actual, const char *expected);
// Adds an override when the method is inherited; never modifies a superclass.
QARHookResult QARInstallHook(Class cls, SEL selector, const char *expected,
                            IMP replacement, IMP *original);
