#import <Foundation/Foundation.h>

void QARInstallCallRecording(NSDictionary *info);
BOOL QARCallRecordingSuppressionEnabled(void);
void QARSetCallRecordingSuppressionEnabled(BOOL enabled);
NSDictionary *QARCallRecordingStatus(void);
void QARResetCallRecordingCounters(void);
