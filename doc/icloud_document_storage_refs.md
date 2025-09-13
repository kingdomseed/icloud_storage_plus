# iCloud Document Storage – Swift & Platform-Channel Reference

This document collects key Apple documentation, WWDC sessions, and conceptual guides that are useful when extending **icloud_storage_plus** with native iCloud **document** storage features via Platform Channels.

## Why this matters

`icloud_storage_plus` already provides basic upload / download APIs.  To support **Files-app–visible documents** and more advanced sync semantics we need to understand Apple’s native document APIs (UIDocument, NSFileCoordinator, ubiquity containers, etc.) and how to bridge them to Dart.

## Core Apple References (latest)

| Topic | Documentation / Session | Notes |
|-------|-------------------------|-------|
| Synchronising documents | https://developer.apple.com/documentation/uikit/synchronizing-documents-in-the-icloud-environment | Current high-level guide for iOS / iPadOS apps using UIDocument and NSMetadataQuery. |
| `FileManager` iCloud utilities | https://developer.apple.com/documentation/foundation/filemanager | See `ubiquityIdentityToken`, `url(forUbiquityContainerIdentifier:)`. |
| Background file coordination | https://developer.apple.com/documentation/foundation/nsfilecoordinator | Avoid file corruption in multi-process access. |
| Metadata queries | https://developer.apple.com/documentation/foundation/nsmetadataquery | Discover iCloud files and monitor changes. |
| WWDC23 – "What’s new in iCloud and CloudKit" | (search via Developer app) | Latest best-practices for iCloud file sync, quotas, & performance. |

## Archive / Historical but still useful

* WWDC12-209 *iCloud Storage Overview* – https://wwdcnotes.com/documentation/wwdcnotes/wwdc12-209-icloud-storage-overview/
* File-System Programming Guide – *iCloud Storage* chapter (Archived) – https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/iCloud/iCloud.html

## Key Concepts to expose via Platform Channels

1. **Ubiquity Containers**
   * Use `FileManager.url(forUbiquityContainerIdentifier:)` to obtain the app’s iCloud container path.
   * Always check `FileManager.ubiquityIdentityToken` to verify iCloud availability.

2. **Document Storage vs. Key-Value / CloudKit**
   * `UIDocument`/`NSDocument` wrappers give automatic conflict resolution & Files-app visibility.
   * Sync happens opportunistically; monitor with `NSMetadataQuery`.

3. **File Coordination & Presentation**
   * Adopt `NSFileCoordinator` / `NSFilePresenter` to avoid race conditions.
   * Offload heavy I/O to background queues (never block UI / Flutter thread).

4. **Asynchronous Transfer Progress**
   * Use `NSProgress` with KVO to report upload / download status back to Dart side.

5. **Conflict Resolution**
   * `UIDocumentStateInConflict` and `NSFileVersion` APIs allow listing & resolving versions.

6. **Sandbox & App Groups** (macOS / iOS)
   * Ensure the correct entitlements: `com.apple.developer.icloud-services`, `com.apple.developer.ubiquity-container-identifiers`.

## Bridging Strategy (Swift 5.9  ➜  Dart)

* Expose **method-channel** calls for:
  * `getUbiquityContainerUrl()` → returns path as `String`.
  * `listDocuments(relativePath)` → returns list of metadata records.
  * `readDocument(path)` / `writeDocument(path, bytes)` with background queue I/O.
  * `observeMetadataChanges()` → set up event channel streaming file changes.
* Return structured error enums conforming to existing `icloud_storage_plus` exception model.

## Next Steps

1. Prototype `getUbiquityContainerUrl` in `SwiftIcloudStoragePlugin` and surface to Dart.
2. Add doc-based unit tests on macOS (using `XCTest`) and integration tests in example app.
3. Document new APIs in `README.md` and update CHANGELOG.

---

_Last updated: 2025-06-25_
