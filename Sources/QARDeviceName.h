#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
void QARPrepareDeviceNamePage(WKWebView *view);
void QARApplyDeviceNamePage(WKWebView *view);
void QARPresentDeviceNameEditor(UIViewController *presenter);
NSDictionary *QARDeviceNameStatus(void);
NSString *QARDeviceNameScript(NSDictionary *config);
