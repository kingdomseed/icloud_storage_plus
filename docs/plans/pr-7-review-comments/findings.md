# Findings & Decisions

## Requirements
- Pull all PR #7 comments (issue comments, review comments, review summaries)
  with full details.
- Address each comment one-by-one in a patch for this branch.

## Research Findings
- PR #7 metadata (gh pr view):
  - Title: "Release v3.0.0: Major Breaking Changes with Enhanced File
    Operations"
  - Author: @kingdomseed
  - State: OPEN
  - Created: 2026-01-23T20:32:21Z
  - Updated: 2026-01-23T20:39:03Z
- Issue comments API: none (`/issues/7/comments` returned empty array).
- Latest review summaries (from `latestReviews` / `reviews`):
  - Devin review summary: reports 2 potential issues and 6 additional flags.
  - Copilot review summary: generated 3 comments (details below).
  - Codex review summary: flags `readDocument` early guard that checks
    `FileManager.default.fileExists(atPath:)`, preventing auto-download for
    remote-only iCloud items (iOS).
- Inline review comments (from `gh api /pulls/7/comments`, 5 total):
  1) Devin (iOS) — `ios/Classes/iOSICloudStoragePlugin.swift` lines 350-351
     - Issue: `download()` calls `result(nativeCodeError(error))` but
       continues executing (no `return`), so query observers still set up
       after error.
     - Impact: duplicate result calls, resource leak, confusing behavior.
     - Recommendation: add `return` after invoking `result` in the catch.
  2) Devin (macOS) — `macos/Classes/macOSICloudStoragePlugin.swift` line 365
     - Issue: macOS `download()` never passes `result` to observer methods.
     - Impact: Flutter Future hangs forever, no success/failure returned.
     - Recommendation: pass `result` through `addDownloadObservers` and
       `onDownloadQueryNotification`, call `result(true)` or error.
  3) Copilot — `lib/icloud_storage.dart` line 146
     - Issue: typo "percentage ofthe" missing space (upload doc comment).
     - Recommendation: change to "percentage of the data being uploaded".
  4) Copilot — `lib/icloud_storage.dart` line 250
     - Issue: typo "percentage ofthe" missing space (download doc comment).
     - Recommendation: change to "percentage of the data being downloaded".
  5) Copilot — `CHANGELOG.md` line 263
     - Issue: `>=2.5.0` conflicts with Dart `>=2.18.2 <3.0.0`.
     - Recommendation: raise minimum Flutter version (suggests `>=3.3.4`) and
       update `pubspec.yaml` to match.

## Technical Decisions
| Decision | Rationale |
|----------|-----------|
| Use `gh pr view` for PR metadata and review summaries | Fast overview |
| Use `gh api` for review comments | `gh pr view` lacks reviewComments |

## Issues Encountered
| Issue | Resolution |
|-------|------------|
| `gh api` URL globbed by zsh when unquoted | Re-run with quoted URL |

## Resources
- PR #7 URL: https://github.com/kingdomseed/icloud_storage_plus/pull/7

## Visual/Browser Findings
- None yet (no browser views).

## Code Pointers
- iOS `download` method around `ios/Classes/iOSICloudStoragePlugin.swift:329`.
- macOS `download` method around `macos/Classes/macOSICloudStoragePlugin.swift:329`.
- Additional `startDownloadingUbiquitousItem` usage around lines ~446 (iOS) and
  ~442 (macOS) likely in other helpers (verify before changes).
- Verified iOS download method: catch block calls `result(nativeCodeError(error))`
  but does not return before starting NSMetadataQuery.
- Verified macOS download method: `addDownloadObservers` lacks `result`
  parameter and observer callback lacks access to Flutter result.
- Confirmed doc comment typos in `lib/icloud_storage.dart`:
  - upload: "percentage ofthe data being uploaded".
  - downloadAndRead: "percentage ofthe data being downloaded".
- CHANGELOG and `pubspec.yaml` both list minimum Flutter `>=2.5.0` while
  Dart SDK constraint is `>=2.18.2 <3.0.0` (needs alignment).
- iOS `readDocument` uses `FileManager.default.fileExists` guard that returns
  nil when file is remote-only; matches Codex review note.
- `readDocumentAt` is only called in `iOSICloudStoragePlugin.swift`; its
  definition appears to be elsewhere (likely `ICloudDocument.swift`).
- `readDocumentAt` (ios/Classes/ICloudDocument.swift) opens UIDocument directly
  and returns an error if open fails. It does not perform existence checks.
- iOS already has `queryMetadataItem` used by `documentExists` and
  `getDocumentMetadata`, which can detect remote-only items via NSMetadataQuery.
- `mapMetadataItem` determines directories via `fileURL.hasDirectoryPath`.
- macOS has a `readDocument` implementation; need to verify if it also
  guards with `fileExists`.
- macOS `readDocument` has the same `fileExists` guard as iOS, so remote-only
  files would also be blocked there.
