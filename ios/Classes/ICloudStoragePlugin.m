#import "ICloudStoragePlugin.h"
#if __has_include(<icloud_storage_plus/icloud_storage_plus-Swift.h>)
#import <icloud_storage_plus/icloud_storage_plus-Swift.h>
#else
#import "icloud_storage_plus-Swift.h"
#endif

@implementation ICloudStoragePlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftICloudStoragePlugin registerWithRegistrar:registrar];
}
@end

