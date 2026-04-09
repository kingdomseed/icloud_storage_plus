# iCloud API Hardening Design

Date: 2026-04-09
Status: Proposed
Branch: `fix/coordinated-overwrite-darwin`

## Summary

This slice hardens the plugin's public Apple-facing contract by fixing four
related problems together:

1. broad native failures are flattened into generic Dart errors
2. typed metadata for a known path is modeled as `ICloudFile`, which actually
   represents metadata-query discovery state rather than known-URL state
3. download status values are normalized inconsistently across discovery,
   listing, and known-path metadata APIs
4. iCloud document paths are too easy to reason about as ordinary local
   filesystem paths instead of stateful, coordinated ubiquity items

The design intentionally follows Apple iCloud document constraints rather than
ordinary filesystem assumptions. It keeps discovery and known-path metadata as
different concepts, normalizes caller-visible state, and replaces ambiguous
typed APIs instead of leaving deprecated compatibility debt behind.

## Goals

- Make typed errors stable and actionable for Dart callers.
- Separate discovery metadata from known-path metadata in the public Dart API.
- Normalize download-status values before they cross the method channel.
- Preserve Apple-aligned native behavior for iOS and macOS.
- Remove the ambiguous typed metadata contract instead of preserving it as a
  deprecated wrapper.

## Non-Goals

- Change the core `UIDocument` / `NSDocument` document read-write model.
- Replace `NSMetadataQuery` discovery with raw filesystem enumeration.
- Eliminate the raw `getDocumentMetadata()` map escape hatch in this slice.
- Solve manual real-device iCloud validation inside this design slice.
- Change transfer-progress stream payloads away from their current
  `PlatformException`-based error model.

## Current Problems

### 1. Metadata semantics are mixed together

`gather()` returns `ICloudFile`, which is appropriate because it is backed by
`NSMetadataQuery` discovery state. The current typed `getMetadata()` API also
returns `ICloudFile`, even though it is backed by known-URL resource values via
`getDocumentMetadata()`. Those are not the same native truth surface.

### 2. Download status is not a stable public contract

Current APIs expose a mix of raw Apple strings and normalized values depending
on which native code path produced the result. That makes callers branch on
transport details instead of plugin semantics.

### 3. Error handling is too broad

Expected iCloud conditions such as conflict state, placeholder/nonlocal state,
and coordination failures are frequently surfaced as generic native errors.
Callers cannot reliably distinguish retryable, invalid-input, and stateful
iCloud failures.

### 4. iCloud is not an ordinary local filesystem

Path existence, simple reads, and uncoordinated writes are not enough to model
correct iCloud behavior. Placeholder and version/conflict state must be treated
as first-class conditions.

## Design

### Public Models

The plugin should expose three distinct typed models with explicit meanings:

- `ICloudFile`
  - discovery state from `NSMetadataQuery`
  - used by `gather()` only
- `ICloudItemMetadata`
  - known-path metadata derived from `URLResourceValues`
  - used by the typed known-path metadata API
- `ContainerItem`
  - immediate directory listing entry
  - used by listing APIs only

This keeps native truth surfaces visible instead of flattening them into one
ambiguous type.

#### `ICloudItemMetadata` Fields

`ICloudItemMetadata` should be a concrete Dart model with these fields:

- `relativePath`: `String`
- `isDirectory`: `bool`
- `sizeInBytes`: `int?`
- `creationDate`: `DateTime?`
- `contentChangeDate`: `DateTime?`
- `downloadStatus`: `DownloadStatus?`
- `isDownloading`: `bool`
- `isUploading`: `bool`
- `isUploaded`: `bool`
- `hasUnresolvedConflicts`: `bool`

Derived convenience:

- `isLocal`: `bool`
  - true when `downloadStatus` is `DownloadStatus.downloaded` or
    `DownloadStatus.current`

