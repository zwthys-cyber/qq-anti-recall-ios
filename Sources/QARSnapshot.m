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

#include <stdatomic.h>
#include <string.h>
#include <stdlib.h>

static atomic_uint_fast64_t encodedCount, omittedCount, dynamicCount, referenceCount;
static NSMutableArray *failureSamples, *omissionSamples;
static NSObject *diagnosticLock(void) {
    static NSObject *lock; static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSObject new]; }); return lock;
}
static void note(BOOL omission, NSString *reason, NSString *path, id object) {
    NSString *name = object ? NSStringFromClass(object_getClass(object)) : @"nil";
    if (name.length > 180) name = @"unrecognized_runtime_class";
    NSDictionary *sample = @{@"reason": reason, @"field_path": path ?: @"OCMsgRecord", @"runtime_class": name};
    @synchronized(diagnosticLock()) {
        if (!failureSamples) failureSamples = [NSMutableArray new];
        if (!omissionSamples) omissionSamples = [NSMutableArray new];
        NSMutableArray *samples = omission ? omissionSamples : failureSamples;
        if (samples.count < 8 && ![samples containsObject:sample]) [samples addObject:sample];
    }
}
NSDictionary *QARSnapshotStatus(void) {
    @synchronized(diagnosticLock()) {
        return @{@"format": @2, @"records_encoded": @(atomic_load(&encodedCount)),
            @"optional_fields_omitted": @(atomic_load(&omittedCount)),
            @"runtime_model_schemas": @(atomic_load(&dynamicCount)),
            @"shared_model_references": @(atomic_load(&referenceCount)),
            @"failure_samples": [failureSamples copy] ?: @[], @"omission_samples": [omissionSamples copy] ?: @[],
            @"samples_include_values": @NO};
    }
}
void QARResetSnapshotCounters(void) {
    atomic_store(&encodedCount, 0); atomic_store(&omittedCount, 0); atomic_store(&referenceCount, 0);
    @synchronized(diagnosticLock()) { [failureSamples removeAllObjects]; [omissionSamples removeAllObjects]; }
}
static NSArray *schemaForName(NSString *name) {
    NSArray *known = QARModelSchemas()[name];
    if (known) return known;
    if (![name isKindOfClass:NSString.class] || ![name hasPrefix:@"OC"] || name.length > 180) return nil;
    Class cls = NSClassFromString(name);
    if (!cls || ![cls isSubclassOfClass:NSObject.class]) return nil;
#ifndef QAR_TESTING
    const char *image = class_getImageName(cls);
    const char *host = class_getImageName(NSClassFromString(@"OCMsgRecord"));
    if (!image || !host || strcmp(image, host) != 0) return nil;
#endif
    static NSMutableDictionary *cache; static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary new]; });
    @synchronized(cache) {
        if (cache[name]) return cache[name] == NSNull.null ? nil : cache[name];
        if (cache.count >= 256) return nil;
        unsigned count = 0; objc_property_t *properties = class_copyPropertyList(cls, &count);
        NSMutableArray *fields = [NSMutableArray new];
        BOOL rejected = count > 256;
        for (unsigned i = 0; i < count && count <= 256; i++) {
            const char *rawName = property_getName(properties[i]), *attrs = property_getAttributes(properties[i]);
            if (!rawName || !attrs || !strstr(attrs, ",V") || attrs[0] != 'T') continue;
            char kind = attrs[1];
            NSString *field = @(rawName);
            NSString *setter = [NSString stringWithFormat:@"set%@%@:", [[field substringToIndex:1] uppercaseString], [field substringFromIndex:1]];
            Method getter = class_getInstanceMethod(cls, NSSelectorFromString(field));
            Method writer = class_getInstanceMethod(cls, NSSelectorFromString(setter));
            Method codec = class_getInstanceMethod(cls, NSSelectorFromString([NSString stringWithFormat:@"setKt_%@FromCodec:", field]));
            if (!codec) continue;
            if (!strchr("@qQiIB", kind)) { rejected = YES; break; }
            NSString *getTypes = [NSString stringWithFormat:@"%c@:", kind];
            NSString *setTypes = [NSString stringWithFormat:@"v@:%c", kind];
            if (!getter || !writer || !codec ||
                !QARSignaturesMatch(method_getTypeEncoding(getter), getTypes.UTF8String) ||
                !QARSignaturesMatch(method_getTypeEncoding(writer), setTypes.UTF8String) ||
                !QARSignaturesMatch(method_getTypeEncoding(codec), "v@:@")) { rejected = YES; break; }
            [fields addObject:@{@"name": field, @"type": [NSString stringWithFormat:@"%c", kind],
                @"getter_types": getTypes, @"setter_types": setTypes}];
        }
        free(properties);
        Method init = class_getInstanceMethod(cls, @selector(init));
        if (rejected || !fields.count || !init || !QARSignaturesMatch(method_getTypeEncoding(init), "@@:")) {
            cache[name] = NSNull.null; return nil;
        }
        cache[name] = [fields copy]; atomic_fetch_add(&dynamicCount, 1);
        return cache[name];
    }
}
static NSDictionary *fieldSpec(id object, NSString *field) {
    NSArray *fields = schemaForName(NSStringFromClass(object_getClass(object)));
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
    if (![className isKindOfClass:NSString.class] || !schemaForName(className)) return nil;
    Class cls = NSClassFromString(className);
    Method method = cls ? class_getInstanceMethod(cls, @selector(init)) : NULL;
    if (!method || !QARSignaturesMatch(method_getTypeEncoding(method), "@16@0:8")) return nil;
    @try { return [[cls alloc] init]; }
    @catch (__unused NSException *exception) { return nil; }
}
static id decodeLegacy(id node, NSUInteger depth, NSUInteger *nodes, BOOL *valid) {
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
            id item = decodeLegacy(child, depth + 1, nodes, &ok);
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
            id key = decodeLegacy(pair[0], depth + 1, nodes, &a);
            id item = decodeLegacy(pair[1], depth + 1, nodes, &b);
            if (!a || !b || (![key isKindOfClass:NSString.class] && ![key isKindOfClass:NSNumber.class])) return nil;
            dictionary[key] = item ?: NSNull.null;
        }
        result = dictionary;
    } else if ([tag isEqual:@"o"] && [value isKindOfClass:NSDictionary.class]) {
        NSString *name = node[@"c"];
        if (![name isKindOfClass:NSString.class]) return nil;
        NSArray *specs = schemaForName(name);
        if (!specs || specs.count != [value count]) return nil;
        result = QARModelCreate(name);
        if (!result) return nil;
        for (NSDictionary *spec in specs) {
            BOOL ok = NO;
            id child = decodeLegacy(value[spec[@"name"]], depth + 1, nodes, &ok);
            if (!ok || !QARModelWrite(result, spec[@"name"], child)) return nil;
        }
    }
    *valid = result != nil;
    return result;
}

