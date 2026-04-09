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

### Status Normalization

All caller-visible Apple download-status values should be normalized before they
reach Dart.

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

### Typed Errors

Expected iCloud states become typed Dart exceptions rather than generic native
failures.

Planned Dart exception categories:

- `ICloudItemNotFoundException`
- `ICloudContainerUnavailableException`
- `ICloudConflictException`
- `ICloudItemNotDownloadedException`
- `ICloudDownloadInProgressException`
- `ICloudInvalidPathException`
- `ICloudCoordinationException`
- `ICloudPermissionException`
- `ICloudUnknownNativeException`

Rules:

- Use typed exceptions only for stable, branchable categories.
- Preserve the original native domain, code, and message inside the exception
  for debugging.
- Normalize iOS and macOS to the same Dart exception category even when Cocoa
  error details differ.
- Treat conflict, placeholder, and in-progress download states as explicit
  iCloud conditions rather than generic read/write failures.

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

### Documentation Changes

- Public docs must explain the difference between discovery metadata,
  known-path metadata, and directory listings.
- Public docs must describe the normalized download-status vocabulary.
- Public docs must describe the typed iCloud exception categories and the
  situations that produce them.

## Testing Strategy

### Dart

- Add mapping tests for `ICloudItemMetadata`.
- Add regression tests for normalized status handling across all public mapping
  surfaces.
- Add exception-mapping tests for each typed iCloud failure category.
- Update any tests that assumed `getMetadata()` returned `ICloudFile`.

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

## Recommendation

Implement this as one combined slice instead of separate mini-fixes. Error
semantics, metadata semantics, and status normalization all describe the same
caller-facing contract, and leaving any one of them behind would preserve the
core ambiguity this design is meant to remove.