This intentionally mirrors the immediately-available known-path state already
surfaced by native metadata and keeps conflict/download/locality information
in-band for inspection callers.

### Public API Changes

This slice allows a breaking cleanup.

- Remove the ambiguous typed `getMetadata(...) -> ICloudFile?` contract.
- Add `getItemMetadata(...) -> ICloudItemMetadata?` as the correct typed
  known-path metadata API.
- Keep `getDocumentMetadata(...) -> Map<String, dynamic>?` as the explicit raw
  native-map escape hatch.
- Keep `gather()` returning `ICloudFile`.
- Keep listing APIs returning `ContainerItem`.

The typed metadata API is corrected in place rather than preserved behind a
deprecated wrapper, because preserving the wrapper would deliberately leave the
main semantic debt in the public surface.

`getDocumentMetadata(...)` remains truly raw. It is not the semantic contract
for normalized caller-facing metadata, and it should not be partially normalized
in ways that blur its purpose as the low-level escape hatch.

`getItemMetadata(...)` is an inspection API. It should report conflict and
download/locality state in-band on the returned `ICloudItemMetadata` model
rather than throwing typed state exceptions for those conditions.

### Status Normalization

All typed, caller-facing semantic metadata APIs should normalize Apple
download-status values before they reach Dart.

Normalized values:

- `notDownloaded`
- `downloaded`
- `current`

Rules:

- `gather()` results normalize raw metadata-query status strings into the shared
  status vocabulary.
- known-path metadata normalizes `URLResourceValues.ubiquitousItemDownloadingStatus`
  into the same vocabulary.
- directory listing metadata uses the same vocabulary.
- Dart treats the normalized vocabulary as the primary contract.
- Raw Apple status strings may be tolerated only inside short-lived private
  migration adapters during implementation. They are not part of the intended
  post-slice contract.
- `getDocumentMetadata(...)` is excluded from this normalization guarantee
  because it remains the explicit raw-map escape hatch.

### Typed Errors

Expected iCloud states become typed Dart exceptions rather than generic native
failures.

Planned Dart exception categories:

- `ICloudItemNotFoundException`
- `ICloudContainerAccessException`
- `ICloudConflictException`
- `ICloudItemNotDownloadedException`
- `ICloudDownloadInProgressException`
- `ICloudTimeoutException`
- `ICloudCoordinationException`
- `ICloudUnknownNativeException`

Notes:

- `InvalidArgumentException` remains the Dart-side pre-channel validation error
  for invalid relative paths and similar caller mistakes.
- This slice intentionally does not split container-unavailable vs permission
  failures because the current cross-platform native signals are not precise
  enough to promise that distinction as a stable contract.

Rules:

- Use typed exceptions only for stable, branchable categories.
- Preserve the original native domain, code, and message inside the exception
  for debugging.
- Normalize iOS and macOS to the same Dart exception category even when Cocoa
  error details differ.
- Treat conflict, placeholder, and in-progress download states as explicit
  iCloud conditions rather than generic read/write failures.

### Error Transport

Typed Dart exceptions in this slice must be backed by structured native channel
errors rather than Dart-side string parsing over generic native failures.

Rules:

- Add stable native error codes for branchable iCloud categories.
- Include machine-readable `details` fields that preserve native context.
- Map those structured channel errors to typed Dart exceptions.
- Keep a single unknown-native fallback for unclassified failures.
- Do not rely on localized `NSError` descriptions as the primary contract.

Required channel contract:

- `FlutterError.code`
  - stable plugin error code string emitted by native code
  - low-level transport identifier for compatibility, logging, and debugging
  - not the authoritative Dart branching discriminator
- `FlutterError.details`
  - machine-readable map with these required keys:
    - `category`: stable enum-like string that Dart may branch on
    - `operation`: stable operation identifier such as `getItemMetadata`,
      `writeInPlace`, `copy`, `move`, `delete`, or `download`
    - `retryable`: boolean
  - optional keys:
    - `relativePath`
    - `nativeDomain`
    - `nativeCode`
    - `nativeDescription`
    - `underlying`

