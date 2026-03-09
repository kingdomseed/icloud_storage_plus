# Task Plan: Move `url(forUbiquityContainerIdentifier:)` to Background Queue

## Goal
Move the `FileManager.default.url(forUbiquityContainerIdentifier:)` call off
the main thread across all Swift plugin methods on both iOS and macOS. This
call can block on first iCloud access and currently runs synchronously on the
platform thread before dispatching filesystem work to a background queue.

## Origin
Identified during PR #19 review (Devin + Copilot). This is a pre-existing
pattern across 14+ methods — not a regression from `listContents`.

## Scope
- **Both platforms:** iOS (`iOSICloudStoragePlugin.swift`) and macOS
  (`macOSICloudStoragePlugin.swift`)
- **All methods** that call `url(forUbiquityContainerIdentifier:)`:
  - `gather`, `listContents`
  - `uploadFile`, `downloadFile`
  - `readInPlace`, `readInPlaceBytes`, `writeInPlace`, `writeInPlaceBytes`
  - `delete`, `move`, `copy`
  - `documentExists`, `getDocumentMetadata`, `getContainerPath`

## Approach Options

### Option A: Move guard block into DispatchQueue.global
Move the `guard let containerURL = ...` and `guard let args = ...` inside the
background dispatch block. Return errors on main queue via `result()`.

**Pro:** Minimal structural change per method.
**Con:** Repeated pattern in every method; error returns need `DispatchQueue.main.async`.

### Option B: Extract a shared helper
Create a private helper like `withContainer(call:result:body:)` that:
1. Dispatches to background queue
2. Resolves args + container URL
3. Calls the body closure with (args, containerURL)
4. Catches errors and returns on main queue

**Pro:** DRY, consistent error handling, single place to evolve.
**Con:** Larger refactor, must handle methods that don't use background dispatch.

## Recommendation
Option B — the repetition across 14+ methods is already a maintenance burden.
A shared helper would also enforce the AGENTS.md rule 6 (background queues)
structurally rather than by convention.

## Phases

### Phase 1: Design the helper
- [ ] Design `withContainer(call:result:body:)` signature
- [ ] Handle methods that don't need background dispatch (e.g. `icloudAvailable`)
- [ ] Decide on error return pattern (main queue hop)
- **Status:** pending

### Phase 2: macOS implementation
- [ ] Add helper to macOS plugin
- [ ] Migrate all methods to use helper
- [ ] Verify no behavioral changes (same error codes, same threading)
- **Status:** pending

### Phase 3: iOS implementation
- [ ] Add helper to iOS plugin (identical to macOS)
- [ ] Migrate all methods to use helper
- **Status:** pending

### Phase 4: Verification
- [ ] `flutter analyze` passes
- [ ] `flutter test` passes (85+ tests)
- [ ] Manual test on device (upload, download, gather, listContents)
- **Status:** pending

### Phase 5: PR
- [ ] Create PR referencing PR #19 review comments
- **Status:** pending

## Risk Assessment
- **Low risk:** All methods already work correctly; this only changes *where*
  the container URL lookup happens (main thread → background thread)
- **Threading concern:** `FlutterResult` must be called on the main thread.
  The helper must ensure `result()` always hops to main.
- **First-access latency:** The blocking behavior only occurs on first call
  per container ID per app launch. Subsequent calls are cached by the system.
