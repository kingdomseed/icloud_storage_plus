# Task Plan: Streamed Document IO for Uploads

## Goal
Replace in-memory Data-based upload/write paths with a single Apple-aligned,
streaming document IO path across native + Dart layers, ensuring iCloud sync
and Files app exposure without technical-debt shims or size caps.

## Overriding Goals
1. Sync files to iCloud so users can retrieve them on other devices.
2. Expose files in the Files app in iCloud Drive (when enabled by the app).

## Current Phase
Phase 5

## Phases

### Phase 1: Requirements & Discovery
- [x] Understand user intent
- [x] Identify constraints and requirements
- [x] Document findings in findings.md
- **Status:** complete

### Phase 2: Planning & Structure
- [x] Define technical approach (single pathway, no shims)
- [x] Map required overrides in UIDocument/NSDocument
- [x] Define Dart API changes to support streaming path end-to-end
- [x] Define migration guide scope for breaking changes
- [x] Document decisions with rationale
- **Status:** complete

### Phase 3: Implementation
- [x] Rework iOS document layer for streaming write/read
- [x] Rework macOS document layer for streaming write/read
- [x] Route upload() through the streaming document write path
- [x] Remove Data(contentsOf:) from upload path
- [x] Update Dart API + method channel to pass streaming source paths
- [x] Remove Data-based convenience APIs (breaking change)
- [x] Update README + migration guide
- **Status:** complete

### Phase 4: Testing & Verification
- [x] Verify behavior on both platforms
- [x] Document test results in progress.md
- [x] Fix any issues found
- **Status:** complete

### Phase 5: Refinement & Tech Debt Cleanup
- [x] Normalize progress event handling in example app (avoid empty strings).
- [x] Use enum-based switch for progress events in example app.
- [x] Audit upload/download UI states for consistent null-safe updates.
- [x] Map delete coordination errors to E_FNF to avoid TOCTOU mismatch.
- [x] Add 10% kickoff progress events (upload/download) with monotonic clamp.
- [ ] Document "read is authoritative" download model and progress caveats.
- [ ] Document upload progress query behavior (empty results, long-lived stream).
- [x] Decide where to normalize trailing slashes (Dart accepts either; no trim).
- [x] Clarify 64KB streamCopy buffer scope and decision (doc read/write only).
- [x] Document gather() return type change with invalidEntries usage example.
- [x] Decide whether to reduce per-entry gather() warning logs.
- [ ] Verify progress stream buffering logic is documented in README/migration.
- [ ] Remove any unused imports or dead code introduced by streaming refactor.
- [ ] Ensure error handling pathways surface typed exceptions consistently.
- [ ] Re-check method channel argument naming consistency across platforms/tests.
- [ ] Run `dart fix`, `dart format`, and analyzer to confirm clean lint state.
- **Status:** in_progress

### Phase 6: Delivery
- [ ] Review all output files
- [ ] Ensure deliverables are complete
- [ ] Deliver to user
- **Status:** pending

## Key Questions
1. Which UIDocument/NSDocument overrides allow direct streaming to URL without
   Data blobs?
2. How to keep a single pathway without introducing helper method sprawl?
3. How to ensure Files app exposure and iCloud syncing stay intact?
4. What Dart API changes are needed to support streaming while keeping UX clear?
5. What are the implications for apps re-opening existing iCloud documents?

## Decisions Made
| Decision | Rationale |
|----------|-----------|
| Use URL/Stream tier only (no Data tier) | Align with Apple’s pro-path; avoids RAM spikes and meets streaming-only requirement. |
| File-path-only Dart API | Avoid platform channel serialization and duplicate memory usage. |
| Rename API to uploadFile/downloadFile | Make streaming path explicit and remove ambiguous byte APIs. |

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
|       | 1       |            |

## Notes
- No file-size caps or workarounds.
- Avoid Data(contentsOf:) and FileManager for upload path unless unavoidable.
- Keep a single, Apple-aligned pathway that supports iCloud sync + Files app.
