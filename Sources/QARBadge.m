#import "QARBadge.h"
#import "QARBadgeRecord.h"
#import "QARAdapter.h"
#import "QARHook.h"
#import "QARStore.h"
#import "QARFlash.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <math.h>
#include <stdatomic.h>

@interface QARRecallPill : UIView
@property(nonatomic,strong) UILabel *label;
@property(nonatomic,strong) UIImageView *icon;
@property(nonatomic,weak) id replayRecord;
@property(nonatomic,copy) NSString *replayOwner;
@end
@implementation QARRecallPill
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(replay)]];
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = @"消息已撤回，原内容已保留";
    self.accessibilityTraits = UIAccessibilityTraitStaticText;
    self.label = [UILabel new];
    self.label.text = @"已撤回 · 已保留";
    self.label.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption2]
        scaledFontForFont:[UIFont systemFontOfSize:11 weight:UIFontWeightMedium]];
    self.label.adjustsFontForContentSizeCategory = YES;
    UIColor *ink = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ?
            [UIColor colorWithRed:0.46 green:0.85 blue:0.91 alpha:1] :
            [UIColor colorWithRed:0.08 green:0.43 blue:0.51 alpha:1];
    }];
    self.label.textColor = ink;
    self.icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.uturn.backward.circle.fill"]];
    self.icon.tintColor = ink;
    self.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ?
            [UIColor colorWithRed:0.10 green:0.23 blue:0.27 alpha:1] :
            [UIColor colorWithRed:0.91 green:0.96 blue:0.98 alpha:1];
    }];
    self.layer.cornerRadius = 9;
    [self addSubview:self.icon];
    [self addSubview:self.label];
    return self;
}
- (void)replay {
    if (!self.replayRecord || ![self.replayOwner isEqual:QARCurrentOwner()]) return;
    UIResponder *responder = self;
    while (responder && ![responder isKindOfClass:UIViewController.class]) responder = responder.nextResponder;
    if (responder) QARPresentFlashRecord((UIViewController *)responder, self.replayRecord);
}
- (CGSize)sizeThatFits:(CGSize)size {
    CGSize label = [self.label sizeThatFits:size];
    return CGSizeMake(ceil(label.width) + 34, ceil(label.height) + 6);
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = self.bounds.size.height;
    self.layer.cornerRadius = h / 2;
    self.icon.frame = CGRectMake(8, (h - 12) / 2, 12, 12);
    self.label.frame = CGRectMake(25, 3, MAX(0, self.bounds.size.width - 32), h - 6);
}
@end


@interface QARBadgeCellState : NSObject
@property(nonatomic,strong) QARRecallPill *pill;
@property(nonatomic,weak) id record;
@property(nonatomic,weak) UITableView *table;
@property(nonatomic,copy) NSIndexPath *path;
@property(nonatomic,copy) NSString *owner;
@property(nonatomic) BOOL marked;
@property(nonatomic) BOOL flash;
@property(nonatomic) CGFloat reserved;
@property(nonatomic) CGFloat baseHeight;
@property(nonatomic) NSUInteger attempts;
@property(nonatomic) BOOL reportedUnavailable;
@property(nonatomic) CGRect bubbleFrame;
@property(nonatomic) NSUInteger contentEpoch;
@property(nonatomic) CFTimeInterval contentCheckedAt;
@end
@implementation QARBadgeCellState @end
@interface QARBadgeTableState : NSObject
@property(nonatomic,strong) NSMapTable<NSIndexPath *, UITableViewCell *> *rows;
@property(nonatomic) BOOL pending;
@property(nonatomic) BOOL requestedAtBottom;
@property(nonatomic) CGFloat requestedOffsetY;
@end
@implementation QARBadgeTableState
- (instancetype)init { if ((self = [super init])) _rows = [NSMapTable strongToWeakObjectsMapTable]; return self; }
@end
@interface QARDelegateHook : NSObject
@property(nonatomic) Class target;
@property(nonatomic) IMP original;
@property(nonatomic) IMP replacement;
@property(nonatomic) QARHookResult result;
@property(nonatomic) unsigned long long calls;
@end
@implementation QARDelegateHook @end