Dart may branch only on `details.category`. All other fields are diagnostic.

Allowed `details.category` vocabulary and Dart mapping:

- `itemNotFound` -> `ICloudItemNotFoundException`
- `containerAccess` -> `ICloudContainerAccessException`
- `conflict` -> `ICloudConflictException`
- `itemNotDownloaded` -> `ICloudItemNotDownloadedException`
- `downloadInProgress` -> `ICloudDownloadInProgressException`
- `timeout` -> `ICloudTimeoutException`
- `coordination` -> `ICloudCoordinationException`
- `unknownNative` -> `ICloudUnknownNativeException`

No other `category` values are part of the contract in this slice.

### Native Boundaries

The native implementation should continue to respect the Apple platform model.

- Keep document reads and writes through `UIDocument` on iOS where document
  lifecycles are already established.
- Keep document reads and writes through `NSDocument` on macOS where that
  lifecycle is already established.
- Keep overwrite and existing-destination replacement through
  `NSFileCoordinator` plus `replaceItemAt(...)`.
- Keep known-path metadata from `URLResourceValues`.
- Keep discovery from `NSMetadataQuery`.
- Do not introduce a generic raw-file abstraction that hides iCloud-specific
  constraints.

### Exception Scope

Typed conflict and download-state exceptions should apply where surfacing state
is the safest and most stable behavior.

They apply to:

- overwrite and preflight flows
- direct known-path mutation APIs where callers need to react to stateful iCloud
  failures
- operations that require locality or coordination and cannot safely recover in
  place

They do not automatically replace current recovery behavior in APIs that
intentionally recover today.

- `getItemMetadata(...)`
  - returns `null` when the item is not found
  - returns in-band state for conflict, not-downloaded, and
    download-in-progress conditions
  - may still surface container-access or unknown-native failures
- `getItemMetadata(...)` should return state in-band rather than throwing for
  conflict, not-downloaded, or download-in-progress conditions.
- Existing read/download flows that currently auto-start downloads and wait for
  locality may keep that behavior in this slice.
- Existing document flows that intentionally preserve current success semantics
  should not be changed to fail eagerly unless a later release explicitly
  chooses a broader behavior change.

### Public API Behavior Map

The public API should follow these behavior rules:

- `icloudAvailable()`
  - remains a boolean availability probe
  - does not adopt typed exceptions in this slice
- `getContainerPath()`
  - remains a nullable path lookup at the type level for compatibility
  - on current Darwin implementations, container lookup failure surfaces as a
    typed container-access failure rather than `null`
  - `null` remains reserved for platforms that explicitly choose to return no
    path without treating it as an error
- `gather()`
  - returns discovery state in-band via `ICloudFile`
  - does not use typed state exceptions for ordinary item-status reporting
- `documentExists()`
  - remains a non-throwing existence probe for missing items
  - may still surface container-access or unknown-native failures
- `getItemMetadata()`
  - returns `ICloudItemMetadata?`
  - returns `null` for not-found
  - reports conflict/download/locality state in-band
  - throws only for container-access or unknown-native failures
- `getDocumentMetadata()`
  - returns raw map data or `null`
  - remains outside the normalized semantic contract
- `listContents()`
  - returns normalized `ContainerItem` state in-band
- `readInPlace()` / `readInPlaceBytes()`
  - preserve current recovery behavior for auto-download/wait flows in this
    slice
  - may surface typed not-found, container-access, timeout, coordination, or
    unknown native failures when recovery does not succeed
  - `ICloudTimeoutException` is used only after the configured or default
    idle-watchdog attempts are exhausted without successful completion
  - the existence of idle-timeout and retry-backoff controls is part of the
    public contract, but the exact default schedules remain implementation
    details so they can be tuned without another breaking release
