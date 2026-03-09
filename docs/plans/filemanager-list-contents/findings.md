# FileManager-based listContents: Discovery & Findings

## Problem Statement

After a `FileManager.moveItem()` (rename) in the iCloud ubiquity container, the
plugin's `gather()` method returns stale file listings because it uses a one-shot
`NSMetadataQuery` that queries the Spotlight metadata index — which is eventually
consistent and lags behind filesystem mutations.

**Observed in:** Mythic GME 2e — rename a journal in iCloud mode → file renamed
on disk → immediate `gather()` still shows old filename → UI does not update →
second rename attempt fails because old file no longer exists.

**Why local storage is unaffected:** The local (non-iCloud) code path uses
`Directory.list()` (Dart's `dart:io`), which calls POSIX `readdir()` directly on
the filesystem — always immediately consistent.

## Root Cause Analysis

### gather() implementation (iOS & macOS)

Both platforms use the identical pattern (line ~105 in each):

1. Create `NSMetadataQuery` with `NSMetadataItemPathKey beginswith containerURL.path`
2. Register observer for `NSMetadataQueryDidFinishGathering`
3. `query.start()` — fires a one-shot Spotlight index query
4. On `didFinishGathering` → extract results → stop query → return to Dart

The Spotlight metadata index is updated **asynchronously** by the `mds`/`mdworker`
system daemons after filesystem mutations. There is no synchronous "flush" API.

### move() implementation (iOS ~line 1044, macOS ~line 1019)

Uses `NSFileCoordinator` with `.forMoving` + `.forReplacing` options, then
`FileManager.moveItem(at:to:)`. The move completes synchronously on the
filesystem — the file IS renamed — but the metadata index has not caught up.

### Apple's documented behavior

- **WWDC 2015 Session 234:** "The coordinated operation works in conjunction with
  the NSMetadataQuery... and immediately tells your running query that there's a
  new updated document." — but ONLY for a **persistent, already-running** query.
  A one-shot query started AFTER the mutation has no running query to receive the
  notification. Without it, "half a second or something, possibly even more."

- **Damien Deville (2013):** Observed 2–6 second delays before the ubiquity
  daemon's database reflects new items after `setUbiquitous:itemAtURL:`.

- **Apple iCloud File Management Guide:** "Using a query to search is the only
  way to ensure an accurate list of documents." — but this refers to discovering
  remote-only files and document promises, not to immediate consistency after
  local mutations.

## Proposed Solution: `listContents` API

Add a new plugin method that uses `FileManager.contentsOfDirectory(at:...)` to
read the actual filesystem instead of the metadata index.

### Why FileManager.contentsOfDirectory works

- Reads the POSIX filesystem directly (like `readdir()`)
- Immediately consistent after `FileManager.moveItem/removeItem/copyItem`
- Works on ubiquity container URLs from `url(forUbiquityContainerIdentifier:)`

### Key caveats to handle

| Concern | Detail |
|---|---|
| **Placeholder files** | Non-downloaded files appear as `.originalName.icloud`. Must strip leading dot + trailing `.icloud` to recover real filename. |
| **`.skipsHiddenFiles`** | Must NOT use — placeholders have a leading dot and would be filtered out. |
| **No cloud metadata** | No download/upload status, no conflict info. This is a filenames-only listing. |
| **Threading** | `url(forUbiquityContainerIdentifier:)` can block on first access. Must dispatch to background queue. |
| **Directories** | Must filter out directories (use `.isRegularFileKey` resource value). |

### When to use each API

| Operation | Use |
|---|---|
| **Listing after own mutations** (rename, delete, save) | `listContents` — immediate consistency |
| **Monitoring remote sync** (changes from other devices) | `gather()` with `onUpdate` stream — rich metadata |
| **Initial app launch discovery** | Either — `gather()` gives download status; `listContents` is faster and consistent |

### What this does NOT replace

`gather()` / `NSMetadataQuery` is still required for:
- Download/upload status tracking
- Conflict detection (`hasUnresolvedConflicts`)
- Discovering document promises (files known to iCloud but not yet local)
- Real-time change notifications from remote devices

---

## Deep Dive: Detecting iCloud Placeholder Files Properly

Research conducted 2026-03-09 into proper Apple APIs for detecting and handling
iCloud placeholder/dataless files, beyond naive `.icloud` string stripping.

### 1. Two Eras of Placeholder Files

There are two distinct mechanisms depending on OS version:

**Pre-macOS Sonoma (iOS always, macOS < 14):** Traditional `.icloud` stub files.
When a file `lesson1.pdf` exists in iCloud but is not downloaded locally, the
filesystem contains a stub file named `.lesson1.pdf.icloud`. This stub is a
binary plist containing:

```
{
  "NSURLNameKey": "lesson1.pdf",
  "NSURLFileSizeKey": 206739,
  "NSURLFileResourceTypeKey": "NSURLFileResourceTypeRegular"
}
```

The stub is typically < 200 bytes and has a `com.apple.icloud.itemName` extended
attribute containing the original filename as a UTF-8 string.

**macOS Sonoma+ (macOS 14+):** APFS "dataless" files. The `.icloud` stub files
are eliminated. Instead, evicted files appear as regular files with their full
names but with no data extents. They report their logical size (as if fully
downloaded) but occupy minimal disk space. Detection requires checking the
`SF_DATALESS` flag in `stat.st_flags` or using URL resource values. (See Apple
TN3150.)

**iOS:** As of the latest research, iOS still uses the traditional `.icloud`
stub file mechanism for iCloud Documents containers.

### 2. Apple APIs for Detecting Download Status (Without NSMetadataQuery)

**Yes, `URL.resourceValues(forKeys:)` can check download status per-file without
NSMetadataQuery.** This is the key finding.

#### Available URLResourceKey values for iCloud files:

| Key | Type | Description |
|-----|------|-------------|
| `.ubiquitousItemDownloadingStatusKey` | `URLUbiquitousItemDownloadingStatus?` | Current download state |
| `.ubiquitousItemIsDownloadingKey` | `Bool?` | Whether the system is actively downloading |
| `.ubiquitousItemIsUploadingKey` | `Bool?` | Whether the system is actively uploading |
| `.ubiquitousItemIsUploadedKey` | `Bool?` | Whether the item has been uploaded to iCloud |
| `.ubiquitousItemHasUnresolvedConflictsKey` | `Bool?` | Whether there are unresolved version conflicts |
| `.ubiquitousItemDownloadRequestedKey` | `Bool?` | Whether a download has been requested |
| `.ubiquitousItemContainerDisplayNameKey` | `String?` | Display name of the ubiquity container |
| `.ubiquitousItemIsExcludedFromSyncKey` | `Bool?` | Whether excluded from sync |
| `.ubiquitousItemIsSharedKey` | `Bool?` | Whether the item is shared |
| `.ubiquitousSharedItemCurrentUserRoleKey` | `URLUbiquitousSharedItemRole?` | Current user's role |
| `.ubiquitousSharedItemCurrentUserPermissionsKey` | `URLUbiquitousSharedItemPermissions?` | Current user's permissions |

#### URLUbiquitousItemDownloadingStatus enum values:

| Case | Meaning |
|------|---------|
| `.notDownloaded` | Item exists only in iCloud, no local data |
| `.downloaded` | Item has local data that may not be the latest version |
| `.current` | Local data is the most recent version available in iCloud |

**Important:** `.current` means "up-to-date local copy" (NOT "currently
downloading"). `.downloaded` means "has a local copy but it may be stale."
To check if actively downloading, use `.ubiquitousItemIsDownloadingKey` instead.

#### Per-file status check example:

```swift
let url: URL = // some file URL in ubiquity container
let values = try url.resourceValues(forKeys: [
    .ubiquitousItemDownloadingStatusKey,
    .ubiquitousItemIsDownloadingKey,
    .ubiquitousItemIsUploadedKey,
])

let status = values.ubiquitousItemDownloadingStatus
// .notDownloaded = placeholder / dataless
// .downloaded    = has local copy (possibly stale)
// .current       = local copy is up-to-date

let isDownloading = values.ubiquitousItemIsDownloading ?? false
let isUploaded = values.ubiquitousItemIsUploaded ?? false
```

#### Dataless detection helper:

```swift
extension URL {
    func isDataless() throws -> Bool {
        let status = try self
            .resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            .ubiquitousItemDownloadingStatus
        return status == .notDownloaded || status == nil
    }
}
```

### 3. FileManager.contentsOfDirectory WITH Ubiquitous Resource Keys

**Yes, `contentsOfDirectory(at:includingPropertiesForKeys:options:)` accepts
ubiquitous resource keys.** Passing them in `includingPropertiesForKeys` causes
the system to prefetch those values, making subsequent `resourceValues(forKeys:)`
calls on each URL cheap (they read from cache rather than hitting the filesystem
again).

```swift
let containerURL = FileManager.default
    .url(forUbiquityContainerIdentifier: containerId)!
    .appendingPathComponent("Documents")

let keys: [URLResourceKey] = [
    .isRegularFileKey,
    .isDirectoryKey,
    .ubiquitousItemDownloadingStatusKey,
    .ubiquitousItemIsDownloadingKey,
    .ubiquitousItemIsUploadedKey,
    .ubiquitousItemHasUnresolvedConflictsKey,
]

let contents = try FileManager.default.contentsOfDirectory(
    at: containerURL,
    includingPropertiesForKeys: keys,
    options: []  // Do NOT use .skipsHiddenFiles — placeholders have leading dot
)

for fileURL in contents {
    let values = try fileURL.resourceValues(forKeys: Set(keys))

    // Skip directories
    guard values.isRegularFile == true else { continue }

    let downloadStatus = values.ubiquitousItemDownloadingStatus
    let isDownloading = values.ubiquitousItemIsDownloading ?? false
    let isUploaded = values.ubiquitousItemIsUploaded ?? false
    let hasConflicts = values.ubiquitousItemHasUnresolvedConflicts ?? false

    // Resolve real filename from placeholder name
    let filename = resolveRealFilename(from: fileURL.lastPathComponent)

    print("\(filename): status=\(downloadStatus), downloading=\(isDownloading)")
}
```

### 4. Critical Caveats and Limitations

#### 4a. Placeholder filename resolution is STILL needed on iOS

Even when using `resourceValues`, `contentsOfDirectory` returns the on-disk
filename. For placeholder files on iOS (and pre-Sonoma macOS), that is
`.originalName.icloud`, not the real name. **You must still resolve the real
filename:**

```swift
func resolveRealFilename(from diskName: String) -> String {
    // If it's a placeholder: ".myfile.txt.icloud" → "myfile.txt"
    if diskName.hasPrefix(".") && diskName.hasSuffix(".icloud") {
        let withoutPrefix = String(diskName.dropFirst())      // "myfile.txt.icloud"
        let withoutSuffix = String(withoutPrefix.dropLast(7))  // "myfile.txt"
        return withoutSuffix
    }
    return diskName
}
```

**However**, this is just a fallback/confirmation. The proper detection uses
`ubiquitousItemDownloadingStatus` to determine whether a file is a placeholder,
not the filename pattern.

#### 4b. resourceValues returns nil/limited data for un-downloaded files

Apple confirms: "There is currently no public API to get the metadata for an
un-downloaded iCloud file." When querying a placeholder file:
- `.fileSizeKey` returns the stub file size (~192 bytes), NOT the real file size
- `.localizedTypeDescriptionKey` returns "Alias", not the real type
- `.ubiquitousItemDownloadingStatusKey` **DOES** return `.notDownloaded` correctly
- Other ubiquitous keys generally DO work on placeholders

The file-level metadata (name, size, type) is embedded inside the placeholder's
plist, but Apple provides no public API to read it. The `NSURLNameKey` inside
the plist gives the real name, and `NSURLFileSizeKey` gives the real size, but
you would need to parse the plist manually.

#### 4c. macOS Sonoma dataless files change the detection model

On macOS Sonoma+, dataless files:
- Have their REAL filename (no `.icloud` naming convention)
- Report their REAL file size (logical size, not physical)
- Return `.notDownloaded` for `ubiquitousItemDownloadingStatus`
- Have `SF_DATALESS` set in `stat.st_flags`
- Accessing their data triggers automatic "materialization" (download)

This means the `.icloud` filename resolution code is unnecessary on Sonoma+, but
`ubiquitousItemDownloadingStatusKey` works consistently across both models.

#### 4d. FileManager.isUbiquitousItem(at:)

This method returns `true` if the item at the given URL is stored in iCloud
(i.e., is in a ubiquity container). It works on BOTH placeholder files and
downloaded files. It does NOT tell you the download status — only whether the
file is managed by iCloud. Useful for confirming you are in a ubiquity container
before querying ubiquitous resource keys.

#### 4e. stat/getattrlist can trigger materialization

On macOS Sonoma+, calling `stat` or `getattrlist` on dataless directories
triggers materialization of intermediate folders. The recommendation from Apple
TN3150 is: "Avoid unnecessarily materializing dataless files and, when your app
requires access to a file's contents, perform that work asynchronously off the
main thread."

### 5. The Key Answer: Can contentsOfDirectory + resourceValues Replace NSMetadataQuery?

**For simple enumeration with download status: YES, mostly.**

`FileManager.contentsOfDirectory(at:includingPropertiesForKeys:)` with
ubiquitous resource keys gives you both the file listing AND the download status
per-file. This is sufficient for:

- Listing files and knowing which are downloaded vs placeholder
- Checking if a file is uploading or uploaded
- Detecting unresolved conflicts
- Immediate consistency after local mutations (rename, delete, copy)

**NSMetadataQuery is still required for:**

| Capability | FileManager | NSMetadataQuery |
|------------|:-----------:|:---------------:|
| File listing | Yes | Yes |
| Download status per file | Yes | Yes |
| Upload status per file | Yes | Yes |
| Conflict detection | Yes | Yes |
| Download/upload percentage progress | No | Yes (`NSMetadataUbiquitousItemPercentDownloadedKey`) |
| Real-time change notifications | No | Yes (`.NSMetadataQueryDidUpdate`) |
| Discovering files not yet synced to this device | Partial* | Yes |
| Immediate consistency after local mutations | Yes | No (delayed) |
| Real file size of un-downloaded files | No** | Yes (`NSMetadataItemFSSizeKey`) |

\* `contentsOfDirectory` sees placeholder files, so it does discover files known
to iCloud. But on macOS Sonoma with dataless files, the file appears with its
real name and the download status key tells you it is not downloaded.

\** On pre-Sonoma, `.fileSizeKey` returns the stub size (~192 bytes). On Sonoma+,
dataless files report their real logical size. NSMetadataQuery always returns the
real size via `NSMetadataItemFSSizeKey`.

### 6. Recommended Approach for icloud_storage_plus

For the `listContents` API that needs immediate consistency after mutations:

1. Use `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:options:)`
   with `[.isRegularFileKey, .ubiquitousItemDownloadingStatusKey]`
2. Filter to regular files only
3. For each file, resolve the real filename:
   - Check `ubiquitousItemDownloadingStatus` — if `.notDownloaded`, it may be a
     placeholder with the `.originalName.icloud` naming pattern
   - Strip the `.` prefix and `.icloud` suffix to get the real name
   - On macOS Sonoma+, the filename is already correct (dataless files keep
     their real name)
4. Return the resolved filenames as relative paths
5. Do NOT use `.skipsHiddenFiles` — placeholder files have a leading dot

For richer metadata (download progress, real-time sync monitoring), continue
using `gather()` with `NSMetadataQuery`.

### 7. fatbobman's Approach (Reference Implementation)

fatbobman's "Advanced iCloud Documents" article recommends NSMetadataQuery as
the primary approach for identifying placeholder files, using a
`MetadataItemWrapper` struct that checks
`NSMetadataUbiquitousItemDownloadingStatusKey`. His key insight:

> "Properly identifying placeholder files is based on the actual metadata state
> of the file, not just the file name."

His `MetadataItemWrapper` extracts:
- `fileName` via `NSMetadataItemFSNameKey` (always the real name)
- `fileSize` via `NSMetadataItemFSSizeKey` (always the real size)
- `isPlaceholder` via `NSMetadataUbiquitousItemDownloadingStatusKey`
- `downloadProgress` via `NSMetadataUbiquitousItemPercentDownloadedKey`
- `isUploaded` via `NSMetadataUbiquitousItemIsUploadedKey`

He also recommends using `NSFileCoordinator` for all file operations and notes
that `evictUbiquitousItem(at:)` must NOT use file coordination (deadlock risk).

## References

- [Apple: iCloud File Management Guide](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/iCloud/iCloud.html)
- [Apple: WWDC 2015 Session 234 — Building Document Based Apps](https://developer.apple.com/videos/play/wwdc2015/234/)
- [Apple: NSMetadataQuery API Reference](https://developer.apple.com/documentation/foundation/nsmetadataquery)
- [Apple: URLResourceKey Documentation](https://developer.apple.com/documentation/foundation/urlresourcekey)
- [Apple: URLUbiquitousItemDownloadingStatus](https://developer.apple.com/documentation/foundation/urlubiquitousitemdownloadingstatus)
- [Apple: FileManager.isUbiquitousItem(at:)](https://developer.apple.com/documentation/foundation/filemanager/1410218-isubiquitousitem)
- [Apple: TN3150 — Getting Ready for Dataless Files](https://developer.apple.com/documentation/technotes/tn3150-getting-ready-for-data-less-files)
- [Damien Deville: Debugging iCloud URL Sharing](https://ddeville.me/2013/08/debugging-icloud-URL-sharing/)
- [objc.io: Mastering the iCloud Document Store](https://www.objc.io/issues/10-syncing-data/icloud-document-store/)
- [fatbobman: Advanced iCloud Documents — Placeholder Files](https://fatbobman.com/en/posts/advanced-icloud-documents/)
- [fatbobman: In-Depth Guide to iCloud Documents](https://fatbobman.com/en/posts/in-depth-guide-to-icloud-documents/)
- [Eclectic Light: macOS Sonoma has changed iCloud Drive radically](https://eclecticlight.co/2023/10/25/macos-sonoma-has-changed-icloud-drive-radically/)
- [Eclectic Light: How iCloud Drive works in macOS Sonoma](https://eclecticlight.co/2024/03/18/how-icloud-drive-works-in-macos-sonoma/)
- [Eclectic Light: xattr com.apple.icloud.itemName](https://eclecticlight.co/2018/01/30/xattr-com-apple-icloud-itemname-icloud-drive-placeholder-filename/)
- [Michael Tsai: Getting Ready for Dataless Files](https://mjtsai.com/blog/2023/05/11/getting-ready-for-dataless-files/)
- [Michael Tsai: iCloud Drive Switches to Dataless Files](https://mjtsai.com/blog/2023/10/27/icloud-drive-switches-to-dataless-files/)
