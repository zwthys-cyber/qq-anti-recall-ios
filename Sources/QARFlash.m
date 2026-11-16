#import "QARFlash.h"
#import "QARHook.h"
#import "QARAdapter.h"
#import "QARStore.h"
#import "QARSnapshot.h"
#import <objc/message.h>
#import <QuickLook/QuickLook.h>
#import <CommonCrypto/CommonDigest.h>
#include <stdatomic.h>

static IMP original;
static QARHookResult result = QARHookMissingClass;
static dispatch_queue_t storage;
static NSURL *root;
static atomic_ullong calls, saved, failures, unsupported, recordLookups, recordMatches;
BOOL QARFlashEnabled(void) { return [NSUserDefaults.standardUserDefaults boolForKey:@"QARFlashRetentionEnabled"]; }
void QARSetFlashEnabled(BOOL enabled) {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:@"QARFlashRetentionEnabled"];
    [NSNotificationCenter.defaultCenter postNotificationName:QARStoreChangedNotification object:nil];
}
static NSString *pathKey(id path) {
    if (![path isKindOfClass:NSString.class] || ![path length] || [path length] > 4096) return nil;
    NSString *home = [NSHomeDirectory() stringByResolvingSymlinksInPath];
    NSString *normalized = [path stringByResolvingSymlinksInPath];
    // Sandbox UUID changes after reinstall; retain a stable app-relative key.
    if ([normalized hasPrefix:[home stringByAppendingString:@"/"]]) normalized = [normalized substringFromIndex:home.length];
    NSData *bytes = [normalized dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(bytes.bytes, (CC_LONG)bytes.length, digest);
    NSMutableString *key = [NSMutableString new];
    for (unsigned i=0; i<sizeof(digest); i++) [key appendFormat:@"%02x", digest[i]];
    return key;
}
static void prepare(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        storage = dispatch_queue_create("QQAntiRecall.flash", DISPATCH_QUEUE_SERIAL);
        NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        root = [support URLByAppendingPathComponent:@"QQAntiRecall/Flash-v1" isDirectory:YES];
    });
}
static NSArray<NSURL *> *files(NSString *owner) {
    if (!owner) return @[];
    NSArray *items = [NSFileManager.defaultManager contentsOfDirectoryAtURL:[root URLByAppendingPathComponent:owner]
        includingPropertiesForKeys:@[NSURLCreationDateKey, NSURLFileSizeKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    NSMutableArray *images = [NSMutableArray new];
    for (NSURL *url in items) if ([url.pathExtension isEqual:@"png"]) [images addObject:url];
    return [images sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        NSDate *x, *y; [a getResourceValue:&x forKey:NSURLCreationDateKey error:nil];
        [b getResourceValue:&y forKey:NSURLCreationDateKey error:nil];
        return [(y ?: NSDate.distantPast) compare:(x ?: NSDate.distantPast)];
    }];
}
static UIImage *decodedImage(id value) {
    if ([value isKindOfClass:UIImage.class]) return value;
    NSData *data = nil;
    if ([value isKindOfClass:NSData.class] && [value length] <= 16*1024*1024) data = value;
    else if ([value isKindOfClass:NSString.class]) {
        NSString *path = [value stringByResolvingSymlinksInPath];
        NSString *home = [NSHomeDirectory() stringByResolvingSymlinksInPath];
        if (![path hasPrefix:[home stringByAppendingString:@"/"]]) return nil;
        NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
        if (![attrs[NSFileType] isEqual:NSFileTypeRegular] || [attrs[NSFileSize] unsignedLongLongValue] > 16*1024*1024) return nil;
        data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    }
    return data ? [UIImage imageWithData:data] : nil;
}
static void capture(id value, NSString *owner, id sourcePath) {
    if (!owner || !QARFlashEnabled() || ![owner isEqual:QARCurrentOwner()]) return;
    UIImage *image = decodedImage(value);
    if (!image || image.size.width * image.scale * image.size.height * image.scale > 32000000) {
        atomic_fetch_add(&unsupported, 1); return;
    }
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1; format.opaque = NO; format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
    CGSize pixels = CGSizeMake(image.size.width * image.scale, image.size.height * image.scale);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:pixels format:format];
    UIImage *canonical = [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
        [image drawInRect:(CGRect){CGPointZero, pixels}];
    }];
    NSData *data = UIImagePNGRepresentation(canonical);
    if (!data.length || data.length > 16*1024*1024) { atomic_fetch_add(&failures, 1); return; }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *name = [NSMutableString new];
    for (unsigned i = 0; i < sizeof(digest); i++) [name appendFormat:@"%02x", digest[i]];
    prepare();
    dispatch_sync(storage, ^{
        if (!QARFlashEnabled() || ![owner isEqual:QARCurrentOwner()]) return;
        NSURL *directory = [root URLByAppendingPathComponent:owner isDirectory:YES];
        NSFileManager *manager = NSFileManager.defaultManager;
        NSDictionary *attributes = @{NSFilePosixPermissions: @0700, NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication};
        if (![manager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:attributes error:nil]) {
            atomic_fetch_add(&failures, 1); return;
        }
        [directory setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
        NSURL *target = [directory URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]];
        BOOL exists = [manager fileExistsAtPath:target.path];
        if (!exists && ![data writeToURL:target options:NSDataWritingAtomic | NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:nil]) {
            atomic_fetch_add(&failures, 1); return;
        }
        [manager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:target.path error:nil];
        [target setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
        if (!exists) atomic_fetch_add(&saved, 1);
        unsigned long long bytes = 0; NSUInteger count = 0;
        for (NSURL *url in files(owner)) {
            NSNumber *size; [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
            bytes += size.unsignedLongLongValue;
            if (++count > 100 || bytes > 128*1024*1024) [manager removeItemAtURL:url error:nil];
        }
        NSString *key = pathKey(sourcePath);
        if (key && [manager fileExistsAtPath:target.path]) {
            NSURL *indexURL = [directory URLByAppendingPathComponent:@"paths.plist"];
            NSMutableDictionary *index = [[NSDictionary dictionaryWithContentsOfURL:indexURL] mutableCopy] ?: [NSMutableDictionary new];
            for (NSString *oldKey in index.allKeys) {
                id name = index[oldKey];
                if (![name isKindOfClass:NSString.class] || ![name isEqual:[name lastPathComponent]] ||
                    ![manager fileExistsAtPath:[directory URLByAppendingPathComponent:name].path]) [index removeObjectForKey:oldKey];
            }
            if (index.count >= 512 && !index[key]) [index removeObjectForKey:index.allKeys.firstObject];
            index[key] = target.lastPathComponent;
            NSData *encoded = [NSPropertyListSerialization dataWithPropertyList:index format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
            if (![encoded writeToURL:indexURL options:NSDataWritingAtomic | NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:nil])
                atomic_fetch_add(&failures, 1);
            [manager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:indexURL.path error:nil];
        }
    });
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:QARStoreChangedNotification object:nil];
    });
}
static id decryptImage(id receiver, SEL selector, id path) {
    atomic_fetch_add(&calls, 1);
    NSString *owner = QARFlashEnabled() ? QARCurrentOwner() : nil;
    id value = ((id (*)(id, SEL, id))original)(receiver, selector, path);
    @try { capture(value, owner, path); }
    @catch (__unused NSException *error) { atomic_fetch_add(&failures, 1); }
    return value;
}
void QARInstallFlash(NSDictionary *info) {
    if (!QARVersionSupported(info) || original) return;
    result = QARInstallHook(object_getClass(NSClassFromString(@"PhotoBrowserFlashPictureService")),
        NSSelectorFromString(@"decryptImageWithImagePath:"), "@24@0:8@16", (IMP)decryptImage, &original);
}
NSArray<NSURL *> *QARFlashFiles(void) {
    prepare(); NSString *owner = QARCurrentOwner(); __block NSArray *resultFiles;
    dispatch_sync(storage, ^{ resultFiles = files(owner); }); return resultFiles;
}
void QARClearFlash(void) {
    prepare(); NSString *owner = QARCurrentOwner(); if (!owner) return;
    dispatch_sync(storage, ^{ [NSFileManager.defaultManager removeItemAtURL:[root URLByAppendingPathComponent:owner] error:nil]; });
    [NSNotificationCenter.defaultCenter postNotificationName:QARStoreChangedNotification object:nil];
}
NSDictionary *QARFlashStatus(void) {
    Class cls = object_getClass(NSClassFromString(@"PhotoBrowserFlashPictureService"));
    return @{@"enabled": @(QARFlashEnabled()), @"replay_location": @"chat_message_footer", @"hook_result": @(result), @"installed_hooks": @(original != NULL),
        @"hook_active": @(original && class_getMethodImplementation(cls, NSSelectorFromString(@"decryptImageWithImagePath:")) == (IMP)decryptImage),
        @"decrypt_calls": @(atomic_load(&calls)), @"images_saved": @(atomic_load(&saved)),
        @"save_failures": @(atomic_load(&failures)), @"unsupported_results": @(atomic_load(&unsupported)),
        @"chat_record_lookups": @(atomic_load(&recordLookups)), @"chat_record_matches": @(atomic_load(&recordMatches)),
        @"saved_images_current_account": @(QARFlashFiles().count), @"maximum_images": @100,
        @"maximum_bytes": @(128*1024*1024), @"uploads_images": @NO, @"runtime_verified": @NO};
}
@interface QARFlashPreview : QLPreviewController <QLPreviewControllerDataSource>
@property(nonatomic,strong) NSArray<NSURL *> *images;
@property(nonatomic,copy) NSString *owner;
@end
@implementation QARFlashPreview
- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.dataSource = self;
    for (NSString *name in @[QARStoreChangedNotification, UIApplicationDidBecomeActiveNotification])
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(checkOwner:) name:name object:nil];
    return self;
}
- (void)checkOwner:(NSNotification *)note {
    (void)note;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!QARFlashEnabled() || ![self.owner isEqual:QARCurrentOwner()] || ![NSFileManager.defaultManager fileExistsAtPath:self.images.firstObject.path]) {
            self.images = @[];
            if (self.isViewLoaded) { self.view.hidden = YES; [self reloadData]; }
            // A switch/account change can arrive while Quick Look is still presenting.
            // Hide content immediately and dismiss after the presentation transition.
            id<UIViewControllerTransitionCoordinator> coordinator = self.transitionCoordinator;
            if (self.isBeingPresented && coordinator) {
                [coordinator animateAlongsideTransition:nil completion:^(__unused id<UIViewControllerTransitionCoordinatorContext> context) {
                    [self dismissViewControllerAnimated:NO completion:nil];
                }];
            } else [self dismissViewControllerAnimated:NO completion:nil];
        }
    });
}
- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller {
    (void)controller; return QARFlashEnabled() && [self.owner isEqual:QARCurrentOwner()] ? self.images.count : 0;
}
- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
    (void)controller; return QARFlashEnabled() && [self.owner isEqual:QARCurrentOwner()] && index >= 0 && (NSUInteger)index < self.images.count ? self.images[index] : nil;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
