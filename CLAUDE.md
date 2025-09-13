# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

iCloud Storage Plus is a Flutter plugin that provides comprehensive iCloud integration for iOS and macOS. This is an enhanced fork incorporating community improvements, focusing on better file coordination using NSFileCoordinator and UIDocument/NSDocument.

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

# Both should pass before committing
```

### Example App
```bash
cd example
flutter run -d macos  # or -d ios
```

## Architecture

### Plugin Structure (Federated)
- **lib/**: Dart API layer
  - `icloud_storage.dart`: Main public API
  - `icloud_storage_platform_interface.dart`: Platform interface definition
  - `icloud_storage_method_channel.dart`: Method channel implementation
  - `models/`: Data models and exceptions

- **ios/Classes/**: iOS native implementation
  - `SwiftIcloudStoragePlugin.swift`: Main iOS plugin implementation
  
- **macos/Classes/**: macOS native implementation  
  - `IcloudStoragePlugin.swift`: macOS-specific implementation

### Key Design Patterns
1. **Platform Channels**: Communication between Dart and native code via method channels
2. **Stream-based Progress**: Upload/download progress reported via event streams
3. **Error Handling**: Typed exceptions in `models/exceptions.dart` for different failure scenarios

## Development Guidelines

### From .windsurfrules
1. Work in feature/bugfix branches - never commit directly to main
2. Follow Effective Dart naming and style conventions
3. Use Dart 3 features (records, patterns, exhaustive switch)
4. All public APIs require documentation and tests
5. Surface all native errors as typed exceptions
6. iOS/macOS code must use background queues (avoid blocking main thread)

### From Code Review Rules
1. Verify branch is up-to-date with target branch before PRs
2. Ensure all changed files are in correct directories
3. Check for security issues (no secrets/keys in code)
4. Maintain sufficient test coverage for new logic
5. Keep changes focused and scoped to stated purpose

## Current Development Focus

The project is actively improving iCloud file coordination:
- Implementing NSFileCoordinator for all file operations
- Adding UIDocument/NSDocument support for better iCloud integration
- Enhancing conflict resolution
- Maintaining backward compatibility

See `memory-bank/` directory for detailed context:
- `activeContext.md`: Current implementation status
- `progress.md`: Development progress tracking
- `projectbrief.md`: Core requirements and success criteria

## Testing Considerations

1. **iCloud Container**: Requires proper Apple Developer setup with iCloud entitlements
2. **Simulator Testing**: Use "Trigger iCloud Sync" from Features menu to force sync
3. **Device Testing**: iCloud sync happens opportunistically - may require patience

## Important Notes

- This is a fork incorporating PRs #40, #45 and features from community forks
- Not published to pub.dev - development/internal use only
- When adding native functionality, update both iOS and macOS implementations
- Check iCloud availability with `icloudAvailable()` before operations