@interface QARGraphWriter : NSObject
@property(nonatomic,strong) NSMapTable *models;
@property(nonatomic,strong) NSHashTable *active;
@property(nonatomic,strong) NSMutableArray *registered;
@property(nonatomic) NSUInteger nodes;
@property(nonatomic,copy) NSString *failureReason;
@property(nonatomic,copy) NSString *failurePath;
@property(nonatomic,strong) id failureObject;
@end
@implementation QARGraphWriter
- (instancetype)init {
    if ((self = [super init])) {
        _models = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality
            valueOptions:NSPointerFunctionsStrongMemory];
        _active = [NSHashTable hashTableWithOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality];
        _registered = [NSMutableArray new];
    } return self;
}
@end
static id fail(QARGraphWriter *writer, NSString *reason, NSString *path, id object) {
    writer.failureReason = reason; writer.failurePath = path; writer.failureObject = object; return nil;
}
static BOOL independentElements(id record) {
    BOOL ok = NO; id elements = QARModelRead(record, @"elements", &ok);
    if (!ok || ![elements isKindOfClass:NSArray.class] || ![elements count]) return NO;
    NSDictionary *payloads = @{@1: @"textElement", @2: @"picElement", @3: @"fileElement",
        @4: @"pttElement", @5: @"videoElement", @6: @"faceElement"};
    for (id element in elements) {
        NSNumber *type = QARModelRead(element, @"elementType", &ok);
        NSString *field = ok ? payloads[type] : nil;
        if (!field || !QARModelRead(element, field, &ok) || !ok) return NO;
    }
    return YES;
}
static NSSet *requiredRecordFields(void) {
    static NSSet *fields; static dispatch_once_t once;
    dispatch_once(&once, ^{ fields = [NSSet setWithArray:@[@"msgId", @"msgRandom", @"msgSeq", @"cntSeq",
        @"chatType", @"msgType", @"subMsgType", @"sendType", @"senderUid", @"peerUid", @"channelId", @"guildId",
        @"msgTime", @"sendStatus", @"senderUin", @"peerUin", @"recallTime", @"elements", @"auxiliaryElements"]]; });
    return fields;
}
static id encodeNode(id object, NSUInteger depth, NSString *path, QARGraphWriter *writer);
static id encodeValue(id object, NSUInteger depth, NSString *path, QARGraphWriter *writer) {
    if (!object || object == NSNull.null) return @{@"t": @"n"};
    if ([object isKindOfClass:NSString.class] || [object isKindOfClass:NSData.class]) {
        if ([object length] > 262144) return fail(writer, @"value_size_limit", path, object);
        return @{@"t": [object isKindOfClass:NSString.class] ? @"s" : @"d", @"v": [object copy]};
    }
    if ([object isKindOfClass:NSNumber.class]) return @{@"t": @"v", @"v": object};
    if ([object isKindOfClass:NSDate.class]) return @{@"t": @"D", @"v": object};
    if ([object isKindOfClass:NSURL.class]) return @{@"t": @"u", @"v": [object absoluteString]};
    if ([object isKindOfClass:NSArray.class] || [object isKindOfClass:NSSet.class]) {
        if ([object count] > 4096) return fail(writer, @"collection_size_limit", path, object);
        NSMutableArray *values = [NSMutableArray new];
        for (id item in object) {
            id child = encodeNode(item, depth + 1, [path stringByAppendingString:@"[]"], writer);
            if (!child) return nil; [values addObject:child];
        }
        return @{@"t": [object isKindOfClass:NSSet.class] ? @"S" : @"a", @"v": values};
    }
    if ([object isKindOfClass:NSDictionary.class]) {
        if ([object count] > 4096) return fail(writer, @"collection_size_limit", path, object);
        NSMutableArray *pairs = [NSMutableArray new];
        for (id key in object) {
            if (![key isKindOfClass:NSString.class] && ![key isKindOfClass:NSNumber.class])
                return fail(writer, @"unsupported_dictionary_key", [path stringByAppendingString:@"{key}"], key);
            id k = encodeNode(key, depth + 1, [path stringByAppendingString:@"{key}"], writer);
            id v = encodeNode(object[key], depth + 1, [path stringByAppendingString:@"{value}"], writer);
            if (!k || !v) return nil; [pairs addObject:@[k, v]];
        }
        return @{@"t": @"m", @"v": pairs};
    }
    NSString *name = NSStringFromClass(object_getClass(object));
    NSArray *specs = schemaForName(name);
    if (!specs) return fail(writer, @"unsupported_model_class", path, object);
    NSNumber *identifier = @(writer.registered.count + 1);
    [writer.models setObject:identifier forKey:object]; [writer.registered addObject:object];
    BOOL record = [name isEqual:@"OCMsgRecord"], selfContained = record && independentElements(object);
    NSMutableDictionary *fields = [NSMutableDictionary new];
    for (NSDictionary *spec in specs) {
        NSString *field = spec[@"name"], *fieldPath = [path stringByAppendingFormat:@".%@", field];
        BOOL optional = record && ![requiredRecordFields() containsObject:field] &&
            (![field isEqual:@"records"] || selfContained);
        NSUInteger checkpoint = writer.registered.count, nodeCheckpoint = writer.nodes;
        BOOL valid = NO; id raw = QARModelRead(object, field, &valid);
        id value = valid ? encodeNode(raw, depth + 1, fieldPath, writer) :
            fail(writer, @"field_reader_rejected", fieldPath, object);
        if (!value) {
            if (!optional) return nil;
            note(YES, writer.failureReason ?: @"field_unavailable", writer.failurePath ?: fieldPath, writer.failureObject);
            atomic_fetch_add(&omittedCount, 1);
            while (writer.registered.count > checkpoint) {
                [writer.models removeObjectForKey:writer.registered.lastObject];
                [writer.registered removeLastObject];
            }
            writer.nodes = nodeCheckpoint;
            continue;
        }
        fields[field] = value;
    }
    return @{@"t": @"o2", @"c": name, @"id": identifier, @"v": fields};
}
static id encodeNode(id object, NSUInteger depth, NSString *path, QARGraphWriter *writer) {
    if (depth > 24 || ++writer.nodes > 16384) return fail(writer, @"graph_limit", path, object);
    if (object && [writer.active containsObject:object]) return fail(writer, @"cyclic_reference", path, object);
    NSNumber *existing = object ? [writer.models objectForKey:object] : nil;
    if (existing) { atomic_fetch_add(&referenceCount, 1); return @{@"t": @"r", @"id": existing}; }
    if (object) [writer.active addObject:object];
    @try { return encodeValue(object, depth, path, writer); }
    @catch (__unused NSException *error) { return fail(writer, @"collection_or_model_exception", path, object); }
    @finally { if (object) [writer.active removeObject:object]; }
}
static BOOL validID(id value) {
    return [value isKindOfClass:NSNumber.class] && [value unsignedLongLongValue] > 0 &&
        [value unsignedLongLongValue] <= 16384 && [value isEqual:@([value unsignedLongLongValue])];
}
static BOOL collectModels(id node, NSUInteger depth, NSUInteger *count, NSMutableDictionary *definitions) {
    if (++*count > 16384 || depth > 24 || ![node isKindOfClass:NSDictionary.class]) return NO;
    NSString *tag = node[@"t"]; id value = node[@"v"];
    if (![tag isKindOfClass:NSString.class]) return NO;
    if ([tag isEqual:@"o2"]) {
        id identifier = node[@"id"], name = node[@"c"];
        if (!validID(identifier) || definitions[identifier] || ![name isKindOfClass:NSString.class] ||
            !schemaForName(name) || ![value isKindOfClass:NSDictionary.class] || [value count] > 256) return NO;
        definitions[identifier] = node;
        for (id child in [value allValues]) if (!collectModels(child, depth + 1, count, definitions)) return NO;
    } else if ([tag isEqual:@"a"] || [tag isEqual:@"S"] || [tag isEqual:@"m"]) {
        if (![value isKindOfClass:NSArray.class] || [value count] > 4096) return NO;
        for (id child in value) {
            if ([tag isEqual:@"m"]) {
                if (![child isKindOfClass:NSArray.class] || [child count] != 2) return NO;
                if (!collectModels(child[0], depth + 1, count, definitions) ||
                    !collectModels(child[1], depth + 1, count, definitions)) return NO;
            } else if (!collectModels(child, depth + 1, count, definitions)) return NO;
        }
    } else if ([tag isEqual:@"r"]) return validID(node[@"id"]);
    else if (![@[@"n", @"s", @"v", @"d", @"D", @"u"] containsObject:tag]) return NO;
    return YES;
}
// Validate the reference graph before allocating models; shared DAG nodes are allowed,
// cyclic or unresolved references in a damaged local archive are rejected.
static BOOL validateReferences(id node, NSDictionary *definitions, NSMutableSet *active, NSMutableSet *done, NSMutableArray *order, NSUInteger depth) {
    if (depth > 48) return NO;
    NSString *tag = node[@"t"]; id value = node[@"v"];
    if ([tag isEqual:@"o2"] || [tag isEqual:@"r"]) {
        NSNumber *ident = node[@"id"];
        if (!definitions[ident] || [active containsObject:ident]) return NO;
        if ([done containsObject:ident]) return YES;
        [active addObject:ident];
        for (id child in [definitions[ident][@"v"] allValues])
            if (!validateReferences(child, definitions, active, done, order, depth + 1)) return NO;
        [active removeObject:ident]; [done addObject:ident]; [order addObject:ident]; return YES;
    }
    if ([tag isEqual:@"a"] || [tag isEqual:@"S"] || [tag isEqual:@"m"]) for (id child in value) {
        if ([tag isEqual:@"m"]) {
            if (!validateReferences(child[0], definitions, active, done, order, depth + 1) ||
                !validateReferences(child[1], definitions, active, done, order, depth + 1)) return NO;
        } else if (!validateReferences(child, definitions, active, done, order, depth + 1)) return NO;
    }
    return YES;
}
static id decodeValue(id node, NSDictionary *models, BOOL *ok) {
    *ok = NO;
    NSString *tag = node[@"t"]; id value = node[@"v"], result = nil;
    if ([tag isEqual:@"n"]) { *ok = YES; return nil; }
    if ([tag isEqual:@"o2"] || [tag isEqual:@"r"]) result = models[node[@"id"]];
    else if ([tag isEqual:@"s"] && [value isKindOfClass:NSString.class]) result = [value mutableCopy];
    else if ([tag isEqual:@"v"] && [value isKindOfClass:NSNumber.class]) result = value;
    else if ([tag isEqual:@"d"] && [value isKindOfClass:NSData.class]) result = [value mutableCopy];
    else if ([tag isEqual:@"D"] && [value isKindOfClass:NSDate.class]) result = value;
    else if ([tag isEqual:@"u"] && [value isKindOfClass:NSString.class]) result = [NSURL URLWithString:value];
    else if ([tag isEqual:@"a"] || [tag isEqual:@"S"]) {
        NSMutableArray *items = [NSMutableArray new];
        for (id nodeValue in value) {
            BOOL childOK = NO; id child = decodeValue(nodeValue, models, &childOK);
            if (!childOK) return nil; [items addObject:child ?: NSNull.null];
        }
        result = [tag isEqual:@"S"] ? [NSMutableSet setWithArray:items] : items;
    } else if ([tag isEqual:@"m"]) {
        NSMutableDictionary *dictionary = [NSMutableDictionary new];
        for (NSArray *pair in value) {
            BOOL a = NO, b = NO; id key = decodeValue(pair[0], models, &a), item = decodeValue(pair[1], models, &b);
            if (!a || !b || (![key isKindOfClass:NSString.class] && ![key isKindOfClass:NSNumber.class])) return nil;
            dictionary[key] = item ?: NSNull.null;
        }
        result = dictionary;
    }
    *ok = result != nil; return result;
}
NSData *QAREncodeRecord(id record) {
    if (![NSStringFromClass(object_getClass(record)) isEqual:@"OCMsgRecord"]) {
        note(NO, @"unsupported_root", @"OCMsgRecord", record); return nil;
    }
    QARGraphWriter *writer = [QARGraphWriter new];
    id graph = encodeNode(record, 0, @"OCMsgRecord", writer);
    if (!graph) { note(NO, writer.failureReason ?: @"unknown", writer.failurePath, writer.failureObject); return nil; }
    @try {
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:@{@"format": @2, @"record": graph}
            format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
        if (!data || data.length > 262144) {
            note(NO, data ? @"snapshot_size_limit" : @"plist_serialization", @"OCMsgRecord", record); return nil;
        }
        atomic_fetch_add(&encodedCount, 1); return data;
    } @catch (__unused NSException *error) { note(NO, @"plist_exception", @"OCMsgRecord", record); return nil; }
}
id QARDecodeRecord(NSData *data) {
    if (![data isKindOfClass:NSData.class] || !data.length || data.length > 262144) return nil;
    @try {
        id envelope = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:nil];
        if (![envelope isKindOfClass:NSDictionary.class]) return nil;
        if (![envelope[@"format"] isEqual:@2]) {
            if (![envelope[@"c"] isEqual:@"OCMsgRecord"]) return nil;
            NSUInteger nodes = 0; BOOL valid = NO;
            id record = decodeLegacy(envelope, 0, &nodes, &valid); return valid ? record : nil;
        }
        id graph = envelope[@"record"];
        if (![graph isKindOfClass:NSDictionary.class] || ![graph[@"t"] isEqual:@"o2"] ||
            ![graph[@"c"] isEqual:@"OCMsgRecord"]) return nil;
        NSMutableDictionary *definitions = [NSMutableDictionary new], *models = [NSMutableDictionary new];
        NSUInteger count = 0;
        NSMutableArray *order = [NSMutableArray new];
        if (!collectModels(graph, 0, &count, definitions) ||
            !validateReferences(graph, definitions, [NSMutableSet new], [NSMutableSet new], order, 0)) return nil;
        for (NSNumber *identifier in order) {
            id model = QARModelCreate(definitions[identifier][@"c"]);
            if (!model) return nil; models[identifier] = model;
        }
        for (NSNumber *identifier in order) {
            NSDictionary *definition = definitions[identifier], *fields = definition[@"v"];
            NSArray *specs = schemaForName(definition[@"c"]);
            NSSet *names = [NSSet setWithArray:[specs valueForKey:@"name"]];
            if (![[NSSet setWithArray:fields.allKeys] isSubsetOfSet:names]) return nil;
            BOOL record = [definition[@"c"] isEqual:@"OCMsgRecord"];
            if (record) {
                if (![requiredRecordFields() isSubsetOfSet:[NSSet setWithArray:fields.allKeys]]) return nil;
            } else if (fields.count != specs.count) return nil;
            // Match QQ's inspected schema order (identity before content), with each
            // child object already populated in dependency order.
            for (NSDictionary *spec in specs) {
                NSString *field = spec[@"name"];
                if (!fields[field]) continue;
                BOOL ok = NO; id child = decodeValue(fields[field], models, &ok);
                if (!ok || !QARModelWrite(models[identifier], field, child)) return nil;
            }
        }
        id result = models[graph[@"id"]];
        BOOL valid = NO; id elements = QARModelRead(result, @"elements", &valid);
        if (!valid || ![elements isKindOfClass:NSArray.class] || ![elements count]) return nil;
        return result;
    } @catch (__unused NSException *error) { return nil; }
}
