# Task Plan: Streamed Document IO for Uploads

## Goal
Replace in-memory Data-based upload/write paths with a single Apple-aligned,
streaming document IO path across native + Dart layers, ensuring iCloud sync
and Files app exposure without technical-debt shims or size caps.

## Overriding Goals
1. Sync files to iCloud so users can retrieve them on other devices.
2. Expose files in the Files app in iCloud Drive (when enabled by the app).

## Current Phase
Phase 2

## Phases

### Phase 1: Requirements & Discovery
- [x] Understand user intent
- [x] Identify constraints and requirements
- [x] Document findings in findings.md
- **Status:** complete

### Phase 2: Planning & Structure
- [ ] Define technical approach (single pathway, no shims)
- [ ] Map required overrides in UIDocument/NSDocument
- [ ] Define Dart API changes to support streaming path end-to-end
- [ ] Define migration guide scope for breaking changes
- [ ] Document decisions with rationale
- **Status:** in_progress

### Phase 3: Implementation
- [ ] Rework iOS document layer for streaming write/read
- [ ] Rework macOS document layer for streaming write/read
- [ ] Route upload() through the streaming document write path
- [ ] Remove Data(contentsOf:) from upload path
- [ ] Update Dart API + method channel to pass streaming source paths
- [ ] Remove Data-based convenience APIs (breaking change)
- [ ] Update README + migration guide
- **Status:** pending

### Phase 4: Testing & Verification
- [ ] Verify behavior on both platforms
- [ ] Document test results in progress.md
- [ ] Fix any issues found
- **Status:** pending

### Phase 5: Delivery
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

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
|       | 1       |            |

## Notes
- No file-size caps or workarounds.
- Avoid Data(contentsOf:) and FileManager for upload path unless unavoidable.
- Keep a single, Apple-aligned pathway that supports iCloud sync + Files app.
