#define QAR_HAS_UI_RECALL 1
#define QAR_UI_RECALL_CLASS "_TtC9NTAIOChat20NTAIOFloatEarManager"
#import <Foundation/Foundation.h>
BOOL QARVersionSupported(NSDictionary *info);
void QARInstallAdapters(NSDictionary *info);
BOOL QAREnabled(void);
void QARSetEnabled(BOOL enabled);
NSDictionary *QARStatus(void);
