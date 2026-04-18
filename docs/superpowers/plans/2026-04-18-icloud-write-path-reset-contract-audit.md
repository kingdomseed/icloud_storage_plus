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

## Locked Write Outcomes

| State | Native behavior target | Dart-visible category/code | Retryable | Contract note |
|---|---|---|---|---|
| Destination missing | Overwrite path reports `handled == false`; existing entrypoint falls back to its current create-or-not-found behavior | No new overwrite-only category | Existing behavior | Part 1 keeps the current entrypoint contract instead of inventing a new overwrite error |
| Destination path resolves to an existing directory | Preserve the stable invalid-argument outcome | `invalidArgument` / `E_ARG` | No | This may use a minimal validation seam or a mapped OS failure; the dedicated helper is not locked |
| Destination is a ubiquitous item that is not locally current | Attempt download and wait for localization before overwrite | No error if recovery succeeds | N/A | `downloadInProgress` becomes a transient internal state, not a final write result |
| Destination download stalls | Surface stable timeout | `timeout` / `E_TIMEOUT` | Yes | Keep the idle-timeout contract |
| Destination download cannot become current | Surface stable not-downloaded failure | `itemNotDownloaded` / `E_NOT_DOWNLOADED` | Yes | Keep the typed split between timeout and not-downloaded |
| Destination has conflicts and recovery succeeds | Recover, then continue overwrite | No error if recovery succeeds | N/A | Recovery is allowed to be explicit write-path cleanup, not observer winner-selection |
| Conflict recovery fails before replacement write | Surface stable conflict failure | `conflict` / `E_CONFLICT` | No | Include underlying native details |
| Replacement write succeeds but post-write cleanup fails | The user's replacement remains the conceptual winner, but the operation still reports failure because cleanup is part of honest success | `conflict` / `E_CONFLICT` | No | Do not roll back to old-content-wins semantics or silently report success |
| Coordination fails | Surface stable coordination failure | `coordination` / `E_COORDINATION` | No by default | Revisit retryability only if an existing stable mapping proves otherwise |
| Unknown native write failure | Preserve structured fallback | `unknownNative` / `E_NAT` | No | Fallback only |

## Locked Behavioral Decisions

- `writeInPlace` and `writeInPlaceBytes` stay public API names.
- The overwrite sequence is: detect existing destination, localize if needed,
  write replacement, then run post-write conflict cleanup.
- Post-write cleanup is part of honest success. A cleanup failure is visible to
  Dart even if the replacement already won.
- The write path does not reuse observer winner-selection semantics.
- The reset keeps the current destination-missing behavior per entrypoint.
- The reset keeps the current typed download failure split:
  `E_NOT_DOWNLOADED` versus `E_TIMEOUT`.
- The reset drops write-path-specific `E_DOWNLOAD_IN_PROGRESS` as a terminal
  contract outcome.

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

- Mirror the iOS decisions exactly. Contract divergence is not allowed.

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

- Mirror the iOS decisions exactly. Contract divergence is not allowed.

### Conflict Helper Extraction Decision

- Part 2 should introduce `ConflictResolver.swift` on iOS and macOS by
  extracting the observer-only winner-selection logic that currently lives in
  `ICloudDocument.resolveConflicts()`.
- The extracted observer helper should be kept as an observer-specific
  resolver, not reused as the write-path winner-selection model.
- The write path should get a separate cleanup helper that marks conflicts
  resolved and removes other versions without restoring an older winner.

### `ios/.../icloud_storage_plus_foundation/ConflictResolver.swift`

- `resolvePresentedItemConflictsSync(at:)`: Keep as the observer-specific
  winner-selection helper extracted from `ICloudDocument.resolveConflicts()`.
- `resolvePresentedItemConflicts(at:)`: Keep as the async wrapper only if
  observer call sites still need an async surface after extraction; otherwise
  merge into the sync helper's call sites.
- `cleanupConflictsAfterOverwrite(at:)`: Keep as a write-path-specific cleanup
  helper that marks conflicts resolved and removes other versions without
  restoring an older winner.
- Any attempt to reuse observer winner-selection for save-path cleanup:
  Delete.

### `macos/.../icloud_storage_plus_foundation/ConflictResolver.swift`

- Mirror the iOS decisions exactly. Contract divergence is not allowed.

## Scope Guard

- This audit is doc-only and does not authorize Swift or Dart implementation
  edits.
- Part 2 may touch only the write-path files already named in the approved
  reset design unless a new design decision explicitly expands scope.
