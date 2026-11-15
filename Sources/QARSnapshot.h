#import <Foundation/Foundation.h>
NSDictionary *QARModelSchemas(void);
id QARModelRead(id object, NSString *field, BOOL *valid);
BOOL QARModelWrite(id object, NSString *field, id value);
id QARModelCreate(NSString *className);
NSData *QAREncodeRecord(id record);
id QARDecodeRecord(NSData *data);
