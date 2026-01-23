# iCloud Storage Plus Technical Context

## Technologies Used

### Programming Languages

1. **Dart**
   - Used for the Flutter plugin API and platform interface
   - Version: Compatible with Dart 2.12+ (null safety)

2. **Swift**
   - Used for the iOS and macOS native implementations
   - iOS: Swift 5.0+
   - macOS: Swift 5.0+

### Frameworks & APIs

1. **Flutter**
   - Plugin architecture using method channels and event channels
   - Platform interface pattern for extensibility
   - Compatible with Flutter 2.0+

2. **Apple iCloud APIs**
   - NSFileManager: Basic file operations and iCloud container access
   - NSFileCoordinator: Coordinated file access to prevent conflicts
   - NSMetadataQuery: File discovery and monitoring
   - UIDocument/NSDocument: Document-based file operations (planned)

## Development Setup

### Environment Requirements

1. **Flutter SDK**
   - Flutter 2.0 or higher
   - Dart 2.12 or higher (with null safety)

2. **iOS Development**
   - Xcode 12.0 or higher
   - iOS 9.0+ deployment target
   - Valid Apple Developer account for iCloud capabilities

3. **macOS Development**
   - Xcode 12.0 or higher
   - macOS 10.11+ deployment target
   - Valid Apple Developer account for iCloud capabilities

### Project Structure

```
icloud_storage_plus/
├── lib/                      # Dart code
│   ├── icloud_storage.dart   # Main API
│   ├── icloud_storage_platform_interface.dart
│   ├── icloud_storage_method_channel.dart
│   └── models/               # Data models
│       ├── exceptions.dart
│       └── icloud_file.dart
├── ios/                      # iOS implementation
│   └── Classes/
│       ├── IcloudStoragePlugin.h
│       ├── IcloudStoragePlugin.m
│       └── SwiftIcloudStoragePlugin.swift
├── macos/                    # macOS implementation
│   └── Classes/
│       └── IcloudStoragePlugin.swift
├── example/                  # Example app
├── test/                     # Unit tests
└── docs/                     # Documentation
    ├── architecture/         # System design
    ├── guides/              # How-to guides
    └── archive/             # Historical docs
```

## Technical Constraints

### Platform Limitations

1. **iOS/macOS Only**
   - iCloud is only available on Apple platforms
   - No Android, Windows, or web support

2. **iCloud Account Required**
   - End users must have an active iCloud account
   - Sufficient iCloud storage space needed for operations

3. **App Store Requirements**
   - Apps using iCloud must be distributed through the App Store
   - iCloud entitlements must be properly configured

### API Constraints

1. **File Size Limitations**
   - iCloud has practical limits on file sizes (typically up to 50GB)
   - Large files may experience slower sync times

2. **Background Processing**
   - iOS may limit background processing time for uploads/downloads
   - Apps must handle suspension gracefully

3. **Conflict Resolution**
   - Current implementation has limited conflict resolution capabilities
   - Document-based approach will improve this in future updates

## Dependencies

### Direct Dependencies

1. **Flutter Plugin Framework**
   - `flutter/plugin_platform_interface`: For platform interface pattern
   - Version: ^2.0.0

2. **Apple Frameworks**
   - Foundation.framework
   - CoreServices.framework
   - UIKit.framework (iOS)
   - AppKit.framework (macOS)

### Development Dependencies

1. **Testing**
   - `flutter_test`: For unit testing
   - `mockito`: For mocking in tests

2. **Build Tools**
   - CocoaPods: For iOS/macOS native dependencies
   - Flutter build system

## Integration Requirements

### For App Developers

1. **iCloud Container Configuration**
   - Configure iCloud container ID in app entitlements
   - Add iCloud capability in Xcode project

2. **Info.plist Configuration**
   - Add `NSUbiquitousContainers` entry with container details

3. **Entitlements**
   - `com.apple.developer.icloud-container-identifiers`
   - `com.apple.developer.icloud-services`
   - `com.apple.developer.ubiquity-container-identifiers`

### Example Configuration

```xml
<!-- Info.plist -->
<key>NSUbiquitousContainers</key>
<dict>
    <key>iCloud.com.example.app</key>
    <dict>
        <key>NSUbiquitousContainerIsDocumentScopePublic</key>
        <true/>
        <key>NSUbiquitousContainerName</key>
        <string>App Name</string>
        <key>NSUbiquitousContainerSupportedFolderLevels</key>
        <string>Any</string>
    </dict>
</dict>

<!-- Entitlements file -->
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.com.example.app</string>
</array>
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudDocuments</string>
</array>
<key>com.apple.developer.ubiquity-container-identifiers</key>
<array>
    <string>iCloud.com.example.app</string>
</array>
```

## Performance Considerations

1. **File Transfer Speed**
   - Dependent on network conditions and file size
   - Progress monitoring essential for user feedback

2. **Memory Usage**
   - Large file operations should be mindful of memory constraints
   - Streaming approach recommended for large files

3. **Battery Impact**
   - Continuous sync operations can impact battery life
   - Batch operations when possible

4. **Storage Efficiency**
   - iCloud storage counts against user's quota
   - Implement cleanup mechanisms for temporary files
