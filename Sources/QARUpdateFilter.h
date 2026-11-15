#import <Foundation/Foundation.h>
// Returns the original payload unless verified recalled records were removed.
// shouldForward is NO only for a nonempty array consisting entirely of recalls.
id QARFilterMessageUpdates(id payload, BOOL *shouldForward);
NSDictionary *QARUpdateFilterStatus(void);
void QARResetUpdateFilter(void);
