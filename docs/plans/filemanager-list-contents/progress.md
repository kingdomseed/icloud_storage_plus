# Progress Log

## Session: 2026-03-09

### Phase 1: API Design
- **Status:** in_progress
- Actions taken:
  - Read all plugin source: iOS Swift, macOS Swift, Dart platform interface,
    method channel, public API, models, AGENTS.md
  - Confirmed iOS and macOS `gather()` are identical patterns: one-shot
    NSMetadataQuery with `NSMetadataItemPathKey beginswith containerURL.path`
  - Confirmed iOS and macOS `move()` are identical: NSFileCoordinator +
    FileManager.moveItem, completes synchronously on filesystem
  - Identified 14 existing method channel methods (both platforms)
  - Analyzed `ICloudFile` model — tightly coupled to NSMetadataQuery fields
  - Decided on `List<String>` return type instead of reusing ICloudFile
  - Captured root cause in findings.md (created in previous session)
  - Created task_plan.md with phased implementation plan
- Files created/modified:
  - docs/plans/filemanager-list-contents/task_plan.md (new)
  - docs/plans/filemanager-list-contents/progress.md (new)
  - docs/plans/filemanager-list-contents/findings.md (previous session)

### Key Findings (Early)
- Method channel routing: both platforms have identical 14-case switch
- `ICloudFile` fields (downloadStatus, isUploading, hasUnresolvedConflicts)
  come from NSMetadataQuery — cannot be populated by FileManager
- Plugin's AGENTS.md mandates: background queues, typed Dart exceptions,
  update both iOS and macOS, use FileManager.fileExists for existence checks

### Research: Placeholder Detection (Revised Understanding)
- **URL resource values work WITHOUT NSMetadataQuery**: FileManager
  `contentsOfDirectory(at:includingPropertiesForKeys:)` accepts ubiquitous
  keys like `.ubiquitousItemDownloadingStatusKey`
- This means FileManager CAN provide download status, upload status,
  and conflict detection per-file — not just filenames
- **Two eras of placeholders:**
  - iOS + pre-Sonoma macOS: `.originalName.icloud` stubs (~192 bytes)
  - macOS Sonoma+: APFS dataless files keep real names, real logical size
- Detection: use `ubiquitousItemDownloadingStatus`, not filename patterns
- Filename stripping still needed on iOS to recover real name from stub

### Research: iCloud Drive vs iCloud Sync
- iCloud Drive (Documents/) and container root use same sync mechanism
- Only difference: Documents/ is visible in Files app / Finder
- FileManager + resource values covers almost everything NSMetadataQuery does
- NSMetadataQuery still required ONLY for:
  - Document promises (remote files not yet placeholder'd locally)
  - Download/upload progress percentages
  - Real-time change notifications from remote devices
  - Real file size of un-downloaded files (pre-Sonoma)

### Design Evolution
- Original plan: `List<String>` (filenames only)
- Revised: Since FileManager CAN provide download status via resource values,
  return a lightweight model with relativePath + downloadStatus
- User raised key question: "Do you need gather at all for iCloud Drive?"
  Answer: For post-mutation consistency, no. For remote discovery and
  progress monitoring, yes.

### Implementation Complete
- Created `ContainerItem` model with full richness (downloadStatus,
  isDownloading, isUploaded, isUploading, hasUnresolvedConflicts, isDirectory)
- Added `listContents` to platform interface, method channel, and public API
- Implemented `listContents` in both macOS and iOS Swift plugins:
  - Uses FileManager.contentsOfDirectory with ubiquitous resource keys
  - Resolves `.icloud` placeholder filenames
  - Normalizes download status to clean enum strings
  - Runs on background queue per AGENTS.md rule 6
  - Returns container-root-relative paths for consistency with gather()
- Added 7 tests for listContents and ContainerItem
- Updated mock platform in test file

### Documentation & Release (1.2.0)
- Updated README.md:
  - Expanded "Choosing the right API" from 2 tiers to 4 tiers
  - Added "Immediate listing with listContents" section with usage example
  - Added "gather vs listContents" comparison table with guidance
  - Added "iCloud placeholder files" section explaining two eras
  - Replaced "Metadata: ICloudFile" with "Metadata models" section covering
    both ICloudFile and ContainerItem
  - Added troubleshooting note about gather staleness after mutations
- Updated CHANGELOG.md with 1.2.0 entry (Added + Changed)
- Bumped pubspec.yaml version to 1.2.0
- Enriched API doc comments (ContainerItem, ICloudFile, GatherResult,
  InvalidArgumentException typo fix)
- Added example app screen: `list_contents.dart` with menu entry
- All quality gates pass (85/85 tests, 0 analyzer issues, formatting clean)

## Test Results
| Test | Input | Expected | Actual | Status |
|------|-------|----------|--------|--------|
| Analyze | `flutter analyze` | No issues | No issues | PASS |
| Tests | `flutter test` | 85 pass | 85 pass | PASS |

## Error Log
| Timestamp | Error | Attempt | Resolution |
|-----------|-------|---------|------------|
| 2026-03-09 | Mock state leak between tests | 1 | Reset `listContentsResult` in setUp |
| 2026-03-09 | comment_references lint on `[ICloudStorage.listContents]` | 1 | Changed to backtick syntax |
