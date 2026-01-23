# Testing Documentation

This directory contains comprehensive testing methodology documentation for the
iCloud Storage Plus Flutter plugin.

## Quick Start

**Start here:** Read [00-testing-strategy.md](00-testing-strategy.md) for a
complete analysis of what needs testing and why.

## Documentation Index

### Strategy & Planning

- **[00-testing-strategy.md](00-testing-strategy.md)** - Master testing
  strategy document
  - Maps uncovered code to testing methodologies
  - Explains what should and shouldn't be tested
  - Provides prioritized action plan
  - **START HERE**

### Testing Guides

- **[01-platform-interface-testing.md](01-platform-interface-testing.md)** -
  Platform Interface Testing
  - How to test classes extending `PlatformInterface`
  - What NOT to test (UnimplementedError methods)
  - Token verification mechanism
  - Mock setup with `MockPlatformInterfaceMixin`

- **[02-method-channel-testing.md](02-method-channel-testing.md)** - Method
  Channel Testing
  - How to mock `MethodChannel` in tests
  - Testing `EventChannel` and broadcast streams
  - `TestDefaultBinaryMessenger` and flutter_test utilities
  - Testing progress callbacks and streams
  - 826 lines of comprehensive examples

- **[03-error-handling-testing.md](03-error-handling-testing.md)** - Error
  Handling Testing
  - Testing `PlatformException` throwing and handling
  - Testing custom exceptions (`InvalidArgumentException`)
  - Testing validation logic
  - Error path verification
  - Best practices and anti-patterns

- **[04-async-stream-testing.md](04-async-stream-testing.md)** - Async & Stream
  Testing
  - Testing async/await functions
  - Testing Stream emissions and transformations
  - Testing `StreamHandler` callbacks
  - Using `fake_async` for time-dependent tests
  - Complete async testing patterns

## Current Coverage Status

```
lib/icloud_storage_method_channel.dart      44/ 74 lines ( 59.5%)
lib/models/icloud_file.dart                 20/ 22 lines ( 90.9%)
lib/icloud_storage.dart                     82/104 lines ( 78.8%)
lib/icloud_storage_platform_interface.dart   6/ 32 lines ( 18.8%)
lib/models/exceptions.dart                   1/  3 lines ( 33.3%)
```

## Key Findings

### What NOT to Test

❌ **Platform interface stub methods** - Testing `UnimplementedError` methods
provides no value

See [01-platform-interface-testing.md](01-platform-interface-testing.md) for
detailed explanation.

### High Priority Test Gaps

1. **Document API methods** (CRITICAL)
   - `readDocument()`, `writeDocument()`, `documentExists()`,
     `getDocumentMetadata()`
   - Zero test coverage on new major features
   - See: [02-method-channel-testing.md](02-method-channel-testing.md)

2. **`copy()` method** (HIGH)
   - File operation with no tests
   - Needs both method channel and API layer tests
   - See: [02-method-channel-testing.md](02-method-channel-testing.md) and
     [03-error-handling-testing.md](03-error-handling-testing.md)

3. **Error handling paths** (HIGH)
   - Validation logic in multiple methods
   - Error scenarios not covered
   - See: [03-error-handling-testing.md](03-error-handling-testing.md)

## How to Use These Docs

1. **Start with the strategy:**
   [00-testing-strategy.md](00-testing-strategy.md)
2. **Find your code category** (platform interface, method channel, API layer,
   error handling)
3. **Read the relevant guide** for testing methodology
4. **Follow the code examples** to implement proper tests
5. **Check the sources** linked in each guide for official documentation

## Sources

All documentation is based on:
- Official Flutter documentation (docs.flutter.dev)
- Dart test package documentation (dart-lang/test)
- Flutter framework source code examples
- plugin_platform_interface package documentation
- Current project codebase analysis

## Testing Principles

Based on research across all guides:

1. **Test your code, not the framework** - Focus on behavior you control
2. **Meaningful tests only** - False security is worse than no test
3. **Test behavior, not implementation** - What it does matters, not how
4. **Error paths are critical** - Test validation and error handling
5. **Use proper mocking patterns** - Follow Flutter recommendations
6. **Clean up resources** - Close streams, clear handlers in tearDown

## Contributing

When adding new tests:

1. Consult the appropriate guide for methodology
2. Follow the code examples and patterns shown
3. Include both happy path and error path tests
4. Use descriptive test names and groups
5. Run `flutter test --coverage` to verify improvement

## Running Coverage

```bash
# Run all tests with coverage
flutter test --coverage

# View coverage summary
cat coverage/lcov.info | grep -E "^SF:|^LH:|^LF:" | \
  awk '/^SF:/ {file=$0; sub(/^SF:/, "", file)} \
       /^LH:/ {lh=$2} \
       /^LF:/ {lf=$2; if (lf > 0) \
         printf "%-50s %3d/%3d lines (%.1f%%)\n", \
         file, lh, lf, (lh/lf)*100}'
```

## Questions?

Refer to the linked official documentation in each guide. All code examples are
sourced from authoritative Flutter and Dart documentation.
