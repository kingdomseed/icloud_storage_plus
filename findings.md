# Findings

## Research Notes

- Native Apple code lives under `ios/icloud_storage_plus/Sources/...` and
  mirrored `macos/...`, with a shared-looking `icloud_storage_plus_foundation`
  SwiftPM target containing the new `CoordinatedReplaceWriter` tests.
- Branch commits are tightly scoped to coordinated overwrite/copy replacement
  and preflight readiness checks.
- `CoordinatedReplaceWriter` is a small injectable helper that:
  uses `FileManager.fileExists(atPath:)`, preflights destination state,
  creates an item replacement directory, coordinates a `.forReplacing` write,
  calls `replaceItemAt`, and cleans up replacement artifacts on success/failure.
- Preflight explicitly blocks replacement when unresolved `NSFileVersion`
  conflicts exist or when a ubiquitous item is not fully downloaded.
- Existing `ICloudDocument` still auto-resolves conflicts by selecting the most
  recent version, while the new replacement helper refuses to replace when
  unresolved conflicts exist. That split suggests inconsistent conflict policy.
- Tests cover the helper's happy path, non-existent destination short-circuit,
  conflict/not-downloaded preflight failures, and cleanup on replacement error.
- iOS and macOS write paths now first try `CoordinatedReplaceWriter` for
  existing destinations and only fall back to `UIDocument`/`NSDocument` create
  flows when the destination is missing.
- Copy replacement is safer than before for existing destinations, but the
  non-existing-destination path still uses a simpler coordinated copy that
  manually removes any existing file before `copyItem`.
- The plugin still collapses most native errors into generic Flutter
  `E_NAT` errors, so the new preflight distinctions are not strongly surfaced
  across the Dart boundary yet.
- macOS explicitly dispatches document reads/writes off the main thread;
  iOS relies on Flutter's background task queue for method calls but
  `UIDocument` callbacks still deserve careful threading review.
- Placeholder/download handling is reasonably mature outside the overwrite path:
  the plugin already starts ubiquitous downloads, waits for `.current` with an
  idle-progress watchdog, exposes download/upload/conflict metadata, and keeps
  placeholders visible in `listContents()` by resolving `.icloud` names instead
  of filtering hidden files blindly.
- The repo includes a maintained branch plan noting broader verification
  expectations: helper unit tests, Flutter tests/analyze, and platform builds,
  plus explicit manual iCloud validation as remaining work.
- Fresh local evidence from this review session: `swift test` passed in both
  `ios/.../icloud_storage_plus_foundation` and
  `macos/.../icloud_storage_plus_foundation` (5 helper tests each, 0 failures).
- User approved a breaking-cleanup direction for the next slice rather than a
  deprecated compatibility wrapper.
- The written spec chooses these contract boundaries:
  - `ICloudFile` stays the discovery model for `gather()`
  - a new `ICloudItemMetadata` model becomes the typed known-path metadata model
  - `getMetadata(...) -> ICloudFile?` is removed as ambiguous API debt
  - `getItemMetadata(...) -> ICloudItemMetadata?` becomes the replacement typed
    API
  - `getDocumentMetadata(...)` remains the raw map escape hatch
- The written spec also locks the normalized caller-visible download-status
  vocabulary to `notDownloaded`, `downloaded`, and `current`, and it treats raw
  Apple status strings as implementation-only migration details rather than part
  of the intended public contract.
- Planned Dart exception categories in the spec are explicit and branchable:
  not-found, container unavailable, conflict, not-downloaded,
  download-in-progress, invalid-path, coordination, permission, and unknown
  native fallback.
- External review of the written spec found 5 material issues to resolve before
  implementation planning:
  - The spec currently promises typed conflict/download exceptions while also
    preserving document flows that still auto-download and auto-resolve some of
    those states. That makes the caller contract internally inconsistent unless
    the affected API surfaces are scoped more precisely.
  - The typed-exception design does not yet define the transport-layer plan.
    Today most native failures still collapse into broad `E_NAT` channel errors,
    so stable Dart-side exception categories require new structured native error
    codes/details rather than string matching on generic native failures.
  - The spec is ambiguous about whether `getDocumentMetadata()` remains truly
    raw. Keeping it raw conflicts with the current wording that all
    caller-visible download-status values are normalized before reaching Dart.
  - The spec does not yet account for transfer progress stream errors, which are
    currently modeled around `PlatformException` in both the stream payload type
    and the documented contract.
  - The migration/testing section understates the repo-owned blast radius:
    README, changelog, example code, public tests, and model tests all assume
    the old `getMetadata()` / `ICloudFile` / `PlatformException` contract.
- Follow-up spec revisions resolved the external review findings. The final
  review reported no material contradictions.
- Final contract decisions locked into the spec:
  - `getItemMetadata()` is a non-throwing state-inspection API for
    conflict/download/locality state and returns `null` for not-found.
  - `getDocumentMetadata()` remains truly raw.
  - `details.category` is the sole authoritative Dart branching discriminator
    for native typed exceptions.
  - Transfer-progress stream errors remain `PlatformException`-based in this
    breaking release.
  - The package release for this cleanup must be semver-major (`2.0.0`).
- Residual non-blocking review risks:
  - current method-channel timeout transport truncates `Duration` values to
    whole seconds, so sub-second/zero/negative semantics should be documented or
    tested during implementation
  - some existing repo docs/comments still describe the pre-revision
    `getContainerPath()` and timeout contract and must be updated during the
    implementation slice
- PR `#23` review triage findings:
  - Documentation/process cleanup comments that are still open in the branch:
    duplicate `### Changed` heading in `CHANGELOG.md`, README grouping of query
    APIs under file management, and unchecked execution boxes in the shipped
    overwrite plan doc. These are now fixed locally in the worktree.
  - Substantive code comments that are still open in the branch:
    `CoordinatedReplaceWriter` does not explicitly reject directory destinations,
    and it still allows replacement when a ubiquitous item reports
    `downloadStatus == .downloaded`.
  - The bot suggestion to move the unresolved-conflict check after the
    `isUbiquitousItem` guard is not currently justified enough to implement.
- The cleaner resolution to those substantive comments is to separate
  file-overwrite semantics from copy semantics rather than keep growing one
  shared helper contract.
- That branch-local cleanup is now implemented:
  - `CoordinatedReplaceWriter` is file-overwrite-only.
  - Existing directory destinations are rejected for file writes.
  - Existing-destination `copy()` replacement moved into platform-specific
    plugin code so directory copy semantics stay intact.
  - Ubiquitous replacement readiness now requires `.current`; `.downloaded`
    is rejected as not yet replace-safe.
- Fresh verification after the cleanup:
  - iOS helper `swift test`: pass
  - macOS helper `swift test`: pass
  - root `flutter test`: pass
  - root `flutter analyze`: pass
  - example macOS `xcodebuild` with signing disabled: `BUILD SUCCEEDED`
  - example iOS simulator `xcodebuild` with signing disabled:
    `BUILD SUCCEEDED`
