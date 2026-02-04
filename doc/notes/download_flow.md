# Download flow rationale

This note explains why the download implementation treats document open/read as
the source of truth and uses metadata queries primarily for progress reporting.

## Source of truth: document open/read

The authoritative signal for whether a file can be read is the document read
path (`UIDocument` on iOS, `NSDocument` on macOS). These APIs coordinate access
with iCloud and provide the definitive success/failure outcome for a read.

That means:

- A successful open/read is a completed download.
- A file-not-found error from open/read is a genuine “not found.”
- Other errors are surfaced as native errors.

## Metadata queries are progress-only

`NSMetadataQuery` is a live monitor. It reports changes in the metadata index,
not a final “exists” answer. For download progress we only read the percent
downloaded value when available. We do not infer existence or failure from
empty results.

Progress streams close when the transfer completes or errors. If metadata is
not yet available, the stream remains open until the transfer state is known.

Existence checks (`documentExists`) use direct filesystem URLs rather than
metadata queries. iCloud placeholders are local entries, so `fileExists` can
return true once the directory metadata syncs, even if the file is not fully
downloaded.

## In-place access

Coordinated in-place reads (`readInPlace`) do not pre-check file existence.
Instead, they:

- Trigger download with `startDownloadingUbiquitousItem` when needed.
- Wait for metadata to report download status `current` (with idle watchdog
  retries).
- Attempt a coordinated document open/read.

File-not-found and other failures surface as errors (not null). Text reads use
UTF-8 decoding; use `readInPlaceBytes` for binary formats.

## Error codes

We map Cocoa file-not-found errors to distinct codes:

- `E_FNF` for `NSFileNoSuchFileError`
- `E_FNF_READ` for `NSFileReadNoSuchFileError`
- `E_FNF_WRITE` for `NSFileWriteNoSuchFileError`

Idle watchdog timeouts return `E_TIMEOUT`.

All other errors are reported as native errors.

