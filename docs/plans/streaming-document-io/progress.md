# Progress Log

## Session: 2026-01-27

### Phase 5: Refinement & Tech Debt Cleanup
- **Status:** in_progress
- **Started:** 2026-01-27
- Actions taken:
  - Reviewed plan and added eight refinement mini-tasks.
  - Updated example upload/download progress handling to switch on
    ICloudTransferProgressType.
  - Normalized example progress/error state handling to use nulls.
  - Ran dart format and analyzer on updated example files.
  - Mapped delete coordination errors to E_FNF for TOCTOU consistency.
  - Documented download read-path authority and progress caveats in findings.
  - Added 10% kickoff progress events with monotonic clamping (upload/download).
  - Noted upload progress query behavior and optional UI timeouts in findings.
  - Captured trailing slash normalization mismatch and follow-up task in plan.
  - Updated Dart validation to accept trailing slashes and removed native trims.
  - Documented 64KB streamCopy buffer scope and rationale in findings.
  - Added gather() return-type findings and follow-up tasks to the plan.
  - Reduced per-entry gather() log noise and documented invalidEntries usage.
  - Updated CHANGELOG for trailing slash validation behavior.
  - Removed custom buffering in favor of listener-driven progress streams.
  - Updated progress stream tests and README/CHANGELOG to match new behavior.
  - Clarified `documentExists` placeholder behavior in README and download flow.
  - Added placeholder clarification to CHANGELOG.
  - Documented E_PLUGIN_INTERNAL guidance in README.
  - Updated README migration/version headers, gather examples, and path notes.
  - Added README clarifications to CHANGELOG.
  - Fixed macOS write save operation to use .saveOperation for existing files.
  - Refactored transfer progress stream mapping to a StreamTransformer
    (no manual controller/subscription lifecycle) and confirmed tests pass.
  - Restored context-aware relative path validation: directory paths may end
    with `/`, but transfer APIs (`uploadFile`/`downloadFile`) now reject
    trailing slashes to avoid UIDocument/NSDocument ambiguity.
  - Ran flutter test for method channel streams.
  - Mapped NSURL download status constants and added coverage in tests.
- Files created/modified:
  - docs/plans/streaming-document-io/task_plan.md
  - docs/plans/streaming-document-io/findings.md
  - lib/icloud_storage.dart
  - test/icloud_storage_test.dart
  - example/lib/upload.dart
  - example/lib/download.dart
  - ios/Classes/iOSICloudStoragePlugin.swift
  - macos/Classes/macOSICloudStoragePlugin.swift

## Session: 2026-01-24

### Phase 1: Requirements & Discovery
- **Status:** in_progress
- **Started:** 2026-01-24 00:00
- Actions taken:
  - Created new plan directory and initialized planning files.
  - Captured requirement that Dart API can change to support streaming.
  - Captured requirement to remove convenience APIs and go streaming-only.
  - Captured Apple’s tiered document API model in findings.
  - Reworked Dart API to file-path-only and updated tests.
  - Reworked iOS/macOS document layers for streaming read/write.
  - Updated native method channel handlers for uploadFile/downloadFile.
  - Captured access/visibility and security-scoped considerations in findings.
  - Updated README to align with sync/visibility and coordination rules.
  - Fixed gather(onUpdate) observers to keep update notifications alive.
  - Aligned delete argument key with relativePath in native handlers/tests.
  - Removed download metadata timers and made document reads authoritative.
  - Limited NSMetadataQuery to download progress only.
  - Kept upload progress query open on empty results to avoid premature close.
  - Added file-not-found error variants and documented download flow.
  - Buffered early progress events and logged unknown download status keys.
  - Replaced metadata query timeouts with coordinated FileManager operations.
  - Documented filesystem-based existence checks and removed E_TIMEOUT.
  - gather() now returns GatherResult with invalid entries.
  - Added transfer progress stream tests for numeric, error, and done events.
  - Renamed example progress listener field for clarity.
  - Ran dart format and flutter test.
- Files created/modified:
  - docs/plans/streaming-document-io/task_plan.md
  - docs/plans/streaming-document-io/findings.md
  - docs/plans/streaming-document-io/progress.md
  - docs/plans/.active-plan
  - lib/icloud_storage.dart
  - lib/icloud_storage_platform_interface.dart
  - lib/icloud_storage_method_channel.dart
  - ios/Classes/ICloudDocument.swift
  - macos/Classes/ICloudDocument.swift
  - ios/Classes/iOSICloudStoragePlugin.swift
  - macos/Classes/macOSICloudStoragePlugin.swift
  - lib/models/exceptions.dart
  - docs/download-flow.md
  - test/icloud_storage_method_channel_test.dart
  - test/icloud_storage_test.dart
  - example/lib/upload.dart
  - example/lib/download.dart
  - CHANGELOG.md
  - README.md

### Phase 2: Planning & Structure
- **Status:** pending
- Actions taken:
  -
- Files created/modified:
  -

## Test Results
| Test | Input | Expected | Actual | Status |
|------|-------|----------|--------|--------|
| flutter test | default | pass | pass | ✓ |
| flutter test | test/icloud_storage_method_channel_test.dart | pass | pass | ✓ |

## Error Log
| Timestamp | Error | Attempt | Resolution |
|-----------|-------|---------|------------|
| 2026-01-27 | Ran `dart format` on README/CHANGELOG and got parse errors (non-Dart). | 1 | Avoid formatting markdown with dart format. |
| 2026-01-27 | Progress stream tests failed after simplification (missing done/error events). | 1 | Added minimal controller to emit done/error events; tests pass. |

## 5-Question Reboot Check
| Question | Answer |
|----------|--------|
| Where am I? | Phase 5 |
| Where am I going? | Phase 6 |
| What's the goal? | Streamed document IO for uploads |
| What have I learned? | See findings.md |
| What have I done? | See session logs above |