- `readDocumentAt` exists in `macos/Classes/ICloudDocument.swift`.
- Flutter release metadata (official releases JSON): earliest stable with
  Dart >=2.18.2 is Flutter 3.3.3 (Dart 2.18.2) released 2022-09-28.
- macOS `onDownloadQueryNotification` currently only emits to stream handlers;
  it never calls the Flutter `result` callback and does not remove observers
  on error/completion.
- iOS `onDownloadQueryNotification` calls `result(false)` when no results and
  `result(true)` on completion; macOS should mirror this behavior.
- macOS also provides `queryMetadataItem`, so readDocument can use it to
  check remote-only existence before opening NSDocument.
- macOS download observer call sites updated to accept `result` (verified via
  search after edits).

## Resolutions
- Added `return` after `result(nativeCodeError(error))` in iOS and macOS
  `download()` methods to stop execution after errors.
- Wired macOS download observers to pass `result` and call it on completion,
  mirroring iOS behavior.
- Updated `readDocument` to use `queryMetadataItem` (iOS + macOS) so
  remote-only iCloud files can be read via UIDocument/NSDocument.
- Fixed doc comment typos in `lib/icloud_storage.dart` (upload/download).
- Updated minimum Flutter version to `>=3.3.3` in `pubspec.yaml` and
  `CHANGELOG.md` to align with Dart `>=2.18.2`.

## New Unresolved Review Comments (2026-01-23)
1) Devin — `lib/icloud_storage.dart` line ~59
   - Unused public constants: `visibilityPrivate`, `visibilityPublic`,
     `visibilityTemporary` are defined but unused. Suggest remove or wire into
     API to reduce surface area.
   - URL: https://github.com/kingdomseed/icloud_storage_plus/pull/7#discussion_r2722898230

2) Devin — `ios/Classes/iOSICloudStoragePlugin.swift` lines ~382-419
   - Potential multiple `result()` invocations because observers are registered
     for both gather and update; race window if multiple notifications fire.
   - Suggest guard to ensure result called once.
   - URL: https://github.com/kingdomseed/icloud_storage_plus/pull/7#discussion_r2722899404

3) Sentry — `macos/Classes/macOSICloudStoragePlugin.swift` lines ~387-390
   - Multiple `result()` invocations possible; observers not removed after
     first call.
   - Suggest remove observers or guard with flag after first result.
   - URL: https://github.com/kingdomseed/icloud_storage_plus/pull/7#discussion_r2722900064

4) Devin — `macos/Classes/macOSICloudStoragePlugin.swift` lines ~350-351
   - Missing `return` after error in startDownloadingUbiquitousItem.
   - Note: already addressed in code, but thread remains unresolved.
   - URL: https://github.com/kingdomseed/icloud_storage_plus/pull/7#discussion_r2722902927

5) Devin — `lib/icloud_storage.dart` lines ~774-781
   - `utf8.encode` returns `List<int>` but runtime is `Uint8List`.
   - Comment says this is not a bug; informational.
   - URL: https://github.com/kingdomseed/icloud_storage_plus/pull/7#discussion_r2722904022

6) Devin — `ios/Classes/iOSICloudStoragePlugin.swift` lines ~840-844
   - removeObservers uses `removeObserver(self, ...)` but observers were added
     via closure API and should be removed by token.
   - Applies to iOS + macOS; use stored tokens or selector-based observers.
   - URL: https://github.com/kingdomseed/icloud_storage_plus/pull/7#discussion_r2722904804

7) Devin — `ios/Classes/iOSICloudStoragePlugin.swift` lines ~382-420
   - `download()` can invoke `result()` multiple times because query is not
     stopped/observers not removed after result.
   - Suggest single-shot cleanup and mirror on macOS.
   - URL: https://github.com/kingdomseed/icloud_storage_plus/pull/7#discussion_r2722904830

8) Copilot — `README.md` line ~512
   - `upload` example lists `destinationRelativePath` as required, but API
     allows it to be optional. Update example.
   - URL: https://github.com/kingdomseed/icloud_storage_plus/pull/7#discussion_r2722905923

## Resolutions (New Comment Batch)
- Implemented token-based observer tracking and cleanup for NSMetadataQuery
  observers (iOS + macOS).
- Made download and downloadAndRead single-shot by stopping queries and
  removing observers after returning a result.
- Cleaned up upload progress queries after completion or error.
- Removed unused visibility constants from public API.
- Made writeJsonDocument encode into Uint8List explicitly.
- Updated README upload signature to show optional destinationRelativePath.

## Decisions (Dart 3 + Equatable)
- Added `equatable` dependency and implemented value equality for `ICloudFile`.
- Updated delete/move native implementations to use metadata queries for
  remote-only items before coordinating operations (iOS + macOS).
- Flutter min updated to >=3.10.0 to match Dart 3.0 baseline (earliest stable
  Flutter with Dart 3.0.0 per releases metadata).

## Resolutions (Copy Remote-Only)
- Updated iOS/macOS copy() to resolve source via metadata query before
  coordinated copy, avoiding local-only fileExists checks for remote items.
