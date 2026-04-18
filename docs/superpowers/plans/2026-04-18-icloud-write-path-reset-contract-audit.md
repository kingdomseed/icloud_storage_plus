# iCloud Write Path Contract Audit

Date: 2026-04-18
Scope: Part 1 contract lock for the reset worktree

## Baseline Notes

- This worktree does not contain a standalone `ConflictResolver.swift` on iOS
  or macOS.
- Observer conflict winner-selection currently lives in the platform
  `ICloudDocument.resolveConflicts()` implementations.
- The current plugin already maps `E_CONFLICT`, `E_NOT_DOWNLOADED`, `E_ARG`,
  `E_TIMEOUT`, and `E_NAT` at the Dart boundary.
- The current write path also exposes a write-path-specific
  `E_DOWNLOAD_IN_PROGRESS` native branch. Part 1 does not keep that branch as a
  terminal write outcome.

## Part 1 Lock Summary

The normative contract remains in
`docs/superpowers/specs/2026-04-18-icloud-write-path-reset-design.md`.

This audit records the Part 1 locks that implementation must preserve:

- public write API names stay stable where truthful
- destination-missing behavior stays tied to the existing entrypoint contract
- `invalidArgument` / `E_ARG` remains the locked directory-destination outcome
- `itemNotDownloaded` / `E_NOT_DOWNLOADED` and `timeout` / `E_TIMEOUT`
  remain the locked download failure split
- post-write cleanup remains part of honest success, so cleanup failure stays
  visible instead of silently succeeding
- save-path conflict handling stays separate from observer winner-selection
- `E_DOWNLOAD_IN_PROGRESS` does not survive as a terminal write-path outcome

## Method Inventory

### `ios/.../icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift`

- `overwriteExistingItem(at:prepareReplacementFile:)`: Keep, but simplify
  around the locked overwrite sequence and post-write cleanup ordering.
- `fileDestinationError(isDirectory:)`: Merge into the smallest honest
  invalid-argument seam that preserves `E_ARG`.
- `replaceReadyStateError(...)`: Simplify so it only models locked write-path
  outcomes; remove the terminal `downloadInProgress` branch and stop treating
  recoverable conflicts as a preflight refusal.
- `verifyExistingDestinationCanBeReplaced(at:)`: Merge away from the overwrite
  path. If copy-path behavior still needs a broader readiness check, keep that
  logic in a copy-specific seam instead of the overwrite contract.
- `verifyFileDestinationCanBeOverwritten(at:)`: Simplify to the minimum
  directory-validation seam, or delete if mapped OS failure can honestly keep
  `E_ARG`.
- `live`: Keep, but simplify to a direct coordinator bridge plus replacement
  staging and cleanup wiring.

### `macos/.../icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift`

- `overwriteExistingItem(at:prepareReplacementFile:)`: Keep, but simplify
  around the locked overwrite sequence and post-write cleanup ordering.
- `fileDestinationError(isDirectory:)`: Merge into the smallest honest
  invalid-argument seam that preserves `E_ARG`.
- `replaceReadyStateError(...)`: Simplify so it only models locked write-path
  outcomes; remove the terminal `downloadInProgress` branch and stop treating
  recoverable conflicts as a preflight refusal.
- `verifyExistingDestinationCanBeReplaced(at:)`: Merge away from the overwrite
  path. If copy-path behavior still needs a broader readiness check, keep that
  logic in a copy-specific seam instead of the overwrite contract.
- `verifyFileDestinationCanBeOverwritten(at:)`: Simplify to the minimum
  directory-validation seam, or delete if mapped OS failure can honestly keep
  `E_ARG`.
- `live`: Keep, but simplify to a direct coordinator bridge plus replacement
  staging and cleanup wiring.

### `ios/.../icloud_storage_plus/iOSICloudStoragePlugin.swift`

- `writeInPlace(_:_: )`: Keep. Simplify only enough to preserve the current
  destination-missing behavior and route overwrite failures through the locked
  categories.
- `writeInPlaceBytes(_:_: )`: Keep with the same contract as `writeInPlace`.
- `mapFileNotFoundError(...)`: Keep to preserve the current write/read
  not-found split.
- `nativeCodeError(...)`: Keep, but simplify to the locked write outcomes.
  Remove the write-path-specific `E_DOWNLOAD_IN_PROGRESS` mapping when the
  writer stops emitting it.
- `timeoutNativeError()`: Keep.
- `mapTimeoutError(...)`: Keep.
- `flutterError(...)`: Keep as the shared Flutter error envelope.

### `macos/.../icloud_storage_plus/macOSICloudStoragePlugin.swift`

- `writeInPlace(_:_: )`: Keep. Simplify only enough to preserve the current
  destination-missing behavior and route overwrite failures through the locked
  categories.
- `writeInPlaceBytes(_:_: )`: Keep with the same contract as `writeInPlace`.
- `mapFileNotFoundError(...)`: Keep to preserve the current write/read
  not-found split.
- `nativeCodeError(...)`: Keep, but simplify to the locked write outcomes.
  Remove the write-path-specific `E_DOWNLOAD_IN_PROGRESS` mapping when the
  writer stops emitting it.
- `timeoutNativeError()`: Keep.
- `mapTimeoutError(...)`: Keep.
- `flutterError(...)`: Keep as the shared Flutter error envelope.

### Observer Conflict Extraction Scope

- Part 2 should extract the observer-only conflict work that currently lives
  inside `ICloudDocument.resolveConflicts()` into a dedicated foundation seam.
- The extracted observer seam should remain observer-specific and should not
  become the save-path winner-selection model.
- The write path should use a separate cleanup seam whose job is cleanup, not
  selecting an older winner.

### `ios observer conflict extraction scope`

- current observer winner-selection logic in `ICloudDocument.resolveConflicts()`:
  Extract and Keep as an observer-only foundation helper
- any separate async wrapper around observer conflict resolution:
  Merge unless surviving observer call sites require it
- write-path post-overwrite conflict cleanup seam:
  Add and Keep as a cleanup-only helper
- any save-path helper that restores an older conflict version as the winner:
  Delete

### `macos observer conflict extraction scope`

- current observer winner-selection logic in `ICloudDocument.resolveConflicts()`:
  Extract and Keep as an observer-only foundation helper
- any separate async wrapper around observer conflict resolution:
  Merge unless surviving observer call sites require it
- write-path post-overwrite conflict cleanup seam:
  Add and Keep as a cleanup-only helper
- any save-path helper that restores an older conflict version as the winner:
  Delete

## Scope Guard

- This audit is doc-only and does not authorize Swift or Dart implementation
  edits.
- Part 2 may touch only the write-path files already named in the approved
  reset design unless a new design decision explicitly expands scope.
