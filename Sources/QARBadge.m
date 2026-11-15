#import "QARBadge.h"
#import "QARBadgeRecord.h"
#import "QARAdapter.h"
#import "QARHook.h"
#import "QARStore.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <math.h>
#include <stdatomic.h>

@interface QARRecallPill : UIView
@property(nonatomic,strong) UILabel *label;
@property(nonatomic,strong) UIImageView *icon;
@end
@implementation QARRecallPill
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = @"消息已撤回，原内容已保留";
    self.accessibilityTraits = UIAccessibilityTraitStaticText;
    self.label = [UILabel new];
    self.label.text = @"已撤回 · 已保留";
    self.label.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption2]
        scaledFontForFont:[UIFont systemFontOfSize:11 weight:UIFontWeightMedium]];
    self.label.adjustsFontForContentSizeCategory = YES;
    self.label.textColor = UIColor.systemTealColor;
    self.icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.uturn.backward.circle.fill"]];
    self.icon.tintColor = UIColor.systemTealColor;
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
- (CGSize)sizeThatFits:(CGSize)size {
    CGSize label = [self.label sizeThatFits:size];
    return CGSizeMake(ceil(label.width) + 34, ceil(label.height) + 6);
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = self.bounds.size.height;
    self.icon.frame = CGRectMake(8, (h - 12) / 2, 12, 12);
    self.label.frame = CGRectMake(25, 3, MAX(0, self.bounds.size.width - 32), h - 6);
}
@end

@interface QARBadgeCellState : NSObject
@property(nonatomic,strong) QARRecallPill *pill;
@property(nonatomic,weak) id model;
@property(nonatomic,copy) NSString *owner;
@property(nonatomic) CGFloat reserved;
@property(nonatomic) CGFloat baseHeight;
@property(nonatomic) NSUInteger heightAttempts;
@end
@implementation QARBadgeCellState @end