@interface QARCellHook : NSObject
@property(nonatomic) Class target;
@property(nonatomic) SEL selector;
@property(nonatomic) IMP original;
@property(nonatomic) IMP replacement;
@property(nonatomic) QARHookResult result;
@property(nonatomic) unsigned long long calls;
@end
@implementation QARCellHook @end
static NSMutableArray<QARCellHook *> *actualCellHooks;
static void ensureActualCell(UITableViewCell *cell);
static char stateKey, tableKey;
static NSHashTable<UITableViewCell *> *visibleCells;
static NSMutableArray<QARDelegateHook *> *delegateHooks;
static BOOL versionReady;
static NSUInteger contentEpoch = 1;
static atomic_uint_fast64_t contentChecks, contentCacheHits;
static _Thread_local unsigned heightDepth;
static atomic_uint_fast64_t noTable, detachedTable, rejectedOrigin, deferredHeightUpdates;
static atomic_uint_fast64_t displayed, unresolved, heightChanges, recordsFound, missingPath;
static atomic_uint_fast64_t heightCalls, reservedRows, missingHeightMethod, delegateABIRejects, autoHeights;
static atomic_uint_fast64_t staticCalls[8];
static void avatarWindow(id self, SEL cmd);
static void avatarSuperview(id self, SEL cmd);
static void avatarLayout(id self, SEL cmd);
static void avatarRecord(id self, SEL cmd, id record);
static BOOL bindCell(id self, SEL cmd, id model);
static void reuseCell(id self, SEL cmd);
static void unbindCell(id self, SEL cmd);
static void layoutCell(id self, SEL cmd);
typedef struct { const char *cls, *selector, *types; IMP replacement, original; QARHookResult result; } BadgeEntry;
static BadgeEntry hooks[] = {
    {"QQNTAIOMessageAvatarView", "layoutSubviews", "v16@0:8", (IMP)avatarLayout, NULL, QARHookMissingClass},
    {"_TtC6AIOLib7AIOCell", "bindViewModel:", "B24@0:8@16", (IMP)bindCell, NULL, QARHookMissingClass},
    {"_TtC6AIOLib7AIOCell", "prepareForReuse", "v16@0:8", (IMP)reuseCell, NULL, QARHookMissingClass},
    {"_TtC6AIOLib7AIOCell", "unbindViewModel", "v16@0:8", (IMP)unbindCell, NULL, QARHookMissingClass},
    {"_TtC6AIOLib7AIOCell", "layoutSubviews", "v16@0:8", (IMP)layoutCell, NULL, QARHookMissingClass},
    {"QQNTAIOMessageAvatarView", "setRecord:", "v24@0:8@16", (IMP)avatarRecord, NULL, QARHookMissingClass},
    {"QQNTAIOMessageAvatarView", "didMoveToWindow", "v@:", (IMP)avatarWindow, NULL, QARHookMissingClass},
    {"QQNTAIOMessageAvatarView", "didMoveToSuperview", "v@:", (IMP)avatarSuperview, NULL, QARHookMissingClass}
};
static UITableViewCell *parentCell(UIView *view) {
    for (UIView *p = view; p; p = p.superview)
        if ([p isKindOfClass:UITableViewCell.class]) return (UITableViewCell *)p;
    return nil;
}
static UITableView *parentTable(UIView *view) {
    for (UIView *p = view.superview; p; p = p.superview)
        if ([p isKindOfClass:UITableView.class]) return (UITableView *)p;
    return nil;
}
static QARBadgeCellState *stateFor(UITableViewCell *cell) {
    if (!cell) return nil;
    QARBadgeCellState *state = objc_getAssociatedObject(cell, &stateKey);
    if (!state) {
        ensureActualCell(cell);
        state = [QARBadgeCellState new];
        objc_setAssociatedObject(cell, &stateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!visibleCells) visibleCells = [NSHashTable weakObjectsHashTable];
        [visibleCells addObject:cell];
    }
    return state;
}
static id findRecord(UIView *view, unsigned *visited) {
    if (++*visited > 256) return nil;
    if ([view isKindOfClass:NSClassFromString(@"QQNTAIOMessageAvatarView")]) {
        id record = QARBadgeRecord(view);
        if (record) return record;
    }
    for (UIView *child in view.subviews) { id record = findRecord(child, visited); if (record) return record; }
    return nil;
}
static CGFloat footerHeight(void) {
    UIFont *font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption2]
        scaledFontForFont:[UIFont systemFontOfSize:11 weight:UIFontWeightMedium]];
    return ceil(font.lineHeight) + 14;
}
static UIView *findBubble(UIView *view, NSUInteger *visited) {
    if (++*visited > 256 || view.hidden || view.alpha < 0.01) return nil;
    Class bubble = NSClassFromString(@"_TtC6AIOLib13AIOBubbleView");
    if (bubble && [view isKindOfClass:bubble]) return view;
    for (UIView *child in view.subviews) { UIView *found = findBubble(child, visited); if (found) return found; }
    return nil;
}
static BOOL usableBubble(QARBadgeCellState *state, CGFloat base) {
    CGRect box = state.bubbleFrame;
    return !CGRectIsEmpty(box) && isfinite(CGRectGetMaxY(box)) && box.origin.y >= 0 &&
        CGRectGetMaxY(box) <= base + 0.5;
}
static CGFloat pillHeight(QARBadgeCellState *state) {
    return state.flash ? MAX(38, footerHeight() - 8) : footerHeight() - 8;
}
static CGFloat pillTop(QARBadgeCellState *state, CGFloat base) {
    return usableBubble(state, base) ? CGRectGetMaxY(state.bubbleFrame) + 4 : base + 3;
}
static CGFloat extraForState(QARBadgeCellState *state, CGFloat base) {
    if (!state.marked && !state.flash) return 0;
    return MAX(0, ceil(pillTop(state, base) + pillHeight(state) + 4 - base));
}
static void refresh(UITableViewCell *cell);
static void removeRow(QARBadgeCellState *state, UITableViewCell *cell) {
    QARBadgeTableState *tableState = state.table ? objc_getAssociatedObject(state.table, &tableKey) : nil;
    if (state.path && [tableState.rows objectForKey:state.path] == cell) [tableState.rows removeObjectForKey:state.path];
    state.table = nil; state.path = nil;
}
static void clearCell(UITableViewCell *cell) {
    QARBadgeCellState *state = cell ? objc_getAssociatedObject(cell, &stateKey) : nil;
    removeRow(state, cell);
    [state.pill removeFromSuperview]; state.pill = nil; state.record = nil; state.owner = nil;
    state.marked = NO; state.flash = NO; state.reserved = 0; state.baseHeight = 0; state.attempts = 0; state.reportedUnavailable = NO;
    state.contentEpoch = 0; state.contentCheckedAt = 0;
}
static double delegateHeight(QARDelegateHook *entry, id receiver, UITableView *table, NSIndexPath *path) {
    BOOL nested = heightDepth > 0; heightDepth++;
    @try {
    double original = ((double (*)(id, SEL, id, id))entry.original)(receiver,
        @selector(tableView:heightForRowAtIndexPath:), table, path);
    if (nested || !NSThread.isMainThread || ![table isKindOfClass:UITableView.class] ||
        ![path isKindOfClass:NSIndexPath.class]) return original;
    entry.calls++; atomic_fetch_add(&heightCalls, 1);
    // This map is populated outside the height callback. Never query UITableView cells here.
    QARBadgeTableState *tableState = objc_getAssociatedObject(table, &tableKey);
    UITableViewCell *cell = [tableState.rows objectForKey:path];
    QARBadgeCellState *state = cell ? objc_getAssociatedObject(cell, &stateKey) : nil;
    if (!state || state.table != table || ![state.path isEqual:path]) return original;
    if (!isfinite(original) || original <= 0) {
        state.reserved = 0; atomic_fetch_add(&autoHeights, 1); return original;
    }
    BOOL sameOwner = state.record && [state.owner isEqual:QARCurrentOwner()];
    BOOL marked = sameOwner && state.marked && QAREnabled();
    BOOL flash = sameOwner && state.flash && QARFlashEnabled();
    CGFloat extra = (flash || marked) ? extraForState(state, original) : 0;
    state.baseHeight = original; state.reserved = extra;
    if (extra) atomic_fetch_add(&reservedRows, 1);
    return original + extra;
    } @finally { heightDepth--; }
}
static BOOL delegateFromQQ(Class cls) {
    NSString *bundle = [NSBundle.mainBundle.bundlePath stringByResolvingSymlinksInPath];
    if (!bundle.length) return NO;
    // KVO/runtime subclasses may have no image. Walk their superclass chain,
    // and normalize /var versus /private/var before checking the app boundary.
    for (Class candidate = cls; candidate && candidate != NSObject.class; candidate = class_getSuperclass(candidate)) {
        const char *path = class_getImageName(candidate);
        if (!path) continue;
        NSString *imagePath = [[NSString stringWithUTF8String:path] stringByResolvingSymlinksInPath];
        if ([imagePath hasPrefix:[bundle stringByAppendingString:@"/"]]) return YES;
    }
    return NO;
}

