#import "ICloudStoragePlugin.h"
#if __has_include(<icloud_storage/icloud_storage-Swift.h>)
#import <icloud_storage/icloud_storage-Swift.h>
#else
#import "icloud_storage-Swift.h"
#endif

@implementation ICloudStoragePlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftICloudStoragePlugin registerWithRegistrar:registrar];
}
@end

