# icloud_storage

[![Pub](https://img.shields.io/pub/v/icloud_storage.svg)](https://pub.dev/packages/icloud_storage)
[![Donate](https://img.shields.io/badge/Donate-PayPal-green.svg)](https://www.paypal.com/donate?hosted_button_id=BH6WBSGWN594U)

A flutter plugin for upload, download and manage files in the app's iCloud container. Includes un-merged PRs and improvements from forks in the community. 

## Introduction

Documents and other data that is user-generated and stored in the <Application_Home>/Documents directory can be automatically backed up by iCloud on iOS devices, if the iCloud Backup setting is turned on. The data can be recovered when user sets up a new device or resets an existing device. If you need to do backup and download outside the forementioned scenarios, this plugin could help.

## Prerequisite

The following setups are needed in order to use this plugin:

1. An apple developer account
2. Created an App ID and iCloud Container ID
3. Enabled iCloud capability and assigned iCloud Container ID for the App ID
4. Enabled iCloud capability in Xcode

Refer to the [How to set up iCloud Container and enable the capability](#how-to-set-up-icloud-container-and-enable-the-capability) section for more detailed instructions.

## API Usage

### Gather files from iCloud

```dart
final fileList = await ICloudStorage.gather(
  containerId: 'iCloudContainerId',
  onUpdate: (stream) {
    filesUpdateSub = stream.listen((updatedFileList) {
      print('FILES UPDATED');
      updatedFileList.forEach((file) => print('-- ${file.relativePath}'));
    });
  },
);
print('FILES GATHERED');
fileList.forEach((file) => print('-- ${file.relativePath}'));
```

### Upload a file to iCloud

```dart
await ICloudStorage.upload(
  containerId: 'iCloudContainerId',
  filePath: '/localDir/localFile',
  destinationRelativePath: 'destDir/destFile',
  onProgress: (stream) {
    uploadProgressSub = stream.listen(
      (progress) => print('Upload File Progress: $progress'),
      onDone: () => print('Upload File Done'),
      onError: (err) => print('Upload File Error: $err'),
      cancelOnError: true,
    );
  },
);
```

Note: The 'startUpload' API is to start the upload process. The returned future completes without waiting for the upload to complete. Use 'onProgress' to track the upload progress. If the 'destinationRelativePath' contains a subdirectory that doesn't exist, it will be created.

### Download a file from iCloud

```dart
await ICloudStorage.download(
  containerId: 'iCloudContainerId',
  relativePath: 'relativePath',
  destinationFilePath: '/localDir/localFile',
  onProgress: (stream) {
    downloadProgressSub = stream.listen(
      (progress) => print('Download File Progress: $progress'),
      onDone: () => print('Download File Done'),
      onError: (err) => print('Download File Error: $err'),
      cancelOnError: true,
    );
  },
);
```

Note: The 'startDownload' API is to start the download process. The returned future completes without waiting for the download to complete. Use 'onProgress' to track the download progress.

### Delete a file from iCloud

```dart
await ICloudStorage.delete(
  containerId: 'iCloudContainerId',
  relativePath: 'relativePath'
);
```

### Move a file from one location to another

```dart
await ICloudStorage.move(
  containerId: 'iCloudContainerId',
  fromRelativePath: 'dir/file',
  toRelativePath: 'dir/subdir/file',
);
```

### Rename a file

```dart
await ICloudStorage.rename(
  containerId: 'iCloudContainerId',
  relativePath: 'relativePath',
  newName: 'newName',
);
```

### Error handling

```dart
catch (err) {
  if (err is PlatformException) {
    if (err.code == PlatformExceptionCode.iCloudConnectionOrPermission) {
      print(
          'Platform Exception: iCloud container ID is not valid, or user is not signed in for iCloud, or user denied iCloud permission for this app');
    } else if (err.code == PlatformExceptionCode.fileNotFound) {
      print('File not found');
    } else {
      print('Platform Exception: ${err.message}; Details: ${err.details}');
    }
  } else {
    print(err.toString());
  }
}
```

## Support for macOS

When uploading and downloading files, make sure the File Access is enabled for the local files if App Sandbox is enabled. Access are enabled for the files in the app's container (/Users/{username}/Library/Containers/{bundle_identifier}). Files in other locations can be enabled from XCode.

## Migrating from version 1.x.x to 2.0.0

- Version 2 supports operations on multiple containers. Therefore, `ICloudStorage.getInstance('iCloudContainerId')` is no longer needed. Instead, you'll need to specifiy the iCloudContainerId in each method.
- All methods in version 2 have been changed to static methods.
- `gatherFiles` has been renamed to `gather`.
- `startUpload` has been renamed to `upload`.
- `startDownload` has been renamed to `download`.

## FAQ

Q: I uploaded a file from a device. I signed in to a simulator using the same iCloud account. But the file is not showing up in the gatherFiles result.

A: From the menu 'Features' click 'Tigger iCloud Sync'.

Q: I uploaded a file from device A. I signed in to device B using the same iCloud account. But the file is not showing up in the gatherFiles result.

A: The API only queries files that's been synced to the iCloud container, which lives in the local device. You'll need to wait for iOS to sync the files from iCloud to the local container. There's no way to programmatically trigger iOS to Sync with iCloud.

Q: I removed a file using 'delete' method then called 'gatherFiles'. The deleted file still shows up in the list.

A: This is most likely to be an issue with the native code. However, if you call 'gatherFiles' first and listen the update, then do the deletion, the list is refreshed immediately in the onUpdate stream.

## How to set up iCloud Container and enable the capability

1. Log in to your apple developer account and select 'Certificates, IDs & Profiles' from the left navigation.
2. Select 'Identifiers' from the 'Certificates, IDs & Profiles' page, create an App ID if you haven't done so, and create an iCloud Containers ID.
   ![icloud container id](./doc/images/icloud_container_id.png)
3. Click on your App ID. In the Capabilities section, select 'iCloud' and assign the iCloud Container created in step 2 to this App ID.
   ![assign icloud capability](./doc/images/assign_icloud_capability.png)
4. Open your project in Xcode. Set your App ID as 'Bundle Identifier' if you haven't done so. Click on '+ Capability' button, select iCloud, then tick 'iCloud Documents' in the Services section and select your iCloud container.
   ![xcode capability](./doc/images/xcode_capability.png)

## References
[Apple Documentation - iCloud Storage Overview](https://wwdcnotes.com/documentation/wwdcnotes/wwdc12-209-icloud-storage-overview/#overview)

[Apple Documentation - iOS Data Storage Guidelines](https://developer.apple.com/icloud/documentation/data-storage/)

[Apple Documentation - Designing for Documents in iCloud](https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/Chapters/DesigningForDocumentsIniCloud.html)

# Attributions

This improved iCloud Storage plugin is based on the [icloud_storage](https://github.com/deansyd/icloud_storage) plugin by Dean Sydney (deansyd), with additional features and improvements from multiple contributors. Below are the specific contributions incorporated into this enhanced version.

## Open Pull Requests

### Improved Error Handling
- **Pull Request**: [PR #40](https://github.com/deansyd/icloud_storage/pull/40)
- **Contributor**: Jorge Sardina ([@js2702](https://github.com/js2702))
- **Features**:
  - Enhanced error handling
  - More specific exception types
  - Improved error messages

### Improved IO Changes
- **Pull Request**: [PR #45](https://github.com/deansyd/icloud_storage/pull/45)
- **Contributor**: Vishal Rao ([@vishalrao8](https://github.com/vishalrao8))
- **Features**:
  - Improved file handling
  - Enhanced I/O operations
  - Better performance
  - Method to access the root iCloud container directory

## Feature Contributions

### iCloud Availability Check
- **Repository**: [TrangLeQuynh/icloud_storage](https://github.com/TrangLeQuynh/icloud_storage)
- **Author**: Trang Le Quynh
- **Commit**: [5069e2c161d89cb90fe07b8ab6b6cf375fc8ac65](https://github.com/TrangLeQuynh/icloud_storage/commit/5069e2c161d89cb90fe07b8ab6b6cf375fc8ac65)
- **Feature**: Method to check if iCloud is available before performing operations
- **Files Modified**: 
  - `lib/icloud_storage.dart`
  - `lib/icloud_storage_platform_interface.dart`
  - `lib/icloud_storage_method_channel.dart`
  - `ios/Classes/SwiftIcloudStoragePlugin.swift`

### Get Root Directory (Superseded by PR #45)
- **Repository**: [rizerco/icloud_storage](https://github.com/rizerco/icloud_storage)
- **Author**: Rizerco
- **Commit**: [5aec3f761db34f2484dad100bf28737254762d76](https://github.com/rizerco/icloud_storage/commit/5aec3f761db34f2484dad100bf28737254762d76)
- **Feature**: Method to access the root iCloud container directory
- **Note**: This implementation has been superseded by PR #45 which provides equivalent functionality
- **Files Modified**:
  - `lib/icloud_storage.dart`
  - `lib/icloud_storage_platform_interface.dart`
  - `lib/icloud_storage_method_channel.dart`
  - `ios/Classes/SwiftIcloudStoragePlugin.swift`

### Download In Place Method
- **Repository**: [rizerco/icloud_storage](https://github.com/rizerco/icloud_storage)
- **Author**: Rizerco
- **Commit**: [39d1be3850595b3fda8c98bca56b70a15c6acb2a](https://github.com/rizerco/icloud_storage/commit/39d1be3850595b3fda8c98bca56b70a15c6acb2a)
- **Feature**: Method to download a file without specifying a destination
- **Files Modified**:
  - `lib/icloud_storage.dart`
  - `lib/icloud_storage_platform_interface.dart`
  - `lib/icloud_storage_method_channel.dart`
  - `ios/Classes/SwiftIcloudStoragePlugin.swift`

### Get Absolute Path
- **Repository**: [rizerco/icloud_storage](https://github.com/rizerco/icloud_storage)
- **Author**: Rizerco
- **Commits**: 
  - [368ef67634251b75cc355c780805e66f29e7ec83](https://github.com/rizerco/icloud_storage/commit/368ef67634251b75cc355c780805e66f29e7ec83) - Main implementation
  - [5900bc0fe371ac1548f44e9d5ab19a44d4eec50f](https://github.com/rizerco/icloud_storage/commit/5900bc0fe371ac1548f44e9d5ab19a44d4eec50f) - Path encoding fix
- **Feature**: Method to get the absolute path for a file in iCloud
- **Files Modified**:
  - `lib/icloud_storage.dart`
  - `lib/icloud_storage_platform_interface.dart`
  - `lib/icloud_storage_method_channel.dart`
  - `ios/Classes/SwiftIcloudStoragePlugin.swift`

### Display File Attributes
- **Repository**: [rizerco/icloud_storage](https://github.com/rizerco/icloud_storage)
- **Author**: Rizerco
- **Commit**: [6649b1b3fd7d38f8d9b459dc82a5243eff30c80f](https://github.com/rizerco/icloud_storage/commit/6649b1b3fd7d38f8d9b459dc82a5243eff30c80f)
- **Feature**: Method to retrieve detailed file attributes
- **Files Modified**:
  - `lib/icloud_storage.dart`
  - `lib/icloud_storage_platform_interface.dart`
  - `lib/icloud_storage_method_channel.dart`
  - `ios/Classes/SwiftIcloudStoragePlugin.swift`

## Integration Approach

This improved version of the iCloud Storage plugin integrates various contributions from pull requests and forks. The integration follows these key principles:

1. Starting with the base package (deansyd/icloud_storage)
2. Applying PR changes (#40 and #45)
3. Adding functionality from the TrangLeQuynh and Rizerco forks
4. Ensuring compatibility between all integrated components
5. Testing thoroughly before publication

### Implementation Decisions

- For overlapping functionality, I prioritize PRs over fork-specific implementations
- PR #45 will be used for accessing the root iCloud container directory instead of the separate Rizerco implementation, as it provides equivalent functionality with additional performance improvements
- All other non-overlapping features from the Rizerco fork will be integrated as specified

## License

All contributions and improvements are provided under the original MIT License.




