#import "ModelFixtures.h"
#import "QARSnapshot.h"
#import <objc/runtime.h>
#include <stdatomic.h>

static char valuesKey;
static atomic_ullong account = 10001;
static NSMutableDictionary *values(id object) {
    NSMutableDictionary *result = objc_getAssociatedObject(object, &valuesKey);
    if (!result) {
        result = [NSMutableDictionary new];
        objc_setAssociatedObject(object, &valuesKey, result, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return result;
}
static NSString *fieldForSetter(id object, SEL selector) {
    NSString *name = NSStringFromSelector(selector);
    for (NSDictionary *spec in QARModelSchemas()[NSStringFromClass(object_getClass(object))]) {
        NSString *field = spec[@"name"];
        NSString *setter = [NSString stringWithFormat:@"set%@%@:",
            [[field substringToIndex:1] uppercaseString], [field substringFromIndex:1]];
        if ([name isEqual:setter]) return field;
    }
    return nil;
}
static id getObject(id self, SEL cmd) { return values(self)[NSStringFromSelector(cmd)]; }
static void setObject(id self, SEL cmd, id value) {
    NSString *key = fieldForSetter(self, cmd);
    if (value) values(self)[key] = value;
    else [values(self) removeObjectForKey:key];
}
#define ACCESSOR(NAME, TYPE, CONVERT) \
static TYPE get##NAME(id self, SEL cmd) { return [getObject(self, cmd) CONVERT]; } \
static void set##NAME(id self, SEL cmd, TYPE value) { setObject(self, cmd, @(value)); }
ACCESSOR(Signed, long long, longLongValue)
ACCESSOR(Unsigned, unsigned long long, unsignedLongLongValue)
ACCESSOR(Int, int, intValue)
ACCESSOR(UInt, unsigned int, unsignedIntValue)
ACCESSOR(Bool, BOOL, boolValue)
#undef ACCESSOR
@interface QQAccountsManager : NSObject
+ (instancetype)GetInstance;
- (unsigned long long)currentUin;
@end
@implementation QQAccountsManager
+ (instancetype)GetInstance { static id manager; static dispatch_once_t once;
    dispatch_once(&once, ^{ manager = [self new]; }); return manager; }
- (unsigned long long)currentUin { return atomic_load(&account); }
@end
void QARFixtureAccount(unsigned long long value) { atomic_store(&account, value); }
void QARFixtureModels(void) {
    for (NSString *name in QARModelSchemas()) {
        Class cls = objc_allocateClassPair(NSObject.class, name.UTF8String, 0);
        NSCAssert(cls, @"Fixture class must be new");
        for (NSDictionary *spec in QARModelSchemas()[name]) {
            IMP get = NULL, set = NULL;
            switch ([spec[@"type"] characterAtIndex:0]) {
                case '@': get = (IMP)getObject; set = (IMP)setObject; break;
                case 'q': get = (IMP)getSigned; set = (IMP)setSigned; break;
                case 'Q': get = (IMP)getUnsigned; set = (IMP)setUnsigned; break;
                case 'i': get = (IMP)getInt; set = (IMP)setInt; break;
                case 'I': get = (IMP)getUInt; set = (IMP)setUInt; break;
                case 'B': get = (IMP)getBool; set = (IMP)setBool; break;
                default: NSCAssert(NO, @"Unsupported fixture scalar");
            }
            NSString *field = spec[@"name"];
            NSString *setter = [NSString stringWithFormat:@"set%@%@:",
                [[field substringToIndex:1] uppercaseString], [field substringFromIndex:1]];
            class_addMethod(cls, NSSelectorFromString(field), get, [spec[@"getter_types"] UTF8String]);
            class_addMethod(cls, NSSelectorFromString(setter), set, [spec[@"setter_types"] UTF8String]);
        }
        objc_registerClassPair(cls);
    }
}
id QARFixtureMessage(long long msgID, long long seq, NSString *peer, long long recall, NSString *body) {
    id record = QARModelCreate(@"OCMsgRecord");
    QARModelWrite(record, @"msgId", @(msgID));
    QARModelWrite(record, @"msgSeq", @(seq));
    QARModelWrite(record, @"chatType", @1);
    QARModelWrite(record, @"peerUid", peer);
    QARModelWrite(record, @"recallTime", @(recall));
    if (body) {
        id text = QARModelCreate(@"OCTextElement"), element = QARModelCreate(@"OCMsgElement");
        QARModelWrite(text, @"content", body);
        QARModelWrite(element, @"elementType", @1);
        QARModelWrite(element, @"textElement", text);
        QARModelWrite(record, @"elements", [NSMutableArray arrayWithObject:element]);
    }
    return record;
}
NSString *QARFixtureBody(id record) {
    NSArray *elements = QARModelRead(record, @"elements", NULL);
    return QARModelRead(QARModelRead(elements.firstObject, @"textElement", NULL), @"content", NULL);
}
NSDictionary *QARFixtureInfo(void) {
    return @{@"CFBundleShortVersionString": @"9.3.86", @"CFBundleVersion": @"9.3.86.617", @"CFBundleExecutable": @"QQ"};
}
