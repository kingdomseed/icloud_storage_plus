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
