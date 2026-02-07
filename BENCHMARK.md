# Performance Improvement: Reduce Redundant Path Standardization

## Issue
The `relativePath` method in `iOSICloudStoragePlugin.swift` was previously calculating `containerURL.standardizedFileURL.path` every time it was called. This method is called inside a loop when listing files (`gather` method), leading to O(N) redundant calculations.

`standardizedFileURL` can be an expensive operation as it may involve filesystem calls to resolve symbolic links and normalize paths.

## Optimization
We refactored the code to calculate `containerPath` once before the loop and pass it down to `relativePath` (and intermediate mapping functions). This changes the complexity of the container path calculation from O(N) to O(1) per gather operation.

## Benchmark
Since we cannot run native iOS benchmarks in the CI environment, we provide a standalone Swift script below that demonstrates the performance difference.

### Swift Benchmark Script
You can run this script in an Xcode Playground or as a standalone Swift file on a Mac.

```swift
import Foundation

// Simulate the old implementation
func relativePathOld(for fileURL: URL, containerURL: URL) -> String {
    let containerPath = containerURL.standardizedFileURL.path
    let filePath = fileURL.standardizedFileURL.path
    guard filePath.hasPrefix(containerPath) else {
        return fileURL.lastPathComponent
    }
    var relative = String(filePath.dropFirst(containerPath.count))
    if relative.hasPrefix("/") {
        relative.removeFirst()
    }
    return relative
}

// Simulate the new implementation
func relativePathNew(for fileURL: URL, containerPath: String) -> String {
    let filePath = fileURL.standardizedFileURL.path
    guard filePath.hasPrefix(containerPath) else {
        return fileURL.lastPathComponent
    }
    var relative = String(filePath.dropFirst(containerPath.count))
    if relative.hasPrefix("/") {
        relative.removeFirst()
    }
    return relative
}

// Setup
let containerURL = URL(fileURLWithPath: "/Users/user/Library/Mobile Documents/iCloud~com~example~app/Documents/")
let fileURL = containerURL.appendingPathComponent("folder/file.txt")
let iterations = 100_000

// Benchmark Old
let startOld = CFAbsoluteTimeGetCurrent()
for _ in 0..<iterations {
    _ = relativePathOld(for: fileURL, containerURL: containerURL)
}
let endOld = CFAbsoluteTimeGetCurrent()
print("Old implementation time: \(endOld - startOld) seconds")

// Benchmark New
let startNew = CFAbsoluteTimeGetCurrent()
let containerPath = containerURL.standardizedFileURL.path // Calculated once
for _ in 0..<iterations {
    _ = relativePathNew(for: fileURL, containerPath: containerPath)
}
let endNew = CFAbsoluteTimeGetCurrent()
print("New implementation time: \(endNew - startNew) seconds")

let improvement = (endOld - startOld) / (endNew - startNew)
print("Speedup: \(String(format: "%.2f", improvement))x")
```

### Expected Results
The new implementation is expected to be significantly faster, potentially by orders of magnitude depending on the cost of `standardizedFileURL`. Even if `standardizedFileURL` is cached or fast, avoiding the function call and property access 100,000 times will yield measurable improvements.