@end
static NSURL *fileForPaths(NSArray *paths, NSString *owner) {
    prepare(); __block NSURL *found = nil;
    dispatch_sync(storage, ^{
        NSURL *directory = [root URLByAppendingPathComponent:owner];
        NSDictionary *index = [NSDictionary dictionaryWithContentsOfURL:[directory URLByAppendingPathComponent:@"paths.plist"]];
        for (id path in paths) {
            NSString *key = pathKey(path); id name = key ? index[key] : nil;
            if (![name isKindOfClass:NSString.class] || ![name isEqual:[name lastPathComponent]] || ![[name pathExtension] isEqual:@"png"]) continue;
            NSURL *candidate = [directory URLByAppendingPathComponent:name];
            if ([NSFileManager.defaultManager fileExistsAtPath:candidate.path]) { found = candidate; break; }
        }
    });
    return found;
}
NSURL *QARFlashURLForRecord(id record) {
    NSString *owner = QARCurrentOwner();
    if (!QARFlashEnabled() || !owner || ![NSStringFromClass(object_getClass(record)) isEqual:@"OCMsgRecord"]) return nil;
    id elements = QARModelRead(record, @"elements", NULL);
    if (![elements isKindOfClass:NSArray.class] || [elements count] > 256) return nil;
    for (id element in elements) {
        id pic = QARModelRead(element, @"picElement", NULL);
        if (![NSStringFromClass(object_getClass(pic)) isEqual:@"OCPicElement"]) continue;
        id flash = QARModelRead(pic, @"isFlashPic", NULL);
        if (![flash isKindOfClass:NSNumber.class] || ![flash boolValue]) continue;
        atomic_fetch_add(&recordLookups, 1);
        NSMutableArray *paths = [NSMutableArray new];
        id source = QARModelRead(pic, @"sourcePath", NULL);
        if ([source isKindOfClass:NSString.class]) [paths addObject:source];
        Class service = NSClassFromString(@"_TtC20AIOChatServiceModule23NTAIOChatMessageService");
        for (NSString *name in @[@"getFlashPicNormalFilePathWithPicElement:isOrigin:", @"getFlashPicResultFilePathWithPicElement:isOrigin:"]) {
            SEL selector = NSSelectorFromString(name);
            Method method = class_getClassMethod(service, selector);
            if (!method || !QARSignaturesMatch(method_getTypeEncoding(method), "@28@0:8@16B24")) continue;
            for (unsigned flag=0; flag<2; flag++) {
                @try {
                    id path = ((id (*)(id,SEL,id,_Bool))objc_msgSend)(service, selector, pic, flag != 0);
                    if ([path isKindOfClass:NSString.class]) [paths addObject:path];
                } @catch (__unused NSException *exception) {}
            }
        }
        NSURL *url = fileForPaths(paths, owner);
        if (url && [owner isEqual:QARCurrentOwner()]) { atomic_fetch_add(&recordMatches, 1); return url; }
    }
    return nil;
}
void QARPresentFlashRecord(UIViewController *presenter, id record) {
    if (!NSThread.isMainThread || !presenter || presenter.presentedViewController) return;
    NSURL *url = QARFlashURLForRecord(record); if (!url) return;
    QARFlashPreview *preview = [QARFlashPreview new]; preview.images = @[url]; preview.owner = QARCurrentOwner();
    [presenter presentViewController:preview animated:YES completion:nil];
}
#ifdef QAR_TESTING
void QARFlashUseTestDirectory(NSURL *directory) {
    prepare(); dispatch_sync(storage, ^{ root = directory; });
}
#endif
