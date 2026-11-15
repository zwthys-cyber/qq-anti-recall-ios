#import <Foundation/Foundation.h>
void QARFixtureModels(void);
void QARFixtureAccount(unsigned long long value);
id QARFixtureMessage(long long msgID, long long seq, NSString *peer, long long recall, NSString *body);
NSString *QARFixtureBody(id record);
NSDictionary *QARFixtureInfo(void);
