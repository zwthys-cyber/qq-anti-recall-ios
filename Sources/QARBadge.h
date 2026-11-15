#import <Foundation/Foundation.h>
void QARInstallBadge(NSDictionary *info);
NSDictionary *QARBadgeStatus(void);
void QARResetBadgeCounters(void);
#ifdef QAR_TESTING
#import <UIKit/UIKit.h>
void QARBadgeRefreshCellForTest(UITableViewCell *cell);
UIView *QARBadgeViewForTest(UITableViewCell *cell);
#endif
