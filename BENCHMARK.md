# Performance Optimization: Reduced Filesystem Calls in Loop

## Issue
The previous implementation of `relativePath(for:containerURL:)` calculated `containerURL.standardizedFileURL.path` every time it was called. This function resolves symlinks and standardizes the path, which involves filesystem system calls.

This method was called inside a loop in `mapFileAttributesFromQuery`, which iterates over all items in the iCloud container. For a container with $N$ items, this resulted in $O(N)$ filesystem calls just to re-calculate the same constant container path.

## Optimization
We refactored `relativePath` to accept a pre-calculated `containerPath` string.
We now calculate `containerURL.standardizedFileURL.path` once before entering the loop in `mapFileAttributesFromQuery` and pass this string down to `mapMetadataItem` and `relativePath`.

## Performance Impact
This change reduces the complexity of path standardization from $O(N)$ to $O(1)$ per query gathering operation.

While we cannot run a Swift benchmark in this environment due to the lack of the `swift` CLI and `xcodebuild`, the theoretical improvement is significant for large file lists. String operations (checking prefix and substring) are orders of magnitude faster than filesystem calls.

## Affected Methods
- `relativePath(for:containerURL:)` -> `relativePath(for:containerPath:)`
- `mapMetadataItem(_:containerURL:)` -> `mapMetadataItem(_:containerPath:)`
- `mapResourceValues(fileURL:values:containerURL:)` -> `mapResourceValues(fileURL:values:containerPath:)`
- `mapFileAttributesFromQuery(query:containerURL:)` (Implementation updated)
- `getDocumentMetadata` (Implementation updated)
