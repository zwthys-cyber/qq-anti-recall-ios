#import <UIKit/UIKit.h>
void QARInstallFlash(NSDictionary *info);
NSDictionary *QARFlashStatus(void);
NSArray<NSURL *> *QARFlashFiles(void);
void QARClearFlash(void);
BOOL QARFlashEnabled(void);
void QARSetFlashEnabled(BOOL enabled);
NSURL *QARFlashURLForRecord(id record);
void QARPresentFlashRecord(UIViewController *presenter, id record);
#ifdef QAR_TESTING
void QARFlashUseTestDirectory(NSURL *directory);
#endif
