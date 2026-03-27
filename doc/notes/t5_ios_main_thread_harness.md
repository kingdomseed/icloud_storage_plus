# T5 iOS Main-Thread Harness

This plugin does not currently have a realistic automated iOS-native test seam
for the `UIDocument` hot path in
`ios/icloud_storage_plus/Sources/icloud_storage_plus/`.

The Swift Package manifest has no test target, and the relevant code depends on
`UIKit` + live iCloud document coordination. Dart unit tests cover the method
channel contract, but not the native timing boundary.

## Goal

Measure which operations still run synchronously on the iOS method-channel
thread before async `UIDocument.open(...)` / `UIDocument.save(...)` completion.

## Required setup

1. Use the sibling app repo `mythicgme2e`.
2. Run on an iOS simulator or device with iCloud Drive enabled.
3. Configure the app to use iCloud documents storage.
4. Start from empty or freshly cleared journal storage so the early coordinated
   read/write path is easy to isolate.
5. Build a `DEBUG` configuration so `DebugHelper.log(...)` emits timing logs.

## Probe points added in this repo

The iOS plugin now logs `elapsed_ms` and `main_thread` for:

- `getContainerPath` container lookup
- `readInPlace` container lookup, `startDownloadingUbiquitousItem`, and
  `waitForDownloadCompletion` callback duration
- `writeInPlace` container lookup and parent-directory creation preflight
- `readInPlaceDocument` document construction, `open` completion, and `close`
  completion
- `writeInPlaceDocument` document construction, save-operation preflight,
  `save` completion, and `close` completion
- `ICloudInPlaceDocument.init(fileURL:)`

## Suggested manual run

1. Launch the app from a cold start.
2. Navigate through the smallest flow that triggers the coordinated journal
   read/write path.
3. Capture the native logs around the first `readInPlace` / `writeInPlace`.
4. Compare the synchronous steps before `document_open_completion` or
   `document_save_completion`.

## What to look for

- Any slow `container_lookup` on the main thread
- Any slow synchronous preflight before `document_open_completion`
- Any slow `ICloudInPlaceDocument.init` on the main thread
- Whether the async `UIDocument` phase is the dominant cost, or whether the
  plugin-owned synchronous preflight already explains the T5 hang seam
