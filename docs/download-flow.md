# Download Flow Rationale

This document explains why the download implementation uses document
open/read as the source of truth and reserves metadata queries for progress
reporting.

## Source of truth: document open/read

The authoritative signal for whether a file can be read is the document
read path (`UIDocument` on iOS, `NSDocument` on macOS). These APIs coordinate
access with iCloud and provide the definitive success/failure outcome for a
read.

That means:
- A successful open/read is a completed download.
- A file-not-found error from open/read is a genuine "not found."
- Other errors are surfaced as native errors.

## Metadata queries are progress-only

`NSMetadataQuery` is a live monitor. It reports changes in the metadata
index, not a final "exists" answer. For download progress we only read the
percent downloaded value when available. We do not infer existence or failure
from empty results.

Progress streams close when the transfer completes or errors. If metadata is
not yet available, the stream remains open until the transfer state is known.

Existence checks (`documentExists`) use direct filesystem URLs rather than
metadata queries.

## Error codes

We map Cocoa file-not-found errors to distinct codes:
- `E_FNF` for `NSFileNoSuchFileError`
- `E_FNF_READ` for `NSFileReadNoSuchFileError`
- `E_FNF_WRITE` for `NSFileWriteNoSuchFileError`

All other errors are reported as native errors.
