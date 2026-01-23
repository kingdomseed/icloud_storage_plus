# README Structure Plan

## Proposed Structure

### 1. Header
- Project name
- One-line description: what it does

### 2. Key Improvements
- **No "file locked" errors:** Prevents conflicts when your app and iCloud sync access files simultaneously
- **Detects remote files:** Finds files stored in iCloud even if they haven't been downloaded to this device yet
- **Automatic conflict resolution:** When two devices modify the same file, conflicts resolve automatically
- **Files app integration:** Make your app's files visible in the iOS/macOS Files app so users can access them

### 3. Concepts You Need to Know
**Purpose:** Plain-English explanations before any technical terms or code

**iCloud Container:**
- A special folder on Apple's servers that's linked to your app
- Think of it as your app's private cloud storage space
- Your app gets the container URL from iOS using a container ID you set up in Apple Developer portal

**The Magic "Documents" Folder:**
- iOS has a special rule: files in a subfolder called "Documents" can be visible in the Files app
- This is NOT a folder you create manually - iOS creates it automatically
- You access it by using the exact string "Documents/" at the start of your file path
- **Case-sensitive:** Must be "Documents/" (capital D), not "documents/" or "DOCUMENTS/"

**How Files Move Between Device and iCloud:**
```
Your App
    ↓ writes file
'Documents/my_doc.md' on device
    ↓ iOS automatically syncs
iCloud servers store file
    ↓ appears in
Files app (if configured correctly)
    ↓ iOS syncs to
Other devices signed into same iCloud account
```

**File Coordination (Why It Matters):**
- Problem: Your app tries to read a file while iCloud sync is writing to it → "file is locked" error
- Solution: iOS provides NSFileCoordinator (this plugin uses it automatically via UIDocument)
- Result: No permission errors, no data corruption from simultaneous access

### 4. How It Works (Technical Foundation)
**Purpose:** Explain the underlying iOS/macOS APIs (for developers who want details)

**File Discovery:**
- Uses NSMetadataQuery to detect files in iCloud (both local and remote)
- Can find files that exist in iCloud but haven't been downloaded to this device

**Safe Operations:**
- Uses NSFileCoordinator and UIDocument for coordinated read/write
- Prevents "permission denied" errors when iCloud sync accesses files simultaneously

**Conflict Resolution:**
- Automatic via UIDocument when two devices modify the same file
- Plugin handles conflicts without your code needing to do anything

