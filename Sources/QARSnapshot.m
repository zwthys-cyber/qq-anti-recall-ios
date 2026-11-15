#import "QARSnapshot.h"
#import "QARHook.h"
#import <objc/message.h>
#import "QARModelSchema.inc"

NSDictionary *QARModelSchemas(void) {
    static NSDictionary *schemas;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSData *data = [NSData dataWithBytes:QARSchemaJSON length:sizeof(QARSchemaJSON)-1];
        schemas = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    });
    return schemas;
}
static NSDictionary *fieldSpec(id object, NSString *field) {
    NSArray *fields = QARModelSchemas()[NSStringFromClass(object_getClass(object))];
    for (NSDictionary *spec in fields) if ([spec[@"name"] isEqual:field]) return spec;
    return nil;
}
static NSString *setterName(NSString *field) {
    return [NSString stringWithFormat:@"set%@%@:", [[field substringToIndex:1] uppercaseString],
        [field substringFromIndex:1]];
}
id QARModelRead(id object, NSString *field, BOOL *valid) {
    if (valid) *valid = NO;
    NSDictionary *spec = object ? fieldSpec(object, field) : nil;
    if (!spec) return nil;
    SEL selector = NSSelectorFromString(field);
    Method method = class_getInstanceMethod(object_getClass(object), selector);
    if (!method || !QARSignaturesMatch(method_getTypeEncoding(method), [spec[@"getter_types"] UTF8String])) return nil;
    id value;
    @try {
        switch ([spec[@"type"] characterAtIndex:0]) {
            case '@': value = ((id (*)(id, SEL))objc_msgSend)(object, selector); break;
            case 'q': value = @(((long long (*)(id, SEL))objc_msgSend)(object, selector)); break;
            case 'Q': value = @(((unsigned long long (*)(id, SEL))objc_msgSend)(object, selector)); break;
            case 'i': value = @(((int (*)(id, SEL))objc_msgSend)(object, selector)); break;
            case 'I': value = @(((unsigned int (*)(id, SEL))objc_msgSend)(object, selector)); break;
            case 'B': value = @(((BOOL (*)(id, SEL))objc_msgSend)(object, selector)); break;
            default: return nil;
        }
    } @catch (__unused NSException *exception) { return nil; }
    if (valid) *valid = YES;
    return value;
}
BOOL QARModelWrite(id object, NSString *field, id value) {
    NSDictionary *spec = object ? fieldSpec(object, field) : nil;
    if (!spec) return NO;
    SEL selector = NSSelectorFromString(setterName(field));
    Method method = class_getInstanceMethod(object_getClass(object), selector);
    if (!method || !QARSignaturesMatch(method_getTypeEncoding(method), [spec[@"setter_types"] UTF8String])) return NO;
    unichar kind = [spec[@"type"] characterAtIndex:0];
    if (kind != '@' && ![value isKindOfClass:NSNumber.class]) return NO;
    @try {
        switch (kind) {
            case '@': ((void (*)(id, SEL, id))objc_msgSend)(object, selector, value); break;
            case 'q': ((void (*)(id, SEL, long long))objc_msgSend)(object, selector, [value longLongValue]); break;
            case 'Q': ((void (*)(id, SEL, unsigned long long))objc_msgSend)(object, selector, [value unsignedLongLongValue]); break;
            case 'i': ((void (*)(id, SEL, int))objc_msgSend)(object, selector, [value intValue]); break;
            case 'I': ((void (*)(id, SEL, unsigned int))objc_msgSend)(object, selector, [value unsignedIntValue]); break;
            case 'B': ((void (*)(id, SEL, BOOL))objc_msgSend)(object, selector, [value boolValue]); break;
            default: return NO;
        }
    } @catch (__unused NSException *exception) { return NO; }
    return YES;
}
id QARModelCreate(NSString *className) {
    if (![className isKindOfClass:NSString.class] || !QARModelSchemas()[className]) return nil;
    Class cls = NSClassFromString(className);
    Method method = cls ? class_getInstanceMethod(cls, @selector(init)) : NULL;
    if (!method || !QARSignaturesMatch(method_getTypeEncoding(method), "@16@0:8")) return nil;
    @try { return [[cls alloc] init]; }
    @catch (__unused NSException *exception) { return nil; }
}
static id encode(id object, NSUInteger depth, NSUInteger *nodes) {
    if (depth > 16 || ++*nodes > 8192) return nil;
    if (!object || object == NSNull.null) return @{@"t": @"n"};
    if ([object isKindOfClass:NSString.class]) {
        if ([object length] > 262144) return nil;
        return @{@"t": @"s", @"v": [object copy]};
    }
    if ([object isKindOfClass:NSNumber.class]) return @{@"t": @"v", @"v": object};
    if ([object isKindOfClass:NSData.class]) {
        if ([object length] > 262144) return nil;
        return @{@"t": @"d", @"v": [object copy]};
    }
    if ([object isKindOfClass:NSDate.class]) return @{@"t": @"D", @"v": object};
    if ([object isKindOfClass:NSURL.class]) return @{@"t": @"u", @"v": [object absoluteString]};
    if ([object isKindOfClass:NSArray.class] || [object isKindOfClass:NSSet.class]) {
        if ([object count] > 4096) return nil;
        NSMutableArray *values = [NSMutableArray new];
        for (id item in object) {
            id value = encode(item, depth + 1, nodes);
            if (!value) return nil;
            [values addObject:value];
        }
        return @{@"t": [object isKindOfClass:NSSet.class] ? @"S" : @"a", @"v": values};
    }
    if ([object isKindOfClass:NSDictionary.class]) {
        if ([object count] > 4096) return nil;
        NSMutableArray *pairs = [NSMutableArray new];
        for (id key in object) {
            if (![key isKindOfClass:NSString.class] && ![key isKindOfClass:NSNumber.class]) return nil;
            id k = encode(key, depth + 1, nodes), v = encode(object[key], depth + 1, nodes);
            if (!k || !v) return nil;
            [pairs addObject:@[k, v]];
        }
        return @{@"t": @"m", @"v": pairs};
    }
    NSString *name = NSStringFromClass(object_getClass(object));
    NSArray *specs = QARModelSchemas()[name];
    if (!specs) return nil; // Never call NSCoder or traverse an unreviewed class.
    NSMutableDictionary *fields = [NSMutableDictionary new];
    for (NSDictionary *spec in specs) {
        BOOL valid = NO;
        id raw = QARModelRead(object, spec[@"name"], &valid);
        if (!valid) return nil;
        id value = encode(raw, depth + 1, nodes);
        if (!value) return nil;
        fields[spec[@"name"]] = value;
    }
    return @{@"t": @"o", @"c": name, @"v": fields};
}
static id decode(id node, NSUInteger depth, NSUInteger *nodes, BOOL *valid) {
    *valid = NO;
    if (depth > 16 || ++*nodes > 8192 || ![node isKindOfClass:NSDictionary.class]) return nil;
    NSString *tag = node[@"t"];
    id value = node[@"v"], result = nil;
    if (![tag isKindOfClass:NSString.class]) return nil;
    if ([tag isEqual:@"n"]) { *valid = YES; return nil; }
    if ([tag isEqual:@"s"] && [value isKindOfClass:NSString.class]) result = [value mutableCopy];
    else if ([tag isEqual:@"v"] && [value isKindOfClass:NSNumber.class]) result = value;
    else if ([tag isEqual:@"d"] && [value isKindOfClass:NSData.class]) result = [value mutableCopy];
    else if ([tag isEqual:@"D"] && [value isKindOfClass:NSDate.class]) result = value;
    else if ([tag isEqual:@"u"] && [value isKindOfClass:NSString.class]) result = [NSURL URLWithString:value];
    else if (([tag isEqual:@"a"] || [tag isEqual:@"S"]) && [value isKindOfClass:NSArray.class]) {
        if ([value count] > 4096) return nil;
        NSMutableArray *array = [NSMutableArray new];
        for (id child in value) {
            BOOL ok = NO;
            id item = decode(child, depth + 1, nodes, &ok);
            if (!ok) return nil;
            [array addObject:item ?: NSNull.null];
        }
        result = [tag isEqual:@"S"] ? [NSMutableSet setWithArray:array] : array;
    } else if ([tag isEqual:@"m"] && [value isKindOfClass:NSArray.class]) {
        if ([value count] > 4096) return nil;
        NSMutableDictionary *dictionary = [NSMutableDictionary new];
        for (id pair in value) {
            if (![pair isKindOfClass:NSArray.class] || [pair count] != 2) return nil;
            BOOL a = NO, b = NO;
            id key = decode(pair[0], depth + 1, nodes, &a);
            id item = decode(pair[1], depth + 1, nodes, &b);
            if (!a || !b || (![key isKindOfClass:NSString.class] && ![key isKindOfClass:NSNumber.class])) return nil;
            dictionary[key] = item ?: NSNull.null;
        }
        result = dictionary;
    } else if ([tag isEqual:@"o"] && [value isKindOfClass:NSDictionary.class]) {
        NSString *name = node[@"c"];
        if (![name isKindOfClass:NSString.class]) return nil;
        NSArray *specs = QARModelSchemas()[name];
        if (!specs || specs.count != [value count]) return nil;
        result = QARModelCreate(name);
        if (!result) return nil;
        for (NSDictionary *spec in specs) {
            BOOL ok = NO;
            id child = decode(value[spec[@"name"]], depth + 1, nodes, &ok);
            if (!ok || !QARModelWrite(result, spec[@"name"], child)) return nil;
        }
    }
    *valid = result != nil;
    return result;
}
NSData *QAREncodeRecord(id record) {
    if (![NSStringFromClass(object_getClass(record)) isEqual:@"OCMsgRecord"]) return nil;
    @try {
        NSUInteger nodes = 0;
        id graph = encode(record, 0, &nodes);
        if (!graph) return nil;
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:graph
            format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
        return data.length <= 262144 ? data : nil;
    } @catch (__unused NSException *exception) { return nil; }
}
id QARDecodeRecord(NSData *data) {
    if (![data isKindOfClass:NSData.class] || !data.length || data.length > 262144) return nil;
    @try {
        id graph = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:nil];
        if (![graph isKindOfClass:NSDictionary.class] || ![graph[@"c"] isEqual:@"OCMsgRecord"]) return nil;
        NSUInteger nodes = 0;
        BOOL valid = NO;
        id record = decode(graph, 0, &nodes, &valid);
        return valid ? record : nil;
    } @catch (__unused NSException *exception) { return nil; }
}
