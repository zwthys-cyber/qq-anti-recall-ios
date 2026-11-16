#import <Foundation/Foundation.h>
void QARInstallDeviceDiagnostics(NSDictionary *info);
NSDictionary *QARDeviceDiagnosticsStatus(void);
NSArray<NSString *> *QARDevicePublicAssets(id values);

NSString *QARDeviceDiagnosticScript(void);
void QARDeviceRecordObservation(id value);
