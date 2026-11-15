#import "QARStore.h"
#import "QARSnapshot.h"
#import "QARAdapter.h"
#import "QARHook.h"
#import "QARTrace.h"
#import <objc/message.h>
#import <CommonCrypto/CommonDigest.h>
#import <TargetConditionals.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>

NSString * const QARStoreChangedNotification = @"QQAntiRecall.StoreChanged";
static dispatch_queue_t queue;
static char recordOwnerKey;
static NSURL *root;
static NSString *loadedOwner;
static NSMutableDictionary *entries;
static BOOL pendingWrite;
static atomic_uint_fast64_t savedCount, restoreCount, missCount, encodeFailures, decodeFailures;
static atomic_uint_fast64_t diskFailures, missingOwner, evictions, markedCount;
static atomic_bool diskReady;
static const NSUInteger maxEntries = 512, maxBytes = 16 * 1024 * 1024;

static void prepare(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("QQAntiRecall.local-storage", DISPATCH_QUEUE_SERIAL);
        NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                             inDomains:NSUserDomainMask].firstObject;
        root = [support URLByAppendingPathComponent:@"QQAntiRecall/Snapshots-v1" isDirectory:YES];
    });
}
static NSString *digest(NSData *data) {
    if (!data || data.length > UINT32_MAX) return nil;
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    NSMutableString *text = [NSMutableString stringWithCapacity:64];
    for (unsigned i = 0; i < sizeof(hash); i++) [text appendFormat:@"%02x", hash[i]];
    return text;
}
static NSString *hashValues(NSArray *values) {
    return digest([NSJSONSerialization dataWithJSONObject:values options:0 error:nil]);
}
NSString *QARCurrentOwner(void) {
    Class cls = objc_getClass("QQAccountsManager");
    SEL get = sel_registerName("GetInstance"), current = sel_registerName("currentUin");
    Method factory = cls ? class_getClassMethod(cls, get) : NULL;
    if (!factory || !QARSignaturesMatch(method_getTypeEncoding(factory), "@16@0:8")) return nil;
    @try {
        id manager = ((id (*)(id, SEL))objc_msgSend)(cls, get);
        if (![manager isKindOfClass:cls]) return nil;
        Method getter = class_getInstanceMethod(object_getClass(manager), current);
        if (!getter || !QARSignaturesMatch(method_getTypeEncoding(getter), "Q16@0:8")) return nil;
        unsigned long long uin = ((unsigned long long (*)(id, SEL))objc_msgSend)(manager, current);
        return uin ? hashValues(@[@"QQ9.3.86.617", [NSString stringWithFormat:@"%llu", uin]]) : nil;
    } @catch (__unused NSException *exception) { return nil; }
}
static NSDictionary *identity(id record) {
    BOOL ok = NO;
    NSNumber *msgID = QARModelRead(record, @"msgId", &ok);
    if (!ok) return nil;
    NSNumber *seq = QARModelRead(record, @"msgSeq", &ok);
    if (!ok) return nil;
    NSNumber *chat = QARModelRead(record, @"chatType", &ok);
    if (!ok || chat.intValue <= 0) return nil;
    NSString *peer = QARModelRead(record, @"peerUid", &ok);
    if (!ok || ![peer isKindOfClass:NSString.class] || !peer.length || peer.length > 1024) return nil;
    id channel = QARModelRead(record, @"channelId", &ok);
    if (!ok || (channel && ![channel isKindOfClass:NSString.class])) return nil;
    id guild = QARModelRead(record, @"guildId", &ok);
    if (!ok || (guild && ![guild isKindOfClass:NSString.class])) return nil;
    NSString *scope = hashValues(@[chat, peer, channel ?: @"", guild ?: @""]);
    NSString *sequenceKey = seq.longLongValue > 0 ? hashValues(@[scope, @"seq", seq.stringValue]) : @"";
    NSString *key = msgID.longLongValue != 0 ? hashValues(@[scope, @"id", msgID.stringValue]) : sequenceKey;
    if (!key.length) return nil;
    return @{@"key": key, @"seq": sequenceKey, @"scope": scope, @"msg_id": msgID};
}
static BOOL validIdentity(id value) {
    if (![value isKindOfClass:NSDictionary.class]) return NO;
    for (NSString *key in @[@"key", @"scope", @"seq"]) {
        id part = value[key];
        if (![part isKindOfClass:NSString.class] ||
            !([part length] == 64 || ([key isEqual:@"seq"] && [part length] == 0))) return NO;
    }
    return [value[@"msg_id"] isKindOfClass:NSNumber.class];
}
static NSURL *fileForOwner(NSString *owner) {
    return [root URLByAppendingPathComponent:[owner stringByAppendingString:@".plist"]];
}
static void loadOwner(NSString *owner) {
    if ([loadedOwner isEqual:owner]) return;
    loadedOwner = [owner copy];
    pendingWrite = NO;
    entries = [NSMutableDictionary new];
    NSURL *file = fileForOwner(owner);
    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:file.path error:nil];
    if (!attrs) return;
    if (![attrs[NSFileType] isEqual:NSFileTypeRegular] ||
        [attrs[NSFileSize] unsignedLongLongValue] > 32 * 1024 * 1024) return;
    NSData *data = [NSData dataWithContentsOfURL:file];
    id envelope = data ? [NSPropertyListSerialization propertyListWithData:data
                 options:NSPropertyListImmutable format:NULL error:nil] : nil;
    if (![envelope isKindOfClass:NSDictionary.class] ||
        ![envelope[@"schema"] isEqual:@"qar-local-v1"] ||
        ![envelope[@"owner"] isEqual:owner] ||
        ![envelope[@"entries"] isKindOfClass:NSDictionary.class]) return;
    NSDictionary *stored = envelope[@"entries"];
    if (stored.count > maxEntries) return;
    NSUInteger bytes = 0;
    for (id key in stored) {
        id entry = stored[key], payload = [entry isKindOfClass:NSDictionary.class] ? entry[@"data"] : nil;
        if (![entry isKindOfClass:NSDictionary.class] || ![key isKindOfClass:NSString.class] || !validIdentity(entry[@"identity"]) ||
            ![key isEqual:entry[@"identity"][@"key"]] ||
            ![entry[@"when"] isKindOfClass:NSNumber.class] ||
            ![entry[@"recalled"] isKindOfClass:NSNumber.class] ||
            (payload && (![payload isKindOfClass:NSData.class] || [payload length] > 262144))) return;
        id aliases = entry[@"local_ids"];
        if (aliases) {
            if (![aliases isKindOfClass:NSArray.class] || [aliases count] > 16) return;
            for (id value in aliases) if (![value isKindOfClass:NSNumber.class]) return;
        }
        bytes += [payload length];
        if (bytes > maxBytes) return;
    }
    [entries addEntriesFromDictionary:stored];
}
static NSString *findKey(NSDictionary *wanted) {
    NSDictionary *exact = entries[wanted[@"key"]];
    if (exact) {
        NSString *a = exact[@"identity"][@"seq"], *b = wanted[@"seq"];
        if (![exact[@"identity"][@"scope"] isEqual:wanted[@"scope"]] ||
            (a.length && b.length && ![a isEqual:b])) return nil;
        return wanted[@"key"];
    }
    if (![wanted[@"seq"] length]) return nil;
    NSString *match = nil;
    for (NSString *key in entries) {
        if ([entries[key][@"identity"][@"seq"] isEqual:wanted[@"seq"]]) {
            if (match) return nil; // Ambiguous sequence matches must never restore another message.
            match = key;
        }
    }
    return match;
}
static void trim(void) {
    NSUInteger bytes = 0;
    for (NSDictionary *entry in entries.allValues) bytes += [entry[@"data"] length];
    if (entries.count <= maxEntries && bytes <= maxBytes) return;
    NSArray *keys = [entries.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [entries[a][@"when"] compare:entries[b][@"when"]];
    }];
    for (NSString *key in keys) {
        if (entries.count <= maxEntries && bytes <= maxBytes) break;
        bytes -= [entries[key][@"data"] length];
        [entries removeObjectForKey:key];
        atomic_fetch_add(&evictions, 1);
    }
}
static BOOL writeOwner(NSString *owner) {
    NSMutableDictionary *attrs = [@{NSFilePosixPermissions: @0700} mutableCopy];
#if TARGET_OS_IOS
    attrs[NSFileProtectionKey] = NSFileProtectionCompleteUntilFirstUserAuthentication;
#endif
    NSFileManager *manager = NSFileManager.defaultManager;
    if (![manager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:attrs error:nil]) {
        atomic_fetch_add(&diskFailures, 1); atomic_store(&diskReady, false); pendingWrite = YES; return NO;
    }
    [root setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:
        @{@"schema": @"qar-local-v1", @"owner": owner, @"entries": entries}
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    NSDataWritingOptions options = NSDataWritingAtomic;
#if TARGET_OS_IOS
    options |= NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication;
#endif
    NSURL *file = fileForOwner(owner);
    BOOL saved = data && [data writeToURL:file options:options error:nil];
    if (saved) [manager setAttributes:@{NSFilePosixPermissions: @0600} ofItemAtPath:file.path error:nil];
    else atomic_fetch_add(&diskFailures, 1);
    atomic_store(&diskReady, saved);
    pendingWrite = !saved;
    return saved;
}
static void changed(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:QARStoreChangedNotification object:nil];
    });
}
static NSNumber *recallValue(id record) {
    BOOL ok = NO;
    id value = QARModelRead(record, @"recallTime", &ok);
    return ok && [value isKindOfClass:NSNumber.class] ? value : nil;
}
void QARRememberMessages(id messages) {
    if (!QAREnabled() || ![messages isKindOfClass:NSArray.class]) return;
    NSString *owner = QARCurrentOwner();
    if (!owner) { atomic_fetch_add(&missingOwner, 1); return; }
    NSMutableArray *candidates = [NSMutableArray new];
    NSUInteger attempted = 0;
    for (id record in messages) {
        if (++attempted > 128) break;
        NSNumber *recall = recallValue(record);
        if (!recall || recall.longLongValue > 0) continue;
        objc_setAssociatedObject(record, &recordOwnerKey, owner, OBJC_ASSOCIATION_COPY_NONATOMIC);
        NSDictionary *key = identity(record);
        BOOL ok = NO;
        id elements = QARModelRead(record, @"elements", &ok);
        if (!key || !ok || ![elements isKindOfClass:NSArray.class] || ![elements count]) continue;
        NSData *data = QAREncodeRecord(record);
        if (!data) { atomic_fetch_add(&encodeFailures, 1); continue; }
        [candidates addObject:@{@"identity": key, @"data": data}];
    }
    if (!candidates.count || ![owner isEqual:QARCurrentOwner()]) return;
    prepare();
    dispatch_sync(queue, ^{
        loadOwner(owner);
        NSUInteger count = 0;
        for (NSDictionary *candidate in candidates) {
            NSString *key = candidate[@"identity"][@"key"];
            NSDictionary *old = entries[key];
            if (([old[@"recalled"] boolValue] && old[@"data"]) || [old[@"data"] isEqual:candidate[@"data"]]) continue;
            entries[key] = @{@"identity": candidate[@"identity"], @"data": candidate[@"data"],
                             @"recalled": old[@"recalled"] ?: @NO, @"when": @(NSDate.date.timeIntervalSince1970)};
            count++;
        }
        if (count || pendingWrite) {
            trim();
            if (writeOwner(owner)) atomic_fetch_add(&savedCount, count);
        }
    });
}
void QARMarkRecalledUpdates(id messages) {
    if (!QAREnabled() || ![messages isKindOfClass:NSArray.class]) return;
    NSString *owner = QARCurrentOwner();
    if (!owner) return;
    NSMutableArray *keys = [NSMutableArray new];
    for (id record in messages) {
        if (recallValue(record).longLongValue <= 0) continue;
        NSDictionary *key = identity(record);
        if (key) [keys addObject:key];
    }
    if (!keys.count || ![owner isEqual:QARCurrentOwner()]) return;
    prepare();
    __block BOOL modified = NO;
    dispatch_sync(queue, ^{
        loadOwner(owner);
        for (NSDictionary *wanted in keys) {
            NSString *key = findKey(wanted) ?: wanted[@"key"];
            NSDictionary *old = entries[key];
            NSMutableArray *aliases = [old[@"local_ids"] mutableCopy] ?: [NSMutableArray new];
            NSNumber *localID = wanted[@"msg_id"];
            BOOL newAlias = localID.longLongValue != 0 && ![aliases containsObject:localID] &&
                ![old[@"identity"][@"msg_id"] isEqual:localID];
            if ([old[@"recalled"] boolValue] && !newAlias) continue;
            if (newAlias) {
                [aliases addObject:localID];
                if (aliases.count > 16) [aliases removeObjectAtIndex:0];
            }
            NSMutableDictionary *entry = old ? [old mutableCopy] :
                [@{@"identity": wanted, @"when": @(NSDate.date.timeIntervalSince1970)} mutableCopy];
            entry[@"recalled"] = @YES;
            entry[@"local_ids"] = aliases;
            entries[key] = entry;
            if (![old[@"recalled"] boolValue]) atomic_fetch_add(&markedCount, 1);
            modified = YES;
        }
        if (modified || pendingWrite) { trim(); writeOwner(owner); }
    });
    if (modified) changed();
}
id QARRestoreHistory(id messages) {
    if (!QAREnabled() || ![messages isKindOfClass:NSArray.class]) return messages;
    QARRememberMessages(messages);
    NSString *owner = QARCurrentOwner();
    if (!owner) return messages;
    prepare();
    NSMutableArray *result = nil;
    NSMutableArray *restoredNotices = [NSMutableArray new];
    NSUInteger index = 0;
    for (id incoming in messages) {
        id replacement = nil;
        if (recallValue(incoming).longLongValue > 0) {
            NSDictionary *wanted = identity(incoming);
            __block NSData *data = nil;
            if (wanted) dispatch_sync(queue, ^{
                loadOwner(owner);
                NSString *key = findKey(wanted);
                if (key) data = entries[key][@"data"];
            });
            if (data) {
                id restored = QARDecodeRecord(data);
                NSDictionary *restoredID = restored ? identity(restored) : nil;
                BOOL same = restoredID && [restoredID[@"scope"] isEqual:wanted[@"scope"]] &&
                    ([restoredID[@"key"] isEqual:wanted[@"key"]] ||
                     ([wanted[@"seq"] length] && [restoredID[@"seq"] isEqual:wanted[@"seq"]]));
                if (same && recallValue(restored) && recallValue(restored).longLongValue <= 0) {
                    // A history query may use a different local ID for the same server sequence.
                    BOOL ok = NO;
                    id localID = QARModelRead(incoming, @"msgId", &ok);
                    if (ok && QARModelWrite(restored, @"msgId", localID)) replacement = restored;
                }
                if (!replacement) atomic_fetch_add(&decodeFailures, 1);
            } else atomic_fetch_add(&missCount, 1);
        }
        if (replacement) {
            objc_setAssociatedObject(replacement, &recordOwnerKey, owner, OBJC_ASSOCIATION_COPY_NONATOMIC);
            [restoredNotices addObject:incoming];
            if (!result) result = [[messages subarrayWithRange:NSMakeRange(0, index)] mutableCopy];
            [result addObject:replacement];
            atomic_fetch_add(&restoreCount, 1);
            QARTraceEvent(@"history_record_restored");
        } else if (result) [result addObject:incoming];
        index++;
    }
    if (![owner isEqual:QARCurrentOwner()]) return messages;
    // A history placeholder alone is not evidence that we retained its original.
    QARMarkRecalledUpdates(restoredNotices);
    return result ? [result copy] : messages;
}
BOOL QARIsMarkedRecord(id record) {
    if (!QAREnabled()) return NO;
    NSNumber *recall = recallValue(record);
    if (!recall || recall.longLongValue > 0) return NO;
    NSString *owner = QARCurrentOwner();
    NSString *recordOwner = objc_getAssociatedObject(record, &recordOwnerKey);
    if (recordOwner && ![recordOwner isEqual:owner]) return NO;
    NSDictionary *wanted = owner ? identity(record) : nil;
    if (!wanted) return NO;
    prepare();
    __block BOOL marked = NO;
    dispatch_sync(queue, ^{
        loadOwner(owner);
        NSString *key = findKey(wanted);
        if (key) marked = [entries[key][@"recalled"] boolValue];
    });
    return marked && [owner isEqual:QARCurrentOwner()];
}
void QARForgetMessageIDs(id ids) {
    if (![ids isKindOfClass:NSArray.class]) return;
    NSString *owner = QARCurrentOwner();
    if (!owner) return;
    NSMutableSet *values = [NSMutableSet new];
    for (id value in ids) if ([value isKindOfClass:NSNumber.class]) [values addObject:value];
    if (!values.count) return;
    prepare();
    dispatch_sync(queue, ^{
        loadOwner(owner);
        BOOL modified = NO;
        for (NSString *key in [entries.allKeys copy]) {
            NSArray *aliases = entries[key][@"local_ids"] ?: @[];
            BOOL aliasMatch = NO;
            for (NSNumber *value in aliases) if ([values containsObject:value]) { aliasMatch = YES; break; }
            if (aliasMatch || [values containsObject:entries[key][@"identity"][@"msg_id"]]) {
                [entries removeObjectForKey:key]; modified = YES;
            }
        }
        if (modified) writeOwner(owner);
    });
    changed();
}
void QARClearSavedMessages(void) {
    NSString *owner = QARCurrentOwner();
    if (!owner) return;
    prepare();
    dispatch_sync(queue, ^{
        loadOwner(owner);
        [entries removeAllObjects];
        writeOwner(owner);
    });
    changed();
}
NSDictionary *QARStoreStatus(void) {
    NSString *owner = QARCurrentOwner();
    return @{@"account_context_available": @(owner != nil), @"last_disk_write_succeeded": @(atomic_load(&diskReady)),
        @"snapshots_saved": @(atomic_load(&savedCount)), @"history_records_restored": @(atomic_load(&restoreCount)),
        @"snapshot_misses": @(atomic_load(&missCount)), @"snapshot_encode_failures": @(atomic_load(&encodeFailures)),
        @"snapshot_decode_failures": @(atomic_load(&decodeFailures)),
        @"snapshot_codec": QARSnapshotStatus(), @"disk_failures": @(atomic_load(&diskFailures)),
        @"missing_account_context": @(atomic_load(&missingOwner)), @"evicted_snapshots": @(atomic_load(&evictions)),
        @"marked_recalled_messages": @(atomic_load(&markedCount)), @"maximum_records_per_account": @(maxEntries),
        @"maximum_snapshot_bytes_per_account": @(maxBytes), @"content_storage": @"local_app_only",
        @"diagnostics_include_message_contents": @NO, @"uploads_message_contents": @NO};
}
void QARResetStoreCounters(void) {
    QARResetSnapshotCounters();
    atomic_store(&savedCount, 0); atomic_store(&restoreCount, 0); atomic_store(&missCount, 0);
    atomic_store(&encodeFailures, 0); atomic_store(&decodeFailures, 0); atomic_store(&diskFailures, 0);
    atomic_store(&missingOwner, 0); atomic_store(&evictions, 0); atomic_store(&markedCount, 0);
}
#ifdef QAR_TESTING
void QARStoreUseTestDirectory(NSURL *directory) {
    prepare();
    dispatch_sync(queue, ^{ root = directory; loadedOwner = nil; entries = nil; });
}
void QARStoreDropMemoryForTest(void) {
    prepare();
    dispatch_sync(queue, ^{ loadedOwner = nil; entries = nil; });
}
#endif
