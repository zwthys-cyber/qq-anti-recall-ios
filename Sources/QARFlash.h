#import <UIKit/UIKit.h>
void QARInstallFlash(NSDictionary *info);
NSDictionary *QARFlashStatus(void);
NSArray<NSURL *> *QARFlashFiles(void);
void QARClearFlash(void);
void QARPresentFlash(UIViewController *presenter);
#ifdef QAR_TESTING
void QARFlashUseTestDirectory(NSURL *directory);
#endif
