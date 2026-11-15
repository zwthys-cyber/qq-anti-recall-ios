#import "QARFlash.h"
#import "QARHook.h"
#import "QARAdapter.h"
#import "QARStore.h"
#import <QuickLook/QuickLook.h>
#import <CommonCrypto/CommonDigest.h>
#include <stdatomic.h>

static IMP original;
static QARHookResult result = QARHookMissingClass;
static dispatch_queue_t storage;
static NSURL *root;
static atomic_ullong calls, saved, failures, unsupported;
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
static void capture(id value, NSString *owner) {
    if (!owner || !QAREnabled() || ![owner isEqual:QARCurrentOwner()]) return;
    UIImage *image = decodedImage(value);
    if (!image || image.size.width * image.scale * image.size.height * image.scale > 32000000) {
        atomic_fetch_add(&unsupported, 1); return;
    }
    NSData *data = UIImagePNGRepresentation(image);
    if (!data.length || data.length > 16*1024*1024) { atomic_fetch_add(&failures, 1); return; }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *name = [NSMutableString new];
    for (unsigned i = 0; i < sizeof(digest); i++) [name appendFormat:@"%02x", digest[i]];
    prepare();
    dispatch_sync(storage, ^{
        if (!QAREnabled() || ![owner isEqual:QARCurrentOwner()]) return;
        NSURL *directory = [root URLByAppendingPathComponent:owner isDirectory:YES];
        NSFileManager *manager = NSFileManager.defaultManager;
        NSDictionary *attributes = @{NSFilePosixPermissions: @0700, NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication};
        if (![manager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:attributes error:nil]) {
            atomic_fetch_add(&failures, 1); return;
        }
        [directory setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
        NSURL *target = [directory URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]];
        if ([manager fileExistsAtPath:target.path]) return;
        if (![data writeToURL:target options:NSDataWritingAtomic | NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:nil]) {
            atomic_fetch_add(&failures, 1); return;
        }
        [manager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:target.path error:nil];
        [target setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
        atomic_fetch_add(&saved, 1);
        unsigned long long bytes = 0; NSUInteger count = 0;
        for (NSURL *url in files(owner)) {
            NSNumber *size; [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
            bytes += size.unsignedLongLongValue;
            if (++count > 100 || bytes > 128*1024*1024) [manager removeItemAtURL:url error:nil];
        }
    });
}
static id decryptImage(id receiver, SEL selector, id path) {
    atomic_fetch_add(&calls, 1);
    NSString *owner = QAREnabled() ? QARCurrentOwner() : nil;
    id value = ((id (*)(id, SEL, id))original)(receiver, selector, path);
    @try { capture(value, owner); }
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
    return @{@"hook_result": @(result), @"installed_hooks": @(original != NULL),
        @"hook_active": @(original && class_getMethodImplementation(cls, NSSelectorFromString(@"decryptImageWithImagePath:")) == (IMP)decryptImage),
        @"decrypt_calls": @(atomic_load(&calls)), @"images_saved": @(atomic_load(&saved)),
        @"save_failures": @(atomic_load(&failures)), @"unsupported_results": @(atomic_load(&unsupported)),
        @"saved_images_current_account": @(QARFlashFiles().count), @"maximum_images": @100,
        @"maximum_bytes": @(128*1024*1024), @"uploads_images": @NO, @"runtime_verified": @NO};
}
@interface QARFlashPreview : QLPreviewController <QLPreviewControllerDataSource>
@property(nonatomic,strong) NSArray<NSURL *> *images;
@property(nonatomic,copy) NSString *owner;
@end
@implementation QARFlashPreview
- (void)viewDidLoad {
    [super viewDidLoad]; self.dataSource = self;
    for (NSString *name in @[QARStoreChangedNotification, UIApplicationDidBecomeActiveNotification])
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(checkOwner:) name:name object:nil];
}
- (void)checkOwner:(NSNotification *)note {
    (void)note;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self.owner isEqual:QARCurrentOwner()] || !QARFlashFiles().count) {
            self.images = @[]; [self reloadData]; [self dismissViewControllerAnimated:YES completion:nil];
        }
    });
}
- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller {
    (void)controller; return [self.owner isEqual:QARCurrentOwner()] ? self.images.count : 0;
}
- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
    (void)controller; return [self.owner isEqual:QARCurrentOwner()] && index >= 0 && (NSUInteger)index < self.images.count ? self.images[index] : nil;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
@end
void QARPresentFlash(UIViewController *presenter) {
    NSArray *images = QARFlashFiles();
    if (!images.count) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"暂无保留的闪照"
            message:@"开启防撤回后打开新收到的闪照。成功保存的图片会出现在这里，可反复查看。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
        [presenter presentViewController:alert animated:YES completion:nil]; return;
    }
    QARFlashPreview *preview = [QARFlashPreview new]; preview.images = images; preview.owner = QARCurrentOwner();
    [presenter presentViewController:preview animated:YES completion:nil];
}
#ifdef QAR_TESTING
void QARFlashUseTestDirectory(NSURL *directory) {
    prepare(); dispatch_sync(storage, ^{ root = directory; });
}
#endif
