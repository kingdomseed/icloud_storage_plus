# AGENTS.md

This file provides guidance to AI coding assistants that read `AGENTS.md` (for example, Cursor). Keep it aligned with `CLAUDE.md` and the Flutter AI rules template.

## Project Overview

iCloud Storage Plus is a Flutter plugin that provides comprehensive iCloud integration for iOS and macOS. This fork focuses on improved file coordination using NSFileCoordinator and UIDocument/NSDocument.

## AI Rules (Flutter/Dart)

Baseline rules come from the Flutter AI rules template at https://docs.flutter.dev/ai/ai-rules. When in doubt, follow the template and keep this file updated to match current Flutter/Dart guidance.

## Development Commands

### Testing
```bash
# Run all tests
flutter test

# Run tests for a specific file
flutter test test/icloud_storage_test.dart
```

### Code Quality
```bash
# Format code
dart format .

# Analyze code (currently has 2 deprecation warnings to fix)
dart analyze
```

### Example App
```bash
cd example
flutter run -d macos  # or -d ios
```

## Flutter/Dart Plugin Rules (Updated)

1. Prefer federated plugin architecture: app-facing API + platform interface + platform implementations.
2. Platform implementations must `extend` the platform interface (do not `implement`) and verify tokens via `PlatformInterface.verifyToken`. Use `MockPlatformInterfaceMixin` in tests that mock the interface.
3. Keep `flutter.plugin.platforms` in `pubspec.yaml` accurate (per-platform `pluginClass`, Android `package`, web `fileName`). For federated packages, use `implements` and endorse with `default_package` where applicable.
4. For native bindings, prefer `flutter create --template=package_ffi` (recommended since Flutter 3.38). Treat `plugin_ffi` as legacy.
5. If iOS + macOS implementations are shared, consider `sharedDarwinSource: true` and move sources to `darwin/`, updating podspec dependencies/targets accordingly.

## Project Conventions

- Follow Effective Dart naming and style conventions.
- All public APIs require documentation and tests.
- Surface all native errors as typed exceptions.
- iOS/macOS code must use background queues (avoid blocking main thread).
- When adding native functionality, update both iOS and macOS implementations.
- Check iCloud availability with `icloudAvailable()` before operations.

## Current Development Focus

- Implementing NSFileCoordinator for all file operations
- Adding UIDocument/NSDocument support for better iCloud integration
- Enhancing conflict resolution
- Maintaining backward compatibility

See `memory-bank/` for detailed context.
