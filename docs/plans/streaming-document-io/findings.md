# Findings & Decisions

## Requirements
- Use planning with files to plan streaming document IO change.
- Single pathway (avoid helper sprawl, shims, migration patterns).
- Avoid Data(contentsOf:) and FileManager in upload path unless unavoidable.
- Apple-aligned approach that supports: (1) iCloud sync, (2) Files app exposure.
- Use Perplexity MCP for deeper research.
- Dart side can change; entire plugin should support streaming path end-to-end.
- Breaking changes are acceptable; no “convenience” APIs kept for compatibility.
- Streaming-only APIs are preferred (avoid Data-based APIs entirely).

## Research Findings
- UIDocument: `writeContents(_:andAttributes:safelyTo:for:)` calls into
  `writeContents(_:to:for:originalContentsURL:)` and is intended to be
  overridden when the contents object is not `Data`/`FileWrapper`, allowing
  custom on-disk writing to the provided URL. Apple notes override for custom
  writing logic.
- UIDocument: `read(from:)` can be overridden to control reading from a URL
  directly (avoid `load(fromContents:)` data blob path).
- NSDocument: `write(to:ofType:for:originalContentsURL:)` is the override point
  for custom on-disk writes with access to the destination URL and save
  operation.
- NSDocument: `read(from:ofType:)` is the override point for custom on-disk
  reads from a URL, bypassing data-based read paths.
- Apple’s document APIs are tiered:
  - **Data tier**: `contents(forType:)` / `load(fromContents:)` for small,
    atomic files (convenient, safe-save, but full-buffer).
  - **URL/Stream tier**: `writeContents(...safelyTo:)` / `read(from:)` for
    large/pro apps (streaming, constant memory, direct I/O control).
  - **FileWrapper tier**: package documents (directory bundles), supports
    structured documents but can still be eager if fully loaded.
- For our use case, URL/Stream tier aligns with large/rich files and avoids
  RAM spikes that can kill the app under memory pressure.

## Technical Decisions
| Decision | Rationale |
|----------|-----------|
|          |           |

## Issues Encountered
| Issue | Resolution |
|-------|------------|
|       |            |

## Resources
- https://developer.apple.com/documentation/uikit/uidocument
- https://developer.apple.com/documentation/uikit/uidocument/1622856-writecontents
- https://developer.apple.com/documentation/uikit/uidocument/1622871-read
- https://developer.apple.com/documentation/foundation/nsdocument
- https://developer.apple.com/documentation/foundation/nsdocument/1414046-write
- https://developer.apple.com/documentation/foundation/nsdocument/1414126-read

## Visual/Browser Findings
-
