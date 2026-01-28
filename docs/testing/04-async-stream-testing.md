# Testing Asynchronous Operations, Futures, and Streams in Dart

This guide covers best practices for testing asynchronous code in Dart, including Futures, Streams, and time-dependent behavior.

## Table of Contents

- [Testing Futures](#testing-futures)
- [Testing Streams](#testing-streams)
- [Testing Callbacks](#testing-callbacks)
- [Testing Time-Dependent Behavior](#testing-time-dependent-behavior)
- [Best Practices](#best-practices)
- [Common Mistakes](#common-mistakes)
- [Additional Resources](#additional-resources)

## Testing Futures

### Using async/await

The most straightforward way to test async functions is using `async`/`await` syntax. The test runner automatically waits for the returned Future to complete.

```dart
import 'dart:async';
import 'package:test/test.dart';

void main() {
  test('Future.value() returns the value', () async {
    var value = await Future.value(10);
    expect(value, equals(10));
  });
}
```

**Source:** [dart-lang/test README](https://github.com/dart-lang/test/blob/master/pkgs/test/README.md)

### Using completion() Matcher

For testing Futures without async/await, use the `completion()` matcher. This ensures the test waits for the Future to complete before applying the matcher to the resolved value.

```dart
import 'dart:async';
import 'package:test/test.dart';

void main() {
  test('Future.value() returns the value', () {
    expect(Future.value(10), completion(equals(10)));
  });
}
```

**Source:** [dart-lang/test matcher README](https://github.com/dart-lang/test/blob/master/pkgs/matcher/README.md)

### Testing Future Errors

Test errors thrown by Futures using `throwsA()` with matchers or specific exception matchers like `throwsStateError`.

```dart
import 'dart:async';
import 'package:test/test.dart';

void main() {
  test('Future.error() throws the error', () {
    expect(Future.error('oh no'), throwsA(equals('oh no')));
    expect(Future.error(StateError('bad state')), throwsStateError);
  });
}
```

**Source:** [dart-lang/test matcher README](https://github.com/dart-lang/test/blob/master/pkgs/matcher/README.md)

### Using package:checks for Async Operations

The modern `package:checks` provides a more type-safe way to test async operations:

```dart
import 'package:test/test.dart';

void main() {
  test('Future completes successfully', () async {
    await check(Future.value(10)).completes();
  });
}
```

**Advantage:** With the `unawaited_futures` lint enabled, `check` always returns a `Future` for async operations, making it harder to forget `await` and miss test failures.

**Source:** [dart-lang/test checks migration guide](https://github.com/dart-lang/test/blob/master/pkgs/checks/doc/migrating_from_matcher.md)

## Testing Streams

### Basic Stream Testing with expectAsync1

Use `expectAsync1` to verify that stream events are emitted the expected number of times:

```dart
import 'dart:async';
import 'package:test/test.dart';

void main() {
  test('Stream.fromIterable() emits the values in the iterable', () {
    var stream = Stream.fromIterable([1, 2, 3]);

    stream.listen(expectAsync1((number) {
      expect(number, inInclusiveRange(1, 3));
    }, count: 3));
  });
}
```

**Key Points:**
- `expectAsync1` takes a callback and a `count` parameter
- The test fails if the callback is called more or fewer times than `count`
- The test waits until the callback has been called `count` times before completing

**Source:** [dart-lang/test matcher README](https://github.com/dart-lang/test/blob/master/pkgs/matcher/README.md)

### Stream Matchers: emits, emitsInOrder, emitsDone

Test stream emissions using specialized stream matchers:

```dart
import 'dart:async';
import 'package:test/test.dart';

void main() {
  test('process emits status messages', () {
    var stdoutLines = Stream.fromIterable([
      'Ready.',
      'Loading took 150ms.',
      'Succeeded!'
    ]);

    expect(stdoutLines, emitsInOrder([
      // Values match individual events
      'Ready.',

      // Matchers also run against individual events
      startsWith('Loading took'),

      // Stream matchers can be nested
      emitsAnyOf(['Succeeded!', 'Failed!']),

      // Assert that the stream emits a done event and nothing else
      emitsDone
    ]));
  });
}
```

**Available Stream Matchers:**
- `emits(value)` - Matches a single event
- `emitsInOrder(matchers)` - Matches events in sequence
- `emitsAnyOf(values)` - Matches one of several possible values
- `emitsDone` - Ensures the stream completes
- `emitsError(matcher)` - Matches an error event
- `emitsThrough(matcher)` - Consumes events until one matches

**Source:** [dart-lang/test matcher README](https://github.com/dart-lang/test/blob/master/pkgs/matcher/README.md)

### Testing Streams with StreamQueue

For more complex stream testing, use `StreamQueue` from `package:async` to request events sequentially:

```dart
import 'dart:async';
import 'package:async/async.dart';
import 'package:test/test.dart';

void main() {
  test('process emits a WebSocket URL', () async {
    // Wrap the Stream in a StreamQueue so that we can request events
    var stdout = StreamQueue(Stream.fromIterable([
      'WebSocket URL:',
      'ws://localhost:1234/',
      'Waiting for connection...'
    ]));

    // Ignore lines from the process until it's about to emit the URL
    await expectLater(stdout, emitsThrough('WebSocket URL:'));

    // Parse the next line as a URL
    var url = Uri.parse(await stdout.next);
    expect(url.host, equals('localhost'));

    // You can match against the same StreamQueue multiple times
    await expectLater(stdout, emits('Waiting for connection...'));
  });
}
```

**Benefits of StreamQueue:**
- Allows sequential consumption of stream events
- Enables complex multi-step stream testing
- Can be used with both `expectLater` and direct `await stdout.next` calls
- Automatically consumes events as they're matched

**Source:** [dart-lang/test matcher README](https://github.com/dart-lang/test/blob/master/pkgs/matcher/README.md)

### Modern Stream Testing with package:checks

When using `package:checks`, streams must be explicitly wrapped in `StreamQueue`:

```dart
import 'package:async/async.dart';
import 'package:test/test.dart';

void main() {
  test('stream emits expected values', () async {
    await check(someStream).withQueue.inOrder([
      (s) => s.emits((e) => e.equals(1)),
      (s) => s.emits((e) => e.equals(2)),
      (s) => s.emits((e) => e.equals(3)),
      (s) => s.isDone(),
    ]);
  });

  test('multiple checks on same stream', () async {
    var someQueue = StreamQueue(someOtherStream);
    await check(someQueue).emits((e) => e.equals(1));
    // do something
    await check(someQueue).emits((e) => e.equals(2));
  });
}
```

**Key Points:**
- Use `.withQueue` for one-time stream checks or broadcast streams
- For single-subscription streams requiring multiple checks, create an explicit `StreamQueue`
- The `withQueue` method is a convenience shortcut

**Source:** [dart-lang/test checks README](https://github.com/dart-lang/test/blob/master/pkgs/checks/README.md)

### Testing StreamControllers

When testing code that uses `StreamController`, ensure proper cleanup:

```dart
import 'dart:async';
import 'package:test/test.dart';

void main() {
  late StreamController<int> controller;

  setUp(() {
    controller = StreamController<int>();
  });

  tearDown(() async {
    await controller.close();
  });

  test('controller emits added values', () async {
    controller.add(1);
    controller.add(2);
    controller.add(3);
    await controller.close();

    expect(
      controller.stream,
      emitsInOrder([1, 2, 3, emitsDone]),
    );
  });
}
```

**Important:** Always close `StreamController`s in tests to avoid resource leaks and hanging tests.

## Testing Callbacks

### Testing Callback Invocation with expectAsync

Use `expectAsync0` through `expectAsync6` (based on parameter count) to test callbacks:

```dart
import 'package:test/test.dart';

void main() {
  test('callback is called exactly once', () {
    var callback = expectAsync0(() {
      // This must be called exactly once
    }, count: 1);

    someFunction(callback);
  });

  test('callback with parameters', () {
    var callback = expectAsync1((int value) {
      expect(value, greaterThan(0));
    }, count: 3);

    // This must call callback exactly 3 times
    repeatThreeTimes(callback);
  });
}
```

**Key Points:**
- `expectAsync0` for no parameters, `expectAsync1` for one parameter, etc.
- The `count` parameter specifies how many times the callback must be called
- Test fails if callback is called more or fewer times than expected
- Test waits until callback has been called the correct number of times

**Source:** [dart-lang/test matcher README](https://github.com/dart-lang/test/blob/master/pkgs/matcher/README.md)

### Testing Callbacks that Receive Streams

For callbacks that receive `Stream` parameters (like Flutter's `EventChannel.StreamHandler`):

```dart
import 'dart:async';
import 'package:test/test.dart';

void main() {
  test('stream handler callback receives events', () async {
    StreamController<String> controller;
    Stream<String>? capturedStream;

    // Capture the stream passed to the callback
    var handler = expectAsync1((Stream<String> stream) {
      capturedStream = stream;
    }, count: 1);

    // Call the function that invokes the handler
    setupStreamHandler(handler);

    // Now test the captured stream
    await expectLater(
      capturedStream,
      emitsInOrder(['event1', 'event2', emitsDone]),
    );
  });
}
```

## Testing Time-Dependent Behavior

### Using fake_async Package

The `fake_async` package allows you to control time in tests without waiting for real time to pass:

```dart
import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  test("Future.timeout() throws an error once the timeout is up", () {
    // Any code run within [fakeAsync] is run within the context of the
    // [FakeAsync] object passed to the callback
    fakeAsync((async) {
      // All asynchronous features that rely on timing are automatically
      // controlled by [fakeAsync]
      expect(
        Completer().future.timeout(Duration(seconds: 5)),
        throwsA(isA<TimeoutException>()),
      );

      // This will cause the timeout above to fire immediately, without waiting
      // 5 seconds of real time
      async.elapse(Duration(seconds: 5));
    });
  });
}
```

**Use Cases:**
- Testing timeouts
- Testing periodic timers
- Testing delayed operations
- Any code that uses `Duration` and `Timer`

**Source:** [dart-lang/test fake_async README](https://github.com/dart-lang/test/blob/master/pkgs/fake_async/README.md)

### Integration with clock Package

`FakeAsync` can't control `DateTime.now()` or `Stopwatch` directly, but works with the `clock` package:

```dart
import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  test('clock integration', () {
    fakeAsync((async) {
      var startTime = clock.now();

      async.elapse(Duration(hours: 1));

      var endTime = clock.now();
      expect(endTime.difference(startTime), equals(Duration(hours: 1)));
    });
  });
}
```

**Source:** [dart-lang/test fake_async README](https://github.com/dart-lang/test/blob/master/pkgs/fake_async/README.md)

## Best Practices

### 1. Always Await Async Operations

```dart
// BAD: Missing await
test('bad test', () {
  someFuture(); // Test completes immediately, doesn't wait for Future
});

// GOOD: Properly awaited
test('good test', () async {
  await someFuture(); // Test waits for Future to complete
});
```

### 2. Use setUp and tearDown for Resource Management

```dart
import 'package:test/test.dart';
import 'dart:io';

void main() {
  late HttpServer server;
  late Uri url;

  setUp(() async {
    server = await HttpServer.bind('localhost', 0);
    url = Uri.parse('http://${server.address.host}:${server.port}');
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('server responds', () async {
    // Use server and url
  });
}
```

**Key Points:**
- `setUp()` runs before each test
- `tearDown()` runs after each test, even if the test fails
- Both can be async
- Ensures proper cleanup and test isolation

**Source:** [dart-lang/test README](https://github.com/dart-lang/test/blob/master/pkgs/test/README.md)

### 3. Close StreamControllers and Cancel Subscriptions

```dart
test('stream test with cleanup', () async {
  var controller = StreamController<int>();

  try {
    // Test logic
    controller.add(42);
    await expectLater(controller.stream, emits(42));
  } finally {
    await controller.close();
  }
});
```

### 4. Use StreamQueue for Complex Stream Testing

When you need to test streams with multiple steps or complex logic, prefer `StreamQueue` over simple matchers:

```dart
import 'package:async/async.dart';

test('complex stream interaction', () async {
  var queue = StreamQueue(myComplexStream);

  // Wait for first event
  var first = await queue.next;
  expect(first, equals('start'));

  // Do some work that affects the stream
  triggerNextPhase();

  // Wait for next event
  var second = await queue.next;
  expect(second, equals('middle'));

  await queue.cancel();
});
```

### 5. Handle Uncaught Async Errors

Any uncaught asynchronous error in a test's zone causes the test to fail. This can happen even after the test appears to complete:

```dart
// BAD: Fire-and-forget can cause late failures
test('bad async pattern', () async {
  someAsyncOperation(); // If this throws later, test fails
  await anotherOperation();
});

// GOOD: Properly await all async operations
test('good async pattern', () async {
  await someAsyncOperation();
  await anotherOperation();
});
```

**Source:** [dart-lang/test README](https://github.com/dart-lang/test/blob/master/pkgs/test/README.md)

### 6. Enable unawaited_futures Lint

Add to your `analysis_options.yaml`:

```yaml
linter:
  rules:
    unawaited_futures: true
```

This helps catch cases where you forget to `await` a Future.

**Source:** [dart-lang/test checks migration guide](https://github.com/dart-lang/test/blob/master/pkgs/checks/doc/migrating_from_matcher.md)

## Common Mistakes

### 1. Forgetting to Return or Await Futures

```dart
// WRONG: Test completes before Future
test('wrong', () {
  Future.delayed(Duration(seconds: 1), () {
    expect(true, false); // This never runs!
  });
});

// CORRECT: Test waits for Future
test('correct', () async {
  await Future.delayed(Duration(seconds: 1), () {
    expect(true, true);
  });
});
```

### 2. Not Closing StreamControllers

```dart
// WRONG: StreamController never closed
test('resource leak', () async {
  var controller = StreamController<int>();
  controller.add(1);
  await expectLater(controller.stream, emits(1));
  // controller.close() never called - resource leak!
});

// CORRECT: Always close in tearDown
late StreamController<int> controller;

setUp(() {
  controller = StreamController<int>();
});

tearDown(() async {
  await controller.close();
});
```

### 3. Using expect Instead of expectLater for Streams

```dart
// WRONG: expect doesn't wait for stream completion
test('wrong', () {
  expect(myStream, emits(42)); // Doesn't wait!
});

// CORRECT: expectLater waits for async matchers
test('correct', () async {
  await expectLater(myStream, emits(42));
});
```

### 4. Incorrect expectAsync Count

```dart
// WRONG: count doesn't match actual calls
test('wrong count', () {
  var callback = expectAsync1((x) {}, count: 2);
  callOnce(callback); // Called once, expected twice - test hangs then fails
});

// CORRECT: count matches actual invocations
test('correct count', () {
  var callback = expectAsync1((x) {}, count: 1);
  callOnce(callback);
});
```

### 5. Testing Single-Subscription Streams Multiple Times

```dart
// WRONG: Can't listen to single-subscription stream twice
test('wrong', () async {
  var stream = Stream.fromIterable([1, 2, 3]);
  await expectLater(stream, emits(1));
  await expectLater(stream, emits(2)); // Error: already listened to!
});

// CORRECT: Use StreamQueue for sequential checks
test('correct', () async {
  var queue = StreamQueue(Stream.fromIterable([1, 2, 3]));
  expect(await queue.next, equals(1));
  expect(await queue.next, equals(2));
  await queue.cancel();
});
```

### 6. Not Accounting for Test Timeouts

By default, tests timeout after 30 seconds of inactivity. For long-running async tests:

```dart
test('long operation', () async {
  // Increase timeout for this specific test
  await someLongOperation();
}, timeout: Timeout(Duration(minutes: 2)));
```

**Source:** [dart-lang/test README](https://github.com/dart-lang/test/blob/master/pkgs/test/README.md)

## Additional Resources

### Official Documentation

- [Dart Test Package](https://pub.dev/packages/test)
- [Dart Test README](https://github.com/dart-lang/test/blob/master/pkgs/test/README.md)
- [Dart Matcher Package](https://github.com/dart-lang/test/blob/master/pkgs/matcher/README.md)
- [package:checks](https://pub.dev/packages/checks) - Modern alternative to matchers
- [package:checks Migration Guide](https://github.com/dart-lang/test/blob/master/pkgs/checks/doc/migrating_from_matcher.md)
- [fake_async Package](https://pub.dev/packages/fake_async)
- [fake_async README](https://github.com/dart-lang/test/blob/master/pkgs/fake_async/README.md)
- [async Package](https://pub.dev/packages/async) - Includes StreamQueue

### Architecture and Internals

- [Test Package Architecture](https://github.com/dart-lang/test/blob/master/pkgs/test/doc/architecture.md)

### Related Packages

- **test_process**: Testing process execution with streams
  - [test_process README](https://github.com/dart-lang/test/blob/master/pkgs/test_process/README.md)
- **clock**: Clock abstraction for testing time-dependent code
  - [clock Package](https://pub.dev/packages/clock)

### Testing Guidelines

- [Effective Dart: Testing](https://dart.dev/effective-dart)
- [Flutter Testing Documentation](https://docs.flutter.dev/testing)

## Summary

Testing asynchronous code in Dart requires:

1. **For Futures**: Use `async`/`await` or the `completion()` matcher
2. **For Streams**: Use stream matchers (`emits`, `emitsInOrder`, `emitsDone`) or `StreamQueue` for complex scenarios
3. **For Callbacks**: Use `expectAsync0` through `expectAsync6` to verify invocation count
4. **For Time**: Use `fake_async` to control time without real delays
5. **For Cleanup**: Always use `setUp` and `tearDown` for resource management
6. **Modern Approach**: Consider migrating to `package:checks` for better type safety

Always remember to:
- `await` all async operations
- Close `StreamController`s and cancel subscriptions
- Use `expectLater` (not `expect`) for async matchers
- Enable the `unawaited_futures` lint
- Be aware of test timeouts (default: 30 seconds)

All code examples and best practices in this guide are sourced from the official Dart test package documentation and represent current recommended patterns as of January 2025.