static char stateKey, pendingKey;
static NSHashTable<UITableViewCell *> *visibleCells;
static atomic_uint_fast64_t displayed, unresolved, heightChanges;
static void avatarLayout(id self, SEL cmd);
static void avatarRecord(id self, SEL cmd, id record);
static BOOL bindCell(id self, SEL cmd, id model);
static void reuseCell(id self, SEL cmd);
static void unbindCell(id self, SEL cmd);
static void layoutCell(id self, SEL cmd);
static double rowHeight(id self, SEL cmd, id table, id path);
typedef struct { const char *cls, *selector, *types; IMP replacement, original; QARHookResult result; } BadgeEntry;
static BadgeEntry hooks[] = {
    {"QQNTAIOMessageAvatarView", "layoutSubviews", "v16@0:8", (IMP)avatarLayout, NULL, QARHookMissingClass},
    {"_TtC6AIOLib7AIOCell", "bindViewModel:", "B24@0:8@16", (IMP)bindCell, NULL, QARHookMissingClass},
    {"_TtC6AIOLib7AIOCell", "prepareForReuse", "v16@0:8", (IMP)reuseCell, NULL, QARHookMissingClass},
    {"_TtC6AIOLib7AIOCell", "unbindViewModel", "v16@0:8", (IMP)unbindCell, NULL, QARHookMissingClass},
    {"_TtC6AIOLib7AIOCell", "layoutSubviews", "v16@0:8", (IMP)layoutCell, NULL, QARHookMissingClass},
    {"AIOBaseCellViewModel", "tableView:heightForRowAtIndexPath:", "d32@0:8@16@24", (IMP)rowHeight, NULL, QARHookMissingClass},
    {"QQNTAIOMessageAvatarView", "setRecord:", "v24@0:8@16", (IMP)avatarRecord, NULL, QARHookMissingClass}
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
        state = [QARBadgeCellState new];
        objc_setAssociatedObject(cell, &stateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!visibleCells) visibleCells = [NSHashTable weakObjectsHashTable];
        [visibleCells addObject:cell];
    }
    return state;
}
static id findRecord(UIView *view, unsigned *visited) {
    if (++*visited > 256) return nil;
    // This verified avatar getter exposes the record without reading Swift storage.
    if ([view isKindOfClass:NSClassFromString(@"QQNTAIOMessageAvatarView")]) {
        id record = QARBadgeRecord(view);
        if (record) return record;
    }
    for (UIView *child in view.subviews) {
        id record = findRecord(child, visited);
        if (record) return record;
    }
    return nil;
}
static id cellRecord(UITableViewCell *cell, id model) {
    unsigned visited = 0;
    id record = cell ? findRecord(cell.contentView, &visited) : nil;
    return record ?: QARBadgeRecord(model);
}
static CGFloat footerHeight(void) {
    UIFont *font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption2]
        scaledFontForFont:[UIFont systemFontOfSize:11 weight:UIFontWeightMedium]];
    return ceil(font.lineHeight) + 14; // Six inside the pill, eight between rows.
}
static void refresh(UITableViewCell *cell);
static void requestHeight(UITableView *table) {
    if (!table || [objc_getAssociatedObject(table, &pendingKey) boolValue]) return;
    objc_setAssociatedObject(table, &pendingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UITableView *weakTable = table;
    dispatch_async(dispatch_get_main_queue(), ^{
        UITableView *strongTable = weakTable;
        if (!strongTable) return;
        objc_setAssociatedObject(strongTable, &pendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!strongTable.window || strongTable.hasUncommittedUpdates) return;
        // Recalculate heights without reloading QQ's already-preserved message models.
        [UIView performWithoutAnimation:^{
            [strongTable beginUpdates];
            [strongTable endUpdates];
        }];
        atomic_fetch_add(&heightChanges, 1);
        for (UITableViewCell *cell in strongTable.visibleCells) refresh(cell);
    });
}
static void clearCell(UITableViewCell *cell) {
    QARBadgeCellState *state = objc_getAssociatedObject(cell, &stateKey);
    [state.pill removeFromSuperview];
    state.pill = nil;
    state.model = nil;
    state.owner = nil;
    state.reserved = 0;
    state.baseHeight = 0;
    state.heightAttempts = 0;
}
static void refresh(UITableViewCell *cell) {
    if (!cell || !NSThread.isMainThread) return;
    QARBadgeCellState *state = stateFor(cell);
    NSString *owner = QARCurrentOwner();
    if (state.owner && ![state.owner isEqual:owner]) {
        clearCell(cell);
        state = stateFor(cell);
    }
    id record = cellRecord(cell, state.model);
    BOOL marked = record && QARIsMarkedRecord(record);
    UITableView *table = parentTable(cell);
    if (!marked) {
        state.pill.hidden = YES;
        if (state.reserved > 0 && state.heightAttempts++ < 2) requestHeight(table);
        return;
    }
    state.owner = owner;
    CGFloat extra = footerHeight();
    // Do not place a label over message text before the row has gained footer space.
    if (state.reserved < extra - 0.5 || cell.bounds.size.height < state.baseHeight + extra - 1) {
        state.pill.hidden = YES;
        if (hooks[5].original && state.heightAttempts++ < 2) requestHeight(table);
        else atomic_fetch_add(&unresolved, 1);
        return;
    }
    if (!state.pill) {
        state.pill = [[QARRecallPill alloc] initWithFrame:CGRectZero];
        [cell.contentView addSubview:state.pill];
        atomic_fetch_add(&displayed, 1);
    }
    CGFloat width = cell.contentView.bounds.size.width;
    CGSize size = [state.pill sizeThatFits:CGSizeMake(MAX(0, width - 32), CGFLOAT_MAX)];
    size.width = MIN(size.width, MAX(0, width - 32));
    // Received messages start next to the avatar. This footer stays inside its own row.
    CGFloat x = MIN(56, MAX(16, width - size.width - 16));
    state.pill.frame = CGRectMake(x, cell.contentView.bounds.size.height - extra + 3, size.width, size.height);
    state.pill.hidden = NO;
    [cell.contentView bringSubviewToFront:state.pill];
}
static void avatarLayout(id self, SEL cmd) {
    ((void (*)(id, SEL))hooks[0].original)(self, cmd);
    if ([self isKindOfClass:UIView.class]) refresh(parentCell(self));
}
static void avatarRecord(id self, SEL cmd, id record) {
    ((void (*)(id, SEL, id))hooks[6].original)(self, cmd, record);
    if ([self isKindOfClass:UIView.class]) refresh(parentCell(self));
}
static BOOL bindCell(id self, SEL cmd, id model) {
    UITableViewCell *cell = [self isKindOfClass:UITableViewCell.class] ? self : parentCell(self);
    clearCell(cell);
    BOOL result = ((BOOL (*)(id, SEL, id))hooks[1].original)(self, cmd, model);
    if (result && cell) {
        stateFor(cell).model = model;
        refresh(cell);
    }
    return result;
}
static void reuseCell(id self, SEL cmd) {
    if ([self isKindOfClass:UIView.class]) clearCell(parentCell(self));
    ((void (*)(id, SEL))hooks[2].original)(self, cmd);
}
static void unbindCell(id self, SEL cmd) {
    if ([self isKindOfClass:UIView.class]) clearCell(parentCell(self));
    ((void (*)(id, SEL))hooks[3].original)(self, cmd);
}
static void layoutCell(id self, SEL cmd) {
    ((void (*)(id, SEL))hooks[4].original)(self, cmd);
    if ([self isKindOfClass:UIView.class]) refresh(parentCell(self));
}
static double rowHeight(id self, SEL cmd, id table, id path) {
    double original = ((double (*)(id, SEL, id, id))hooks[5].original)(self, cmd, table, path);
    if (!NSThread.isMainThread || ![table isKindOfClass:UITableView.class] ||
        ![path isKindOfClass:NSIndexPath.class] || !isfinite(original) || original <= 0) return original;
    UITableViewCell *cell = [(UITableView *)table cellForRowAtIndexPath:path];
    id record = cellRecord(cell, self);
    BOOL marked = record && QARIsMarkedRecord(record);
    CGFloat extra = marked ? footerHeight() : 0;
    QARBadgeCellState *state = cell ? stateFor(cell) : nil;
    state.model = self;
    state.owner = QARCurrentOwner();
    state.baseHeight = original;
    state.reserved = extra;
    return original + extra;
}
void QARInstallBadge(NSDictionary *info) {
    if (!QARVersionSupported(info)) return;
    for (unsigned i = 0; i < sizeof(hooks) / sizeof(hooks[0]); i++) {
        BadgeEntry *entry = &hooks[i];
        if (entry->original) continue;
        entry->result = QARInstallHook(objc_getClass(entry->cls), sel_registerName(entry->selector),
            entry->types, entry->replacement, &entry->original);
    }
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        for (NSString *notification in @[QARStoreChangedNotification, UIApplicationDidBecomeActiveNotification,
                                         UIContentSizeCategoryDidChangeNotification]) {
            [NSNotificationCenter.defaultCenter addObserverForName:notification object:nil
                queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                    NSMutableSet *tables = [NSMutableSet new];
                    for (UITableViewCell *cell in visibleCells.allObjects) {
                        stateFor(cell).heightAttempts = 0;
                        refresh(cell);
                        UITableView *table = parentTable(cell);
                        if (table) [tables addObject:table];
                    }
                    for (UITableView *table in tables) requestHeight(table);
                }];
        }
    });
}
NSDictionary *QARBadgeStatus(void) {
    NSMutableDictionary *results = [NSMutableDictionary new], *active = [NSMutableDictionary new];
    NSUInteger installed = 0;
    for (unsigned i = 0; i < sizeof(hooks) / sizeof(hooks[0]); i++) {
        BadgeEntry *entry = &hooks[i];
        NSString *key = [NSString stringWithFormat:@"%s -%s", entry->cls, entry->selector];
        results[key] = @(entry->result);
        Method method = class_getInstanceMethod(objc_getClass(entry->cls), sel_registerName(entry->selector));
        active[key] = @(entry->original && method && method_getImplementation(method) == entry->replacement);
        if (entry->original) installed++;
    }
    return @{@"installed_hooks": @(installed), @"hook_results": results, @"hook_still_active": active,
             @"badges_created": @(atomic_load(&displayed)), @"height_refreshes": @(atomic_load(&heightChanges)),
             @"missing_height_hook": @(atomic_load(&unresolved)), @"text": @"已撤回 · 已保留"};
}
void QARResetBadgeCounters(void) {
    atomic_store(&displayed, 0); atomic_store(&unresolved, 0); atomic_store(&heightChanges, 0);
}
#ifdef QAR_TESTING
void QARBadgeRefreshCellForTest(UITableViewCell *cell) { refresh(cell); }
UIView *QARBadgeViewForTest(UITableViewCell *cell) { return stateFor(cell).pill; }
#endif
