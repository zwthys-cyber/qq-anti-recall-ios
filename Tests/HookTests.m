#import <Foundation/Foundation.h>
#import "QARHook.h"
#include <stdio.h>
#include <stdlib.h>

static NSUInteger forwarded, intercepted;
static BOOL enabled;
static IMP originalReceive, originalChild;
@interface QARFixture : NSObject
- (void)receive:(id)value;
- (NSInteger)count;
@end
@implementation QARFixture
- (void)receive:(id)value { (void)value; forwarded++; }
- (NSInteger)count { return 7; }
@end
@interface QARChild : QARFixture
@end
@implementation QARChild
@end
static void replacement(id self, SEL cmd, id value) {
    if (enabled) { intercepted++; return; }
    ((void (*)(id, SEL, id))originalReceive)(self, cmd, value);
}
static void childReplacement(id self, SEL cmd, id value) {
    (void)self; (void)cmd; (void)value; intercepted++;
}
static void check(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
int main(void) {
    @autoreleasepool {
        check(QARSignaturesMatch("v24@0:8@16", "v@:@"), "offsets do not change ABI");
        check(!QARSignaturesMatch("v@:@", "v@:q"), "object/integer mismatch");
        check(!QARSignaturesMatch("v@:i", "v@:q"), "32/64 bit integer mismatch");
        check(!QARSignaturesMatch("@@:@", "v@:@"), "return type mismatch");
        check(!QARSignaturesMatch("v@:@", "v@:@@"), "argument count mismatch");
        IMP scratch = NULL;
        check(QARInstallHook(Nil, @selector(receive:), "v@:@",
              (IMP)replacement, &scratch) == QARHookMissingClass, "missing class");
        check(QARInstallHook(QARFixture.class, NSSelectorFromString(@"notPresent:"),
              "v@:@", (IMP)replacement, &scratch) == QARHookMissingMethod, "missing selector");
        check(QARInstallHook(QARFixture.class, @selector(receive:),
              "v@:q", (IMP)replacement, &scratch) == QARHookSignatureMismatch, "reject wrong ABI");
        check(scratch == NULL, "rejected hook does not publish original");
        [[[QARFixture alloc] init] receive:nil];
        check(forwarded == 1, "rejected hook leaves behavior unchanged");

        check(QARInstallHook(QARChild.class, @selector(receive:), "v@:@",
              (IMP)childReplacement, &originalChild) == QARHookInstalled, "inherited method");
        [[[QARChild alloc] init] receive:nil];
        [[[QARFixture alloc] init] receive:nil];
        check(intercepted == 1 && forwarded == 2, "subclass override preserves superclass");

        check(QARInstallHook(QARFixture.class, @selector(receive:), "v@:@",
              (IMP)replacement, &originalReceive) == QARHookInstalled, "install instance hook");
        enabled = YES;
        [[[QARFixture alloc] init] receive:@"synthetic message"];
        check(intercepted == 2 && forwarded == 2, "enabled hook intercepts event");
        enabled = NO;
        [[[QARFixture alloc] init] receive:@"synthetic message"];
        check(forwarded == 3, "disabled hook forwards event");
        check([[[QARFixture alloc] init] count] == 7, "unrelated method unchanged");
        check(QARInstallHook(QARFixture.class, @selector(receive:), "v@:@",
              (IMP)replacement, &originalReceive) == QARHookInvalidArgument, "reject duplicate install");
        puts("PASS: runtime ABI guards, inherited isolation, intercept and passthrough behavior.");
    }
    return 0;
}