**Apple Documentation Links:**
- [NSMetadataQuery](https://developer.apple.com/documentation/foundation/nsmetadataquery) - Finding iCloud files
- [NSFileCoordinator](https://developer.apple.com/documentation/foundation/nsfilecoordinator) - Safe file access
- [UIDocument](https://developer.apple.com/documentation/uikit/uidocument) (iOS) / [NSDocument](https://developer.apple.com/documentation/appkit/nsdocument) (macOS) - Document storage
- [iCloud Document Storage](https://developer.apple.com/icloud/documentation/data-storage/) - Overview

### 5. Quick Start
**Purpose:** Get developers up and running with actual Dart code examples

**Installation:**
```bash
flutter pub add icloud_storage_plus
```

**Complete Working Example:**
```dart
import 'package:icloud_storage_plus/icloud_storage.dart';
import 'dart:convert';

// 1. Check if iCloud is available
final available = await ICloudStorage.icloudAvailable();
if (!available) {
  print('iCloud not available');
  return;
}

// 2. Write a document to iCloud (visible in Files app)
final content = '''# My Notes
Created: ${DateTime.now()}

This is a document that syncs across all my devices.
''';

await ICloudStorage.writeDocument(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/my_document.md',  // Documents/ = visible in Files app
  data: utf8.encode(content),
);

// 3. Read it back later
final bytes = await ICloudStorage.readDocument(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/my_document.md',
);

if (bytes != null) {
  print('Document content: ${utf8.decode(bytes)}');
}
```

**That's it!** The plugin handles:
- Automatic downloading if the file is in iCloud but not local
- File coordination (prevents "permission denied" errors)
- Conflict resolution when two devices modify the same file
- Sync across all your user's devices signed into iCloud

### 6. Enabling iCloud Sync
**Purpose:** Answer "How do I enable iCloud syncing?"

Clear step-by-step:
1. Apple Developer setup (Container ID, App ID)
2. Xcode configuration (Capabilities, entitlements)
3. Container ID in code
4. Verify availability check

### 7. Making Files Visible in iCloud Drive
**Purpose:** Answer "How do I make files show up in iCloud Drive?"

**CRITICAL Requirement #1: Use the Magic "Documents/" String**

To make files visible in the iOS/macOS Files app, you MUST:
- Use the exact string `"Documents/"` at the start of your `relativePath` parameter
- This is NOT a folder you create - iOS creates it automatically in your iCloud container
- **Case-sensitive:** Must be `"Documents/"` (capital D)
- **Exact string:** Cannot be `"documents/"`, `"DOCUMENTS/"`, `"MyDocuments/"`, or anything else

Examples:
```dart
// ✓ CORRECT - Will appear in Files app
await ICloudStorage.writeDocument(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/savegame.json',  // ← Starts with "Documents/"
  data: jsonBytes,
);

// ✗ WRONG - Will NOT appear in Files app
await ICloudStorage.writeDocument(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'documents/savegame.json',  // ← lowercase "documents" - wrong!
  data: jsonBytes,
);

// ✗ WRONG - Will NOT appear in Files app
await ICloudStorage.writeDocument(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'MyFiles/savegame.json',  // ← Not "Documents/" - wrong!
  data: jsonBytes,
);

// ✗ WRONG - Will NOT appear in Files app
await ICloudStorage.writeDocument(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'cache/temp.json',  // ← No "Documents/" prefix - private to app
  data: jsonBytes,
);
```

**Requirement #2: Configure Info.plist**

Your app's Info.plist must include `NSUbiquitousContainers` configuration:

**Requirement #3: Set Container to Public**

Container must have `NSUbiquitousContainerIsDocumentScopePublic = true` in Info.plist

**Show exact Info.plist XML:**
```xml
<key>NSUbiquitousContainers</key>
<dict>
    <key>iCloud.com.yourapp.container</key>
    <dict>
        <key>NSUbiquitousContainerIsDocumentScopePublic</key>
        <true/>
        <key>NSUbiquitousContainerName</key>
        <string>YourAppName</string>
    </dict>
</dict>
```

**Show code example:**
```dart
// Visible in Files app
await ICloudStorage.writeDocument(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/my_document.json',
  data: jsonBytes,
);
```

**Where Files Actually Go:**
```
Your iCloud Container (iCloud.com.yourapp.container)
│
├── Documents/                    ← FILES APP VISIBLE (if Info.plist configured)
│   ├── savegame.json            ✓ Users see this in Files app
│   ├── settings.json            ✓ Users see this in Files app
│   └── reports/
│       └── monthly.pdf          ✓ Users see this in Files app
│
└── [other folders]               ← HIDDEN from Files app (private to your app)
    ├── cache/
    │   └── temp.dat             ✗ Hidden from Files app
    └── config.json              ✗ Hidden from Files app
```

### 8. API Reference
- Keep current structure but streamline
- Focus on most common operations first
- Advanced operations section for specialized needs
- Clarify `exists()` returns true for files **and directories**
 - Note breaking change: `getMetadata()` returns metadata for files and
   directories with `isDirectory`/`type` field; directory fields may be null
   if not provided by iCloud metadata

### 9. iOS vs macOS Differences
**Purpose:** Clarify platform-specific behavior and requirements

**From Dart Code Perspective:**
The Dart API is **identical** across iOS and macOS. You use the same code:
```dart
// Same code works on both iOS and macOS
await ICloudStorage.writeDocument(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/file.json',
  data: bytes,
);
```

**Native Implementation Differences:**
Under the hood, the plugin uses platform-appropriate APIs:

| Feature | iOS | macOS |
|---------|-----|-------|
| Document API | UIDocument | NSDocument |
| File coordination | NSFileCoordinator (iOS) | NSFileCoordinator (macOS) |
| Query API | NSMetadataQuery (iOS) | NSMetadataQuery (macOS) |
| Container access | FileManager.url(forUbiquityContainerIdentifier:) | Same |
| Files app integration | iOS Files app | macOS Finder |

**Setup Differences:**
- **iOS**: Configure in Xcode iOS target → Signing & Capabilities → iCloud
- **macOS**: Configure in Xcode macOS target → Signing & Capabilities → iCloud
- **Info.plist**: Same `NSUbiquitousContainers` configuration for both platforms
- **Entitlements**: Same entitlement keys for both platforms

**Behavioral Differences:**
1. **Files app appearance**:
   - iOS: Files appear in the iOS Files app under "iCloud Drive" → "YourAppName"
   - macOS: Files appear in Finder under "iCloud Drive" → "YourAppName"

2. **Sync timing**:
   - iOS: May defer uploads when on cellular to save data
   - macOS: Typically syncs immediately when on any network

3. **Storage limits**:
   - Both platforms respect user's iCloud storage quota
   - No artificial limits imposed by the plugin

**You don't need to worry about these differences** - the plugin handles all platform-specific details automatically.

### 10. Common Issues
- Keep current troubleshooting content
- Add section on Info.plist configuration problems
- Add section on Documents/ folder requirement (case-sensitivity, exact string)

### 10. Credits and Recognition
**Purpose:** Acknowledge original work

- Based on [icloud_storage](https://pub.dev/packages/icloud_storage) by [author]
- This fork adds:
  - NSFileCoordinator integration
  - Improved file coordination
  - iCloud Drive visibility support
  - Enhanced documentation

## Changes from Current README

**Move to end:**
- "Based on icloud_storage" credit (currently line 3)

**Add new sections:**
- "Concepts You Need to Know" (Section 3) - Plain-English explanations BEFORE technical details
- "How It Works" (Section 4) with technical foundation
- **"Quick Start" (Section 5) - Complete working Dart code example** (currently just has API examples without context)
- Crystal-clear "Documents/" folder explanation with correct/incorrect examples
- Clear Info.plist configuration in "Making Files Visible"
- **"iOS vs macOS Differences" (Section 9) - Platform-specific behavior and setup** (not currently documented)
- Direct Apple documentation links

**Enhance existing sections:**
- Section 5 "Quick Start": Replace with complete working example showing iCloud availability check, writing a document, and reading it back
- Section 8 "API Reference": Streamline to focus on most common operations first (readDocument, writeDocument, exists)

**Simplify:**
- Reduce repetitive examples
- Remove "throat clearing" language
- Direct, outcome-focused tone

**Emphasize:**
- **Actual Dart API usage** - Show developers the code they'll write, not just theory
- Documents/ folder requirement with CRYSTAL CLEAR explanation (case-sensitive, exact string, iOS creates it)
- Info.plist configuration (not currently documented)
- Plain-English concepts before technical jargon
- What the APIs DO (prevent errors) not just what they ARE
- **Platform transparency** - Same Dart API works on both iOS and macOS

## Key Questions Answered

1. **"How do I use this plugin in my Dart code?"** → Section 5 "Quick Start" with complete working example
2. **"What is an iCloud container?"** → Section 3 "Concepts" with plain-English explanation
3. **"What does 'Documents/' mean?"** → Section 3 "Concepts" explains the magic folder + Section 7 with detailed examples
4. **"How do I enable iCloud syncing?"** → Section 6 with clear setup steps
5. **"How do I make files show up in iCloud Drive?"** → Section 7 with Info.plist config, Documents/ requirement, and correct/incorrect examples
6. **"Are there differences between iOS and macOS?"** → Section 9 explains the Dart API is identical, shows platform-specific details
7. **"What Dart methods should I use?"** → Section 8 "API Reference" focuses on recommended methods (readDocument, writeDocument)

## Links to Include

All links should point to current Apple documentation:
- https://developer.apple.com/documentation/foundation/nsmetadataquery
- https://developer.apple.com/documentation/foundation/nsfilecoordinator
- https://developer.apple.com/documentation/uikit/uidocument
- https://developer.apple.com/documentation/appkit/nsdocument
- https://developer.apple.com/icloud/documentation/data-storage/
- https://developer.apple.com/documentation/xcode/configuring-icloud-services
