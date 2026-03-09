# Task Plan: Add `listContents` API using FileManager.contentsOfDirectory

## Goal
Add a new `listContents` method to the icloud_storage_plus plugin that uses
`FileManager.contentsOfDirectory(at:includingPropertiesForKeys:options:)` with
ubiquitous URL resource keys to list files in the ubiquity container with
download status. This provides immediately-consistent file listings after local
mutations (rename, delete, copy), fixing a race condition where `gather()`
returns stale results because the Spotlight metadata index hasn't converged.

**Origin bug:** Mythic GME 2e — rename a journal in iCloud mode, `gather()`
still shows old filename, UI does not update, second rename fails.

## Current Phase
Phase 1

## Phases

### Phase 1: API Design
- [x] Read iOS + macOS Swift source to confirm gather() uses NSMetadataQuery
- [x] Read Dart platform interface, method channel, and public API
- [x] Capture root cause analysis in findings.md
- [x] Research proper placeholder detection via URL resource values
- [x] Research iCloud Drive vs iCloud Sync architecture
- [x] Discover that FileManager CAN provide download status via resource keys
- [ ] Finalize Dart return type and model design
- [ ] Design method signature across all layers
- [ ] Document final API design decisions
- **Status:** in_progress

### Phase 2: Swift Implementation (both platforms)
- [ ] Implement `listContents` in macOS Swift plugin
- [ ] Implement `listContents` in iOS Swift plugin
- [ ] Use URL resource values for download status detection
- [ ] Handle `.icloud` placeholder filename resolution (iOS + pre-Sonoma macOS)
- [ ] Filter out directories (use `.isRegularFileKey`)
- [ ] Run on background queue (AGENTS.md rule 6)
- [ ] Wire into method channel `handle()` switch
- **Status:** pending

### Phase 3: Dart Layer
- [ ] Create `ContainerItem` model (or equivalent)
- [ ] Add `listContents` to `ICloudStoragePlatform` (platform interface)
- [ ] Add `listContents` to `MethodChannelICloudStorage` (method channel impl)
- [ ] Add `listContents` to `ICloudStorage` (public API)
- [ ] Add input validation (containerId, optional relativePath)
- **Status:** pending

### Phase 4: Tests
- [ ] Unit test Dart method channel layer
- [ ] Verify `flutter analyze` passes
- [ ] Verify `flutter test` passes
- **Status:** pending

### Phase 5: Documentation & PR
- [ ] Update CHANGELOG.md
- [ ] Update README if needed
- [ ] Create PR with clear description
- **Status:** pending

## Design Considerations (Active Discussion)

### iCloud Drive vs iCloud Sync — Do we even need gather()?

**Key insight from user:** If files are in iCloud Drive (the `Documents/`
subdirectory visible in Files app), they appear as real filesystem entries
(or placeholders). The original iCloud Sync put files in a hidden container
invisible to the user. iCloud Drive made them first-class filesystem citizens.

**Research conclusion:** `FileManager.contentsOfDirectory` + URL resource
values provides:
- File listing (immediately consistent after mutations)
- Download status per file (`.notDownloaded`, `.downloaded`, `.current`)
- Upload status, conflict detection
- File size (real size on macOS Sonoma+; stub size on older platforms)

`gather()` / NSMetadataQuery is still needed ONLY for:
- **Document promises** — files known to iCloud server but not yet
  placeholder'd on this device (brief window during remote sync)
- **Download/upload progress percentage** — only available via
  `NSMetadataUbiquitousItemPercentDownloadedKey`
- **Real-time remote change notifications** — `NSMetadataQueryDidUpdate`
- **Real file size of un-downloaded files** (pre-Sonoma only)

**For Mythic GME's use case** (journals the user is actively working with,
all in `Documents/`, already downloaded), `listContents` with resource values
may be sufficient for ALL post-mutation operations. `gather()` remains useful
only for initial device sync and remote change monitoring.

### Return type: `List<String>` vs lightweight model

**Original plan:** `List<String>` of relative paths.

**Revised after research:** Since FileManager CAN provide download status via
`ubiquitousItemDownloadingStatusKey`, returning a model with `relativePath` +
`downloadStatus` is both honest and useful. This lets the consumer distinguish
real files from placeholders without a separate `gather()` call.

**Proposed model:**
```dart
class ContainerItem {
  final String relativePath;
  final bool isDownloaded;  // true if .downloaded or .current
  final bool isDirectory;
}
```

**Open question:** Should this be richer? We CAN also include:
- `isUploaded` (bool)
- `isDownloading` (bool) — actively downloading right now
- `hasUnresolvedConflicts` (bool)

These are all available from URL resource values. The trade-off is API surface
area vs usefulness.

### Placeholder filename resolution

Two mechanisms depending on platform:
- **iOS / pre-Sonoma macOS:** `.originalName.icloud` on disk → must strip
  leading dot + trailing `.icloud` to recover real name
- **macOS Sonoma+:** APFS dataless files keep real filename. No stripping needed.

Detection should use `ubiquitousItemDownloadingStatusKey`, not filename patterns.
Filename stripping is a fallback for recovering the real name on older platforms.

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Use URL resource values for download status | Proper Apple API. Works on both placeholder stubs and APFS dataless files. No string hacking for detection. |
| Strip `.icloud` placeholder names in Swift (iOS) | On-disk names are mangled on iOS. Resource values detect the status; stripping recovers the real name. |
| Do NOT use `.skipsHiddenFiles` option | Placeholder files have a leading dot — would be filtered out. |
| Accept optional `relativePath` parameter | Consumer needs to list `Documents/` specifically. |
| Filter out directories by default | Primary use case is file listings. |
| Complement gather(), don't replace it | Document promises and download progress still require NSMetadataQuery. But for post-mutation consistency, listContents is the correct tool. |

## Key Questions (Pending User Input)
1. How rich should the return model be? Minimal (`relativePath` + `isDownloaded`)
   vs richer (add `isUploaded`, `isDownloading`, `hasConflicts`)?
2. Should the method name be `listContents` or something more descriptive like
   `enumerateFiles`?

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
|       | 1       |            |
