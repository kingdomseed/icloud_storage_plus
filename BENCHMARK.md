# Performance Optimization: Reduce Redundant Path Normalization in Loops

## Issue
The previous implementation of `relativePath(for:containerURL:)` calculated
`containerURL.standardizedFileURL.path` every time it was called.
`standardizedFileURL` performs in-memory URL/path normalization (for example,
removing `.` and `..` components). Even though each call is relatively cheap,
performing that work repeatedly in a tight loop is redundant.

This method was called inside a loop in `mapFileAttributesFromQuery`, which
iterates over all items in the iCloud container. For a container with $N$ items,
this resulted in $O(N)$ repeated normalizations just to re-calculate the same
constant container path.

## Optimization
We refactored `relativePath` to accept a pre-calculated `containerPath` string.
We now calculate `containerURL.standardizedFileURL.path` once before entering the loop in `mapFileAttributesFromQuery` and pass this string down to `mapMetadataItem` and `relativePath`.

## Performance Impact
This change reduces the *container path normalization* from $O(N)$ to $O(1)$ per
query gathering operation (the overall listing still performs $O(N)$ work per
item, including relative path computation).

The improvement is most relevant for large file lists, where shaving repeated
per-item work can reduce CPU time and allocations.

## Affected Methods
- `relativePath(for:containerURL:)` -> `relativePath(for:containerPath:)`
- `mapMetadataItem(_:containerURL:)` -> `mapMetadataItem(_:containerPath:)`
- `mapResourceValues(fileURL:values:containerURL:)` -> `mapResourceValues(fileURL:values:containerPath:)`
- `mapFileAttributesFromQuery(query:containerURL:)` (Implementation updated)
- `getDocumentMetadata` (Implementation updated)