static void ensureActualCell(UITableViewCell *cell) {
    if (!versionReady || !NSThread.isMainThread) return;
    Class cls = object_getClass(cell);
    if (!delegateFromQQ(cls) || [NSStringFromClass(cls) isEqual:@"_TtC6AIOLib7AIOCell"]) return;
    if (!actualCellHooks) actualCellHooks = [NSMutableArray new];
    for (NSString *name in @[@"layoutSubviews", @"prepareForReuse"]) {
        SEL selector = NSSelectorFromString(name); BOOL exists = NO;
        for (QARCellHook *entry in actualCellHooks) if (entry.target == cls && entry.selector == selector) { exists = YES; break; }
        if (exists || actualCellHooks.count >= 32) continue;
        QARCellHook *entry = [QARCellHook new]; entry.target = cls; entry.selector = selector;
        BOOL reuse = [name isEqual:@"prepareForReuse"];
        entry.replacement = imp_implementationWithBlock(^(UITableViewCell *receiver) {
            entry.calls++;
            if (reuse) clearCell(receiver);
            ((void (*)(id,SEL))entry.original)(receiver, selector);
            if (!reuse) refresh(receiver);
        });
        IMP original = NULL;
        entry.result = QARInstallHook(cls, selector, "v16@0:8", entry.replacement, &original);
        entry.original = original;
        [actualCellHooks addObject:entry];
        if (!original) imp_removeBlock(entry.replacement);
    }
}
static BOOL ensureDelegate(UITableView *table) {
    if (!versionReady || !table.delegate) return NO;
    Class cls = object_getClass(table.delegate);
    SEL selector = @selector(tableView:heightForRowAtIndexPath:);
    for (QARDelegateHook *entry in delegateHooks)
        if (entry.target == cls) return entry.original && class_getMethodImplementation(cls, selector) == entry.replacement;
    if (!delegateFromQQ(cls)) { atomic_fetch_add(&rejectedOrigin, 1); return NO; }
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) { atomic_fetch_add(&missingHeightMethod, 1); return NO; }
    if (!QARSignaturesMatch(method_getTypeEncoding(method), "d32@0:8@16@24")) {
        atomic_fetch_add(&delegateABIRejects, 1); return NO;
    }
    if (!delegateHooks) delegateHooks = [NSMutableArray new];
    if (delegateHooks.count >= 16) return NO;
    QARDelegateHook *entry = [QARDelegateHook new]; entry.target = cls;
    // Each class has its own trampoline and original IMP; superclass dispatch cannot
    // select the wrong original or add the footer twice.
    entry.replacement = imp_implementationWithBlock(^double(id receiver, UITableView *sender, NSIndexPath *path) {
        return delegateHeight(entry, receiver, sender, path);
    });
    IMP original = NULL;
    entry.result = QARInstallHook(cls, selector, "d32@0:8@16@24", entry.replacement, &original);
    entry.original = original;
    [delegateHooks addObject:entry];
    return entry.result == QARHookInstalled;
}
static CGFloat bottomOffset(UITableView *table) {
    return MAX(-table.adjustedContentInset.top,
        table.contentSize.height + table.adjustedContentInset.bottom - table.bounds.size.height);
}
static BOOL userScrolling(UITableView *table) {
    return table.isTracking || table.isDragging || table.isDecelerating;
}
static BOOL nearBottom(UITableView *table) {
    return fabs(bottomOffset(table) - table.contentOffset.y) <= 24;
}
static void performHeightUpdate(UITableView *table, NSUInteger deferrals) {
    QARBadgeTableState *current = table ? objc_getAssociatedObject(table, &tableKey) : nil;
    if (!current) return;
    if (!table.window) { current.pending = NO; return; }
    if (table.hasUncommittedUpdates) {
        atomic_fetch_add(&deferredHeightUpdates, 1);
        if (deferrals >= 20) { current.pending = NO; return; }
        __weak UITableView *weakTable = table;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 20), dispatch_get_main_queue(), ^{
            performHeightUpdate(weakTable, deferrals + 1);
        });
        return;
    }
    BOOL followBottom = !userScrolling(table) && (nearBottom(table) ||
        (current.requestedAtBottom && fabs(table.contentOffset.y - current.requestedOffsetY) <= 2));
    // Only completed attempts consume the row budget; repeated layout calls while
    // an update is queued or QQ is applying its own batch must not consume it.
    for (UITableViewCell *cell in table.visibleCells) {
        QARBadgeCellState *state = objc_getAssociatedObject(cell, &stateKey);
        if (!state) continue;
        CGFloat needed = extraForState(state, state.baseHeight);
        if (fabs(state.reserved - needed) > 0.5 ||
            (needed > 0 && cell.bounds.size.height < state.baseHeight + needed - 1)) state.attempts++;
    }
    @try {
        [UIView performWithoutAnimation:^{
            [table beginUpdates]; [table endUpdates];
            [table layoutIfNeeded];
            if (followBottom && !userScrolling(table))
                [table setContentOffset:CGPointMake(table.contentOffset.x, bottomOffset(table)) animated:NO];
        }];
        atomic_fetch_add(&heightChanges, 1);
    } @finally { current.pending = NO; }
    for (UITableViewCell *cell in table.visibleCells) refresh(cell);
    if (followBottom) {
        __weak UITableView *weakTable = table;
        dispatch_async(dispatch_get_main_queue(), ^{
            UITableView *currentTable = weakTable;
            if (!currentTable.window || userScrolling(currentTable)) return;
            [currentTable layoutIfNeeded];
            [currentTable setContentOffset:CGPointMake(currentTable.contentOffset.x, bottomOffset(currentTable)) animated:NO];
        });
    }
}
static void requestHeight(UITableView *table) {
    QARBadgeTableState *tableState = table ? objc_getAssociatedObject(table, &tableKey) : nil;
    if (!tableState || tableState.pending || !ensureDelegate(table)) return;
    tableState.requestedAtBottom = !userScrolling(table) && nearBottom(table);
    tableState.requestedOffsetY = table.contentOffset.y;
    tableState.pending = YES;
    __weak UITableView *weakTable = table;
    dispatch_async(dispatch_get_main_queue(), ^{ performHeightUpdate(weakTable, 0); });
}
static void refresh(UITableViewCell *cell) {
    if (!cell || !NSThread.isMainThread || heightDepth) return;
    QARBadgeCellState *state = stateFor(cell);
    unsigned visited = 0; id record = findRecord(cell.contentView, &visited);
    NSString *owner = QARCurrentOwner();
    if ((state.owner && ![state.owner isEqual:owner]) || state.record != record) {
        clearCell(cell); state = stateFor(cell);
    }
    state.record = record; state.owner = owner;
    NSUInteger bubbleVisited = 0;
    UIView *bubble = findBubble(cell.contentView, &bubbleVisited);
    state.bubbleFrame = bubble ? [bubble convertRect:bubble.bounds toView:cell.contentView] : CGRectZero;
    // Cache both positive and negative lookups. Layout can run many times per frame;
    // flash lookup otherwise synchronously visits the storage queue and filesystem.
    // Store/switch notifications invalidate immediately; the short expiry also covers
    // QQ mutating a record in place without rebinding it.
    CFTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    BOOL marked = state.marked, flash = state.flash;
    if (state.contentEpoch != contentEpoch || now - state.contentCheckedAt >= 0.5) {
        marked = record && QARIsMarkedRecord(record);
        flash = record && QARFlashURLForRecord(record) != nil;
        state.contentEpoch = contentEpoch; state.contentCheckedAt = now;
        atomic_fetch_add(&contentChecks, 1);
    } else atomic_fetch_add(&contentCacheHits, 1);
    if (state.marked != marked || state.flash != flash) { state.attempts = 0; state.reportedUnavailable = NO; }
    state.marked = marked; state.flash = flash;
    if (record) atomic_fetch_add(&recordsFound, 1);
    UITableView *table = parentTable(cell);
    if (record && !table) atomic_fetch_add(&noTable, 1);
    if (record && table && !table.window) atomic_fetch_add(&detachedTable, 1);
    if (table && table.window && record) {
        NSIndexPath *path = [table indexPathForCell:cell]; // Deliberately outside delegateHeight.
        if (path) {
            if (state.table != table || ![state.path isEqual:path]) { removeRow(state, cell); state.attempts = 0; state.reportedUnavailable = NO; }
            QARBadgeTableState *tableState = objc_getAssociatedObject(table, &tableKey);
            if (!tableState) {
                tableState = [QARBadgeTableState new];
                objc_setAssociatedObject(table, &tableKey, tableState, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            state.table = table; state.path = path; [tableState.rows setObject:cell forKey:path];
            ensureDelegate(table);
        } else atomic_fetch_add(&missingPath, 1);
    }
    if (!state.marked && !state.flash) {
        state.pill.hidden = YES;
        if (state.reserved > 0 && table.window && state.attempts < 3) requestHeight(table);
        return;
    }
    CGFloat extra = extraForState(state, state.baseHeight);
    if (fabs(state.reserved - extra) > 0.5 || cell.bounds.size.height < state.baseHeight + extra - 1) {
        state.pill.hidden = YES;
        if (table.window && state.path && state.attempts < 3) requestHeight(table);
        else if (table.window && state.attempts >= 3 && !state.reportedUnavailable) { state.reportedUnavailable = YES; atomic_fetch_add(&unresolved, 1); }
        return;
    }
    state.attempts = 0; state.reportedUnavailable = NO;
    if (!state.pill) {
        state.pill = [[QARRecallPill alloc] initWithFrame:CGRectZero];
        [cell.contentView addSubview:state.pill]; atomic_fetch_add(&displayed, 1);
    }
    state.pill.replayRecord = state.flash ? record : nil;
    state.pill.replayOwner = state.flash ? owner : nil;
    state.pill.userInteractionEnabled = state.flash;
    state.pill.label.text = state.flash ? (state.marked ? @"已撤回 · 已保留 · 查看闪照" : @"闪照 · 再次查看") : @"已撤回 · 已保留";
    state.pill.accessibilityLabel = state.pill.label.text;
    state.pill.accessibilityTraits = state.flash ? UIAccessibilityTraitButton : UIAccessibilityTraitStaticText;
    NSString *iconName = state.flash ? @"photo.circle.fill" : @"arrow.uturn.backward.circle.fill";
    if (![state.pill.icon.accessibilityIdentifier isEqual:iconName]) {
        state.pill.icon.image = [UIImage systemImageNamed:iconName];
        state.pill.icon.accessibilityIdentifier = iconName;
    }
    CGFloat width = cell.contentView.bounds.size.width;
    CGSize size = [state.pill sizeThatFits:CGSizeMake(MAX(0, width - 32), CGFLOAT_MAX)];
    size.width = MIN(size.width, MAX(0, width - 32));
    if (state.flash) size.height = MAX(38, size.height);
    CGFloat desiredX = usableBubble(state, state.baseHeight) ? CGRectGetMinX(state.bubbleFrame) : 56;
    CGFloat x = MIN(desiredX, MAX(16, width - size.width - 16));
    state.pill.frame = CGRectMake(x, pillTop(state, state.baseHeight), size.width, size.height);
    state.pill.hidden = NO;
    if (cell.contentView.subviews.lastObject != state.pill) [cell.contentView bringSubviewToFront:state.pill];
}
static void attachmentRefresh(id object) {
    if (!NSThread.isMainThread || ![object isKindOfClass:UIView.class]) return;
    __weak UIView *view = object;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *strongView = view;
        if (strongView.window) refresh(parentCell(strongView));
    });
}
static void avatarWindow(id self, SEL cmd) {
    atomic_fetch_add(&staticCalls[6], 1);
    ((void (*)(id, SEL))hooks[6].original)(self, cmd);
    attachmentRefresh(self);
}
static void avatarSuperview(id self, SEL cmd) {
    atomic_fetch_add(&staticCalls[7], 1);
    ((void (*)(id, SEL))hooks[7].original)(self, cmd);
    attachmentRefresh(self);
}
static void avatarLayout(id self, SEL cmd) {
    atomic_fetch_add(&staticCalls[0], 1);
    ((void (*)(id, SEL))hooks[0].original)(self, cmd);
    if (NSThread.isMainThread && [self isKindOfClass:UIView.class]) refresh(parentCell(self));
}
static void avatarRecord(id self, SEL cmd, id record) {
    atomic_fetch_add(&staticCalls[5], 1);
    ((void (*)(id, SEL, id))hooks[5].original)(self, cmd, record);
    if (NSThread.isMainThread && [self isKindOfClass:UIView.class]) {
        UITableViewCell *cell = parentCell(self);
        stateFor(cell).contentEpoch = 0;
        refresh(cell);
    }
}
static BOOL bindCell(id self, SEL cmd, id model) {
    atomic_fetch_add(&staticCalls[1], 1);
    UITableViewCell *cell = NSThread.isMainThread && [self isKindOfClass:UIView.class] ? parentCell(self) : nil;
    clearCell(cell);
    BOOL result = ((BOOL (*)(id, SEL, id))hooks[1].original)(self, cmd, model);
    // The avatar owns the verified record; no assumption about an opaque Swift view model
    // or the meaning of the bind method's Boolean return value is needed.
    refresh(cell); return result;
}
static void reuseCell(id self, SEL cmd) {
    atomic_fetch_add(&staticCalls[2], 1);
    if (NSThread.isMainThread && [self isKindOfClass:UIView.class]) clearCell(parentCell(self));
    ((void (*)(id, SEL))hooks[2].original)(self, cmd);
}
static void unbindCell(id self, SEL cmd) {
    atomic_fetch_add(&staticCalls[3], 1);
    if (NSThread.isMainThread && [self isKindOfClass:UIView.class]) clearCell(parentCell(self));
    ((void (*)(id, SEL))hooks[3].original)(self, cmd);
}
static void layoutCell(id self, SEL cmd) {
    atomic_fetch_add(&staticCalls[4], 1);
    ((void (*)(id, SEL))hooks[4].original)(self, cmd);
    if (NSThread.isMainThread && [self isKindOfClass:UIView.class]) refresh(parentCell(self));
}
void QARInstallBadge(NSDictionary *info) {
    if (!QARVersionSupported(info)) return;
    versionReady = YES;
    for (unsigned i = 0; i < 8; i++) {
        BadgeEntry *entry = &hooks[i]; if (entry->original) continue;
        entry->result = QARInstallHook(objc_getClass(entry->cls), sel_registerName(entry->selector),
            entry->types, entry->replacement, &entry->original);
    }
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        for (NSString *notification in @[QARStoreChangedNotification, UIApplicationDidBecomeActiveNotification,
                                         UIContentSizeCategoryDidChangeNotification]) {
            [NSNotificationCenter.defaultCenter addObserverForName:notification object:nil
                queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                    contentEpoch++;
                    for (UITableViewCell *cell in visibleCells.allObjects) {
                        if (!cell.window) continue;
                        stateFor(cell).attempts = 0; refresh(cell);
                    }
                    // refresh requests a height update only when geometry changed.
                    // Ordinary incoming-message notifications must not relayout the table.
                }];
        }
    });
}
NSDictionary *QARBadgeStatus(void) {
    NSMutableDictionary *results = [NSMutableDictionary new], *active = [NSMutableDictionary new], *calls = [NSMutableDictionary new];
    NSUInteger installed = 0;
    for (unsigned i = 0; i < 8; i++) {
        BadgeEntry *entry = &hooks[i];
        NSString *key = [NSString stringWithFormat:@"%s -%s", entry->cls, entry->selector];
        results[key] = @(entry->result); calls[key] = @(atomic_load(&staticCalls[i]));
        Method method = class_getInstanceMethod(objc_getClass(entry->cls), sel_registerName(entry->selector));
        active[key] = @(entry->original && method && method_getImplementation(method) == entry->replacement);
        if (entry->original) installed++;
    }
    for (QARCellHook *entry in actualCellHooks) {
        NSString *key = [NSString stringWithFormat:@"%@ -%@", NSStringFromClass(entry.target), NSStringFromSelector(entry.selector)];
        results[key] = @(entry.result); calls[key] = @(entry.calls);
        active[key] = @(entry.original && class_getMethodImplementation(entry.target, entry.selector) == entry.replacement);
        if (entry.original) installed++;
    }
    for (QARDelegateHook *entry in delegateHooks) {
        NSString *key = [NSStringFromClass(entry.target) stringByAppendingString:@" -tableView:heightForRowAtIndexPath:"];
        results[key] = @(entry.result); calls[key] = @(entry.calls);
        active[key] = @(entry.original && class_getMethodImplementation(entry.target,
            @selector(tableView:heightForRowAtIndexPath:)) == entry.replacement);
        if (entry.original) installed++;
    }
    return @{@"installed_hooks": @(installed), @"hook_results": results, @"hook_still_active": active, @"hook_calls": calls,
        @"content_state_checks": @(atomic_load(&contentChecks)), @"content_cache_hits": @(atomic_load(&contentCacheHits)),
        @"badges_created": @(atomic_load(&displayed)), @"height_refreshes": @(atomic_load(&heightChanges)), @"deferred_height_updates": @(atomic_load(&deferredHeightUpdates)),
        @"delegate_height_calls": @(atomic_load(&heightCalls)), @"rows_with_footer_reserved": @(atomic_load(&reservedRows)),
        @"records_found": @(atomic_load(&recordsFound)), @"table_not_attached": @(atomic_load(&noTable)),
        @"table_without_window": @(atomic_load(&detachedTable)), @"row_path_unavailable": @(atomic_load(&missingPath)),
        @"delegate_origin_rejected": @(atomic_load(&rejectedOrigin)), @"delegate_method_missing": @(atomic_load(&missingHeightMethod)), @"delegate_abi_rejected": @(atomic_load(&delegateABIRejects)),
        @"automatic_height_rows": @(atomic_load(&autoHeights)), @"footer_space_unavailable": @(atomic_load(&unresolved)),
        @"text": @"已撤回 · 已保留"};
}
void QARResetBadgeCounters(void) {
    atomic_store(&contentChecks, 0); atomic_store(&contentCacheHits, 0);
    atomic_store(&deferredHeightUpdates, 0);
    atomic_store(&rejectedOrigin, 0); atomic_store(&noTable, 0); atomic_store(&detachedTable, 0);
    atomic_store(&displayed, 0); atomic_store(&unresolved, 0); atomic_store(&heightChanges, 0);
    atomic_store(&heightCalls, 0); atomic_store(&reservedRows, 0); atomic_store(&recordsFound, 0);
    atomic_store(&missingPath, 0); atomic_store(&missingHeightMethod, 0); atomic_store(&delegateABIRejects, 0);
    atomic_store(&autoHeights, 0);
    for (unsigned i = 0; i < 8; i++) atomic_store(&staticCalls[i], 0);
    for (QARDelegateHook *entry in delegateHooks) entry.calls = 0;
}
#ifdef QAR_TESTING
BOOL QARBadgeHeightCallbackForTest(void) { return heightDepth > 0; }
void QARBadgeRefreshCellForTest(UITableViewCell *cell) { refresh(cell); }
UIView *QARBadgeViewForTest(UITableViewCell *cell) { return stateFor(cell).pill; }
#endif
