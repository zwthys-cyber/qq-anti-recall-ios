#import <Foundation/Foundation.h>
void QARTraceEvent(NSString *event);
void QARResetTrace(void);
NSArray<NSDictionary *> *QARTraceSnapshot(void);
