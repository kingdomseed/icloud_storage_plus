# Error Handling Testing in Flutter/Dart

## Overview

Testing error handling is critical for ensuring your Flutter plugin gracefully handles failures, provides meaningful error messages, and maintains application stability. This guide covers best practices for testing exceptions, validation logic, and error propagation in Dart and Flutter code.

## Table of Contents

1. [Why Test Error Handling](#why-test-error-handling)
2. [Testing Exception Throwing](#testing-exception-throwing)
3. [Testing Custom Exceptions](#testing-custom-exceptions)
4. [Testing PlatformException](#testing-platformexception)
5. [Testing Validation Logic](#testing-validation-logic)
6. [Best Practices](#best-practices)
7. [Anti-Patterns to Avoid](#anti-patterns-to-avoid)
8. [Real-World Examples](#real-world-examples)

## Why Test Error Handling

Error handling tests serve several critical purposes:

- **Validate error messages**: Ensure users receive clear, actionable error information
- **Verify exception types**: Confirm the correct exception is thrown for each error condition
- **Test error propagation**: Verify errors bubble up correctly through async operations
- **Document failure modes**: Tests serve as documentation of how your API handles errors
- **Prevent regressions**: Catch changes that break error handling behavior
- **Edge case coverage**: Ensure boundary conditions and invalid inputs are handled properly

## Testing Exception Throwing

### Basic Exception Testing with `expect` and `throwsA`

The standard approach uses the `expect` function with exception matchers:

```dart
import 'package:test/test.dart';

void main() {
  test('parsing invalid input throws FormatException', () {
    expect(() => int.parse('invalid'), throwsFormatException);
  });

  test('custom error message validation', () {
    expect(
      () => someFunction('bad input'),
      throwsA(isA<ArgumentError>()),
    );
  });
}
```

**Key points:**
- Wrap the code that should throw in a closure `() => ...`
- Use specific exception matchers when available (`throwsFormatException`, `throwsStateError`, etc.)
- Use `throwsA(matcher)` for custom matching

**Source:** [dart-lang/test - matcher README](https://github.com/dart-lang/test/blob/master/pkgs/matcher/README.md)

### Testing Asynchronous Exception Throwing

When testing async functions, the matchers work with Futures:

```dart
import 'dart:async';
import 'package:test/test.dart';

void main() {
  test('Future.error() throws the expected error', () {
    expect(Future.error('oh no'), throwsA(equals('oh no')));
    expect(Future.error(StateError('bad state')), throwsStateError);
  });

  test('async function throws exception', () async {
    expect(
      () async => await fetchDataFromCloud('invalid-id'),
      throwsA(isA<PlatformException>()),
    );
  });
}
```

**Important:** Any uncaught asynchronous error within the zone that a test is running in will cause the test to fail. This can cause a test which was previously considered complete and passing to change into a failure if the uncaught async error is raised late.

**Source:** [dart-lang/test - test README](https://github.com/dart-lang/test/blob/master/pkgs/test/README.md)

### Using the `checks` Package for Better Assertions

The `checks` package (recommended in this project) provides more expressive assertions with compile-time safety:

```dart
import 'package:test/test.dart';
import 'package:checks/checks.dart';

void main() {
  test('validates exception with checks', () {
    check(() => dangerousOperation())
      .throws<InvalidArgumentException>();
  });

  test('validates exception properties', () {
    try {
      validateInput('');
      fail('Should have thrown');
    } catch (e) {
      check(e).isA<InvalidArgumentException>();
      check(e.toString()).contains('cannot be empty');
    }
  });
}
```

**Advantages of `checks`:**
- Better static analysis (catches invalid operations at compile time)
- More readable assertions
- Chainable checks for complex validations

**Source:** [dart-lang/test - checks README](https://github.com/dart-lang/test/blob/master/pkgs/checks/README.md)

## Testing Custom Exceptions

### Creating Testable Custom Exceptions

Custom exceptions should be designed with testing in mind:

```dart
/// Good: Provides structured error information
class InvalidArgumentException implements Exception {
  InvalidArgumentException(this.message, {this.parameterName});

  final String message;
  final String? parameterName;

  @override
  String toString() => 'InvalidArgumentException: $message'
      '${parameterName != null ? ' (parameter: $parameterName)' : ''}';
}
```

**From the project:** `/Users/jholt/development/icloud_storage_plus/lib/models/exceptions.dart`

### Testing Custom Exception Properties

```dart
import 'package:test/test.dart';

void main() {
  group('InvalidArgumentException', () {
    test('contains the error message', () {
      final exception = InvalidArgumentException(
        'Path cannot be empty',
        parameterName: 'relativePath',
      );

      expect(exception.message, equals('Path cannot be empty'));
      expect(exception.parameterName, equals('relativePath'));
    });

    test('toString includes message and parameter', () {
      final exception = InvalidArgumentException(
        'Invalid format',
        parameterName: 'filePath',
      );

      final stringRepresentation = exception.toString();
      expect(stringRepresentation, contains('Invalid format'));
      expect(stringRepresentation, contains('filePath'));
    });

    test('thrown when validation fails', () {
      expect(
        () => validatePath(''),
        throwsA(
          isA<InvalidArgumentException>()
            .having((e) => e.message, 'message', contains('empty')),
        ),
      );
    });
  });
}
```

**Best practices:**
- Test the exception constructor and properties
- Test the `toString()` method output
- Test that functions throw the exception under the right conditions
- Use `.having()` to validate specific exception properties

## Testing PlatformException

### Understanding PlatformException

`PlatformException` is Flutter's standard exception for errors from native platform code. It contains:
- `code`: A string error code for programmatic handling
- `message`: A human-readable error message
- `details`: Optional additional error information
- `stacktrace`: Optional platform stack trace

**Source:** [Flutter API Documentation](https://api.flutter.dev/ios-embedder/interface_flutter_error)

### Testing PlatformException in Method Channels

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Method channel error handling', () {
    const channel = MethodChannel('com.example/test');

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'errorMethod') {
          throw PlatformException(
            code: 'E_ERROR',
            message: 'Something went wrong',
            details: {'extra': 'information'},
          );
        }
        return null;
      });
    });

    test('handles PlatformException from native code', () async {
      expect(
        () async => await channel.invokeMethod('errorMethod'),
        throwsA(
          isA<PlatformException>()
            .having((e) => e.code, 'code', equals('E_ERROR'))
            .having((e) => e.message, 'message', contains('went wrong'))
            .having((e) => e.details, 'details', isNotNull),
        ),
      );
    });

    test('categorizes error codes correctly', () async {
      try {
        await channel.invokeMethod('errorMethod');
        fail('Should have thrown PlatformException');
      } on PlatformException catch (e) {
        expect(e.code, equals('E_ERROR'));
        expect(e.message, isNotNull);
        // Verify your error code constants
        expect(e.code, equals(PlatformExceptionCode.nativeCodeError));
      }
    });
  });
}
```

### Handling Uncaught Platform Errors

Errors from `MethodChannel.invokeMethod` and plugin calls may not be caught by `FlutterError.onError`. Instead, they're forwarded to `PlatformDispatcher`:

```dart
import 'dart:ui';
import 'package:flutter/material.dart';

void main() {
  // Set up handler for uncaught platform errors
  PlatformDispatcher.instance.onError = (error, stack) {
    // Log or report the error
    debugPrint('Uncaught error: $error');
    debugPrint('Stack trace: $stack');
    return true; // Indicates error was handled
  };

  runApp(const MyApp());
}
```

**Source:** [Flutter Error Handling Documentation](https://docs.flutter.dev/testing/errors)

## Testing Validation Logic

### Input Validation Testing Pattern

```dart
import 'package:test/test.dart';

void main() {
  group('Path validation', () {
    test('accepts valid relative paths', () {
      expect(() => validateRelativePath('Documents/file.txt'), returnsNormally);
      expect(() => validateRelativePath('dir/subdir/file.pdf'), returnsNormally);
    });

    test('rejects empty paths', () {
      expect(
        () => validateRelativePath(''),
        throwsA(
          isA<InvalidArgumentException>()
            .having((e) => e.message, 'message', contains('empty')),
        ),
      );
    });

    test('rejects paths with invalid characters', () {
      final invalidPaths = [
        'dir//file',    // Double slash
        '..file',       // Leading dots
        'dir:file',     // Colon
        'file/',        // Trailing slash
      ];

      for (final path in invalidPaths) {
        expect(
          () => validateRelativePath(path),
          throwsException,
          reason: 'Path "$path" should be rejected',
        );
      }
    });

    test('validation error messages are descriptive', () {
      try {
        validateRelativePath('dir//file');
        fail('Should have thrown');
      } on InvalidArgumentException catch (e) {
        expect(e.message, contains('consecutive slashes'));
      }
    });
  });
}
```

**Pattern highlights:**
- Test valid inputs first (positive tests)
- Test each invalid input category (negative tests)
- Use loops for multiple similar test cases
- Verify error messages are helpful
- Use `reason` parameter to clarify test failures

**From the project:** `/Users/jholt/development/icloud_storage_plus/test/icloud_storage_test.dart` (lines 200-243)

### Boundary Condition Testing

```dart
test('handles boundary conditions', () {
  // Minimum valid input
  expect(() => processFile('a'), returnsNormally);

  // Maximum valid input (if applicable)
  final longButValidPath = 'a' * 255;
  expect(() => processFile(longButValidPath), returnsNormally);

  // Just over the boundary
  final tooLongPath = 'a' * 256;
  expect(
    () => processFile(tooLongPath),
    throwsA(isA<InvalidArgumentException>()),
  );
});
```

## Best Practices

### 1. Test the Error Path, Not Just the Happy Path

```dart
// Bad: Only tests success case
test('uploads file', () async {
  await ICloudStorage.upload(
    containerId: 'id',
    filePath: '/valid/path',
  );
  expect(uploadCalled, isTrue);
});

// Good: Tests both success and failure
group('upload', () {
  test('succeeds with valid parameters', () async {
    await ICloudStorage.upload(
      containerId: 'id',
      filePath: '/valid/path',
    );
    expect(uploadCalled, isTrue);
  });

  test('throws InvalidArgumentException for empty filePath', () {
    expect(
      () async => ICloudStorage.upload(
        containerId: 'id',
        filePath: '',
      ),
      throwsA(isA<InvalidArgumentException>()),
    );
  });
});
```

### 2. Verify Exception Properties, Not Just Types

```dart
// Weak: Only checks exception type
expect(() => operation(), throwsA(isA<PlatformException>()));

// Strong: Validates exception details
expect(
  () => operation(),
  throwsA(
    isA<PlatformException>()
      .having((e) => e.code, 'code', equals('E_CTR'))
      .having((e) => e.message, 'message', contains('iCloud'))
      .having((e) => e.details, 'details', isNotNull),
  ),
);
```

### 3. Use Descriptive Test Names and Groups

```dart
// Good: Hierarchical organization with clear names
group('upload tests', () {
  group('validation', () {
    test('throws InvalidArgumentException when filePath is empty', () { });
    test('throws InvalidArgumentException for paths with consecutive slashes', () { });
    test('throws InvalidArgumentException for paths with invalid characters', () { });
  });

  group('success cases', () {
    test('uploads file when all parameters are valid', () { });
    test('uses filename as destination when not specified', () { });
  });
});
```

### 4. Test Error Messages Are User-Friendly

```dart
test('error messages provide actionable information', () {
  try {
    validatePath('dir//file');
    fail('Should have thrown');
  } on InvalidArgumentException catch (e) {
    // Message should explain what's wrong and how to fix it
    expect(e.message, contains('consecutive slashes'));
    expect(e.message, contains('not allowed'));
    // Bonus: suggest the fix
    expect(e.message, contains('Use single slashes'));
  }
});
```

### 5. Use `fail()` for Expected Exception Tests

```dart
// When you need to access exception properties
test('exception contains specific details', () async {
  try {
    await riskyOperation();
    fail('Expected PlatformException to be thrown');
  } on PlatformException catch (e) {
    expect(e.code, equals('E_NET'));
    expect(e.details, containsPair('retryable', true));
  }
});
```

### 6. Test Async Error Handling

```dart
test('async function propagates errors correctly', () async {
  // Method 1: Using expect with async closure
  expect(
    () async => await asyncOperation(),
    throwsA(isA<PlatformException>()),
  );

  // Method 2: Using try-catch
  try {
    await asyncOperation();
    fail('Should have thrown');
  } on PlatformException catch (e) {
    expect(e.code, equals('E_ERROR'));
  }
});
```

### 7. Add Context with `because` Parameter (checks package)

```dart
import 'package:checks/checks.dart';

test('validates log format', () {
  check(
    because: 'log lines must start with severity level',
    logLines,
  ).every((line) => line
    ..anyOf([
      (l) => l.startsWith('ERROR'),
      (l) => l.startsWith('WARNING'),
      (l) => l.startsWith('INFO'),
    ]));
});
```

**Source:** [checks package README](https://github.com/dart-lang/test/blob/master/pkgs/checks/README.md)

## Anti-Patterns to Avoid

### 1. Testing Exception Types Without Verifying Details

```dart
// Bad: Too generic
expect(() => operation(), throwsException);

// Good: Specific exception type and properties
expect(
  () => operation(),
  throwsA(
    isA<InvalidArgumentException>()
      .having((e) => e.message, 'message', contains('invalid path')),
  ),
);
```

### 2. Not Testing Exception Messages

```dart
// Bad: Only checks that an exception is thrown
test('throws on invalid input', () {
  expect(() => process(''), throwsException);
});

// Good: Validates the error message helps users
test('throws descriptive exception on empty input', () {
  expect(
    () => process(''),
    throwsA(
      isA<ArgumentError>()
        .having(
          (e) => e.toString(),
          'message',
          allOf([
            contains('empty'),
            contains('provide a valid'),
          ]),
        ),
    ),
  );
});
```

### 3. Ignoring Error Propagation in Async Code

```dart
// Bad: Doesn't await, error might not be caught
test('handles errors', () {
  expect(asyncFunction(), throwsA(isA<Exception>()));
  // Test might pass even if error handling is broken
});

// Good: Properly awaits or uses async matcher
test('handles errors', () {
  expect(
    () async => await asyncFunction(),
    throwsA(isA<Exception>()),
  );
});
```

### 4. Testing Implementation Instead of Behavior

```dart
// Bad: Tests internal implementation detail
test('calls _validatePath', () {
  // Verifying private method was called
  verify(mock._validatePath(any)).called(1);
});

// Good: Tests the observable behavior
test('rejects invalid paths', () {
  expect(
    () => upload(invalidPath),
    throwsA(isA<InvalidArgumentException>()),
  );
});
```

### 5. Not Using Specific Exception Matchers

```dart
// Bad: Generic throwsException doesn't verify the type
expect(() => int.parse('X'), throwsException);

// Good: Specific matcher ensures correct exception type
expect(() => int.parse('X'), throwsFormatException);
```

## Real-World Examples

### Example 1: Testing Path Validation (From Project)

```dart
group('upload tests', () {
  test('upload with invalid filePath', () async {
    expect(
      () async => ICloudStorage.upload(
        containerId: containerId,
        filePath: '',
      ),
      throwsException,
    );
  });

  test('upload with invalid destinationRelativePath - consecutive slashes', () async {
    expect(
      () async => ICloudStorage.upload(
        containerId: containerId,
        filePath: 'dir/file',
        destinationRelativePath: 'dir//file',
      ),
      throwsException,
    );
  });

  test('upload with invalid destinationRelativePath - leading dots', () async {
    expect(
      () async => ICloudStorage.upload(
        containerId: containerId,
        filePath: 'dir/file',
        destinationRelativePath: '..file',
      ),
      throwsException,
    );
  });

  test('upload with invalid destinationRelativePath - colon', () async {
    expect(
      () async => ICloudStorage.upload(
        containerId: containerId,
        filePath: 'dir/file',
        destinationRelativePath: 'dir:file',
      ),
      throwsException,
    );
  });
});
```

**Source:** `/Users/jholt/development/icloud_storage_plus/test/icloud_storage_test.dart` (lines 200-243)

### Example 2: Testing PlatformException Codes

```dart
import 'package:flutter/services.dart';
import 'package:test/test.dart';

void main() {
  group('PlatformException handling', () {
    test('identifies iCloud connection errors', () async {
      final channel = MethodChannel('test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(
          code: PlatformExceptionCode.iCloudConnectionOrPermission,
          message: 'User not signed in to iCloud',
          details: {'available': false},
        );
      });

      try {
        await channel.invokeMethod('checkICloud');
        fail('Should have thrown PlatformException');
      } on PlatformException catch (e) {
        expect(e.code, equals('E_CTR'));
        expect(e.message, contains('iCloud'));
        expect(e.details['available'], isFalse);
      }
    });

    test('identifies file not found errors', () async {
      expect(
        () async => await downloadFile('nonexistent.txt'),
        throwsA(
          isA<PlatformException>()
            .having(
              (e) => e.code,
              'code',
              equals(PlatformExceptionCode.fileNotFound),
            )
            .having((e) => e.message, 'message', contains('not found')),
        ),
      );
    });
  });
}
```

**Based on:** `/Users/jholt/development/icloud_storage_plus/lib/models/exceptions.dart`

### Example 3: Testing Error Propagation

```dart
test('errors propagate through convenience methods', () async {
  // Test that validation errors in lower-level methods
  // are properly propagated through convenience wrappers
  expect(
    () async => ICloudStorage.uploadToDocuments(
      containerId: 'id',
      filePath: '', // Invalid
    ),
    throwsA(isA<InvalidArgumentException>()),
  );

  expect(
    () async => ICloudStorage.downloadFromDocuments(
      containerId: 'id',
      relativePath: 'file/', // Invalid trailing slash
    ),
    throwsException,
  );
});
```

## Additional Resources

### Official Documentation

- [Dart Test Package](https://github.com/dart-lang/test) - Official testing framework
- [Flutter Testing Documentation](https://docs.flutter.dev/testing) - Flutter-specific testing guide
- [Flutter Error Handling](https://docs.flutter.dev/testing/errors) - Platform error handling
- [Checks Package](https://github.com/dart-lang/test/tree/master/pkgs/checks) - Modern assertion library
- [Platform Channels](https://docs.flutter.dev/platform-integration/platform-channels) - Method channel error handling

### Key Takeaways

1. **Always test error paths** alongside happy paths
2. **Verify exception details**, not just types
3. **Test error messages** are clear and actionable
4. **Use specific matchers** (`throwsFormatException`, `throwsA(isA<T>())`)
5. **Handle async errors** properly with `async/await`
6. **Organize tests** with descriptive groups and names
7. **Test edge cases** and boundary conditions
8. **Use `checks` package** for more expressive assertions
9. **Document failure modes** through comprehensive error tests
10. **Validate PlatformException** codes and messages for native integration

Testing error handling is not optional - it's a critical part of creating reliable, user-friendly Flutter plugins.