- `downloadFile()`
  - preserves current download-and-wait behavior
  - may surface typed not-found, container-access, timeout, coordination, or
    unknown native failures
- `writeInPlace()` / `writeInPlaceBytes()` / `uploadFile()` / `copy()` /
  `move()` / `rename()` / `delete()`
  - use typed exceptions for stateful iCloud failures where callers must react,
    including conflict, not-downloaded, download-in-progress, coordination,
    not-found, container-access, and unknown-native fallback as applicable

### Platform Rules the API Must Reflect

- A path existing inside the ubiquity container does not imply the item is fully
  local or ready for replacement.
- Placeholder and nonlocal items must surface as explicit metadata and error
  states.
- Unresolved file-version conflicts must surface as explicit conflict state.
- Listing results are immediate local/container views, not the same thing as
  discovery state from `NSMetadataQuery`.

## Migration

This is an intentional breaking cleanup.

### Caller Changes

- Replace typed calls to `getMetadata(...)` with `getItemMetadata(...)`.
- Update code that expected an `ICloudFile` from a known-path metadata lookup to
  use `ICloudItemMetadata` instead.
- Continue using `getDocumentMetadata(...)` only when raw map access is
  genuinely needed.
- Update exception handling to branch on typed exceptions rather than broad
  `PlatformException` categories where practical.
- Keep existing transfer-progress stream listeners unchanged in this slice.

### Documentation Changes

- Public docs must explain the difference between discovery metadata,
  known-path metadata, and directory listings.
- Public docs must describe the normalized download-status vocabulary.
- Public docs must describe the typed iCloud exception categories and the
  situations that produce them.
- Public docs must explicitly note that `getDocumentMetadata(...)` remains a raw
  map API.
- Public docs must explicitly note that `getItemMetadata(...)` reports state
  in-band rather than throwing for conflict/download-status conditions.
- Public docs must explicitly note that transfer-progress stream errors remain
  `PlatformException`-based in this release.

## Testing Strategy

### Dart

- Add mapping tests for `ICloudItemMetadata`.
- Add regression tests for normalized status handling across all public mapping
  surfaces.
- Add exception-mapping tests for each typed iCloud failure category.
- Update any tests that assumed `getMetadata()` returned `ICloudFile`.
- Leave transfer-progress stream tests on the current `PlatformException`
  contract in this slice.

### Native

- Keep helper tests for overwrite orchestration and preflight.
- Keep helper source parity checks so the helper harness cannot silently drift
  from the production writer implementation.
- Keep local-file `live` replacement tests for the coordinated writer.
- Add targeted native tests where status normalization and native error mapping
  can be exercised without real iCloud entitlements.

### Manual Validation

Automated local tests cannot prove true iCloud placeholder, conflict,
eviction/download, and remote-sync behavior. After this slice lands, manual
Darwin validation remains required on a real signed environment.

## Risks

- Breaking the typed metadata API requires coordinated documentation and test
  updates.
- Some existing callers may rely on raw Apple status strings or broad native
  exceptions.
- Native error mapping can become overly specific if it branches on unstable
  Cocoa details instead of stable iCloud categories.
- The repo-owned migration scope is broad and must include public docs,
  example code, changelog notes, and existing method-channel/model tests, not
  only production source changes.

## Release Plan

This design requires a semver-major package release.

- Bump the package from `1.x` to `2.0.0` when this slice ships.
- Publish a migration guide covering:
  - `getMetadata(...)` removal
  - `getItemMetadata(...)` adoption
  - `ICloudItemMetadata` model usage
  - typed exception handling changes
  - the explicit decision that progress-stream errors remain
    `PlatformException`-based in `2.0.0`

## Recommendation

Implement this as one combined slice instead of separate mini-fixes. Error
semantics, metadata semantics, and status normalization all describe the same
caller-facing contract, and leaving any one of them behind would preserve the
core ambiguity this design is meant to remove.
