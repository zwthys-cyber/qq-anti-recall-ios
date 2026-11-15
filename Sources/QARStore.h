#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSString * const QARStoreChangedNotification;
NSString *QARCurrentOwner(void);
void QARRememberMessages(id messages);
void QARMarkRecalledUpdates(id messages);
id QARRestoreHistory(id messages);
BOOL QARIsMarkedRecord(id record);
void QARForgetMessageIDs(id ids);
void QARClearSavedMessages(void);
NSDictionary *QARStoreStatus(void);
void QARResetStoreCounters(void);
#ifdef QAR_TESTING
void QARStoreUseTestDirectory(NSURL *directory);
void QARStoreDropMemoryForTest(void);
#endif
