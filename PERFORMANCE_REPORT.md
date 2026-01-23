# Performance Improvement Report

## Optimization: Remove Redundant String Property Access in Loop

**File:** `ios/Classes/iOSICloudStoragePlugin.swift`
**Method:** `mapFileAttributesFromQuery`

### Issue
The original code calculated `containerURL.absoluteString.count` inside a `for` loop that iterates over all files returned by an iCloud query.

```swift
for item in query.results {
  // ...
  let map: [String: Any?] = [
    "relativePath": String(fileURL.absoluteString.dropFirst(containerURL.absoluteString.count)),
    // ...
  ]
  fileMaps.append(map)
}
```

### Optimization
The value `containerURL.absoluteString.count` is invariant during the loop. We extracted this calculation outside the loop.

```swift
let containerURLStringCount = containerURL.absoluteString.count
for item in query.results {
  // ...
  let map: [String: Any?] = [
    "relativePath": String(fileURL.absoluteString.dropFirst(containerURLStringCount)),
    // ...
  ]
  fileMaps.append(map)
}
```

### Performance Impact
*   **Algorithmic Complexity:**
    *   `URL.absoluteString` (in Swift/ObjC) typically involves creating a new String object.
    *   `String.count` in Swift iterates over Unicode grapheme clusters, which is an O(N) operation where N is the length of the string.
    *   By moving this calculation outside the loop, we reduced the complexity from `O(M * N)` to `O(N + M)`, where M is the number of files (loop iterations) and N is the length of the container URL string.
*   **Allocations:** Reduced unnecessary temporary String allocations inside the loop.

### Benchmarking
Due to the constraints of the execution environment (absence of `swift` CLI and ability to run iOS simulators), a runtime benchmark could not be executed. However, the performance benefits of hoisting invariant calculations—especially those involving object allocation and O(N) property access—out of loops are a well-established principle in computer science and software engineering.
