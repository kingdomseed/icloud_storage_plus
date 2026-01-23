# Testing Strategy for iCloud Storage Plus

This document maps the uncovered code from the coverage report to proper testing
methodologies, explaining what should be tested, what shouldn't be tested, and
why.

## Current Coverage Status

```
lib/icloud_storage_method_channel.dart      44/ 74 lines ( 59.5%)
lib/models/icloud_file.dart                 20/ 22 lines ( 90.9%)
lib/icloud_storage.dart                     82/104 lines ( 78.8%)
lib/icloud_storage_platform_interface.dart   6/ 32 lines ( 18.8%)
lib/models/exceptions.dart                   1/  3 lines ( 33.3%)
```

## Testing Methodology Reference

Before testing any uncovered code, consult these guides:

- **[01-platform-interface-testing.md](01-platform-interface-testing.md)** -
  How to test platform interfaces and what NOT to test
- **[02-method-channel-testing.md](02-method-channel-testing.md)** - How to
  test MethodChannel and EventChannel implementations
- **[03-error-handling-testing.md](03-error-handling-testing.md)** - How to
  test exceptions, validation, and error paths
- **[04-async-stream-testing.md](04-async-stream-testing.md)** - How to test
  async operations, Futures, and Streams

## Coverage Analysis & Testing Recommendations

### 1. Platform Interface (18.8% coverage) - DO NOT TEST

**File:** `lib/icloud_storage_platform_interface.dart`

**Uncovered lines:** All abstract method implementations that throw
`UnimplementedError`

**Recommendation:** ❌ **DO NOT ADD TESTS**

**Rationale:**
- These are abstract stub methods meant to be overridden by platform
  implementations
- Testing that they throw `UnimplementedError` provides NO value and creates
  false security
- See **[01-platform-interface-testing.md](01-platform-interface-testing.md)**,
  section "What NOT to Test"

**Quote from research:**
> "Testing UnimplementedError methods in abstract interfaces provides no value.
> You're testing framework behavior, not your code."

**What IS tested (and correct):**
- Token verification mechanism (lines 13-17, 22, 27-29)
- Instance getter/setter logic
- These are the only lines that need coverage in this file

### 2. Method Channel Implementation (59.5% coverage) - MIXED

**File:** `lib/icloud_storage_method_channel.dart`

#### 2a. Missing Tests - SHOULD ADD

**Lines to test:**

1. **`icloudAvailable()` method (lines 13-17)** ✅ ADD TEST
   - **Guide:** [02-method-channel-testing.md](02-method-channel-testing.md)
   - **How:** Mock method channel to return bool
   - **Why:** Tests method channel integration and null handling
   - **Priority:** HIGH (core availability check)

2. **`getContainerPath()` method (lines 55-62)** ✅ ADD TEST
   - **Guide:** [02-method-channel-testing.md](02-method-channel-testing.md)
   - **How:** Mock method channel to return String?
   - **Why:** Tests nullable return value handling
   - **Priority:** MEDIUM

3. **`copy()` method (lines 155-166)** ✅ ADD TEST
   - **Guide:** [02-method-channel-testing.md](02-method-channel-testing.md)
   - **How:** Mock method channel with proper arguments
   - **Why:** File operation needs verification
   - **Priority:** HIGH (untested file operation)

4. **Document methods (lines 204-257)** ✅ ADD TESTS
   - `readDocument()` (204-215)
   - `writeDocument()` (217-228)
   - `documentExists()` (230-240)
   - `getDocumentMetadata()` (242-257)
   - **Guide:** [02-method-channel-testing.md](02-method-channel-testing.md)
   - **How:** Mock method channel, test Uint8List handling, null returns
   - **Why:** Core new functionality for coordinated file access
   - **Priority:** CRITICAL (new major features)

5. **`downloadAndRead()` with onProgress (lines 176-192)** ✅ ADD TEST
   - **Guide:** [02-method-channel-testing.md](02-method-channel-testing.md)
     and [04-async-stream-testing.md](04-async-stream-testing.md)
   - **How:** Use MockStreamHandler to test EventChannel progress callback
   - **Why:** Progress tracking needs verification
   - **Priority:** MEDIUM (nice-to-have feature)

#### 2b. Lines That Shouldn't Be Tested Separately

**Lines 39-40:** Event channel stream mapping in `gather()`
- **Status:** ❌ Don't test in isolation
- **Why:** This is covered by the existing `gather with update` test
- **Current test:** `test/icloud_storage_method_channel_test.dart:71`
- Already has 100% functional coverage through integration test

### 3. High-Level API (78.8% coverage) - PRIORITIZE CAREFULLY

**File:** `lib/icloud_storage.dart`

#### 3a. Methods Missing Tests - SHOULD ADD

1. **`icloudAvailable()` static method (lines 64-65)** ✅ ADD TEST
   - **Guide:** Basic function test (no special guide needed)
   - **How:** Mock platform instance, verify call passthrough
   - **Why:** Ensures static wrapper works correctly
   - **Priority:** LOW (simple passthrough)

2. **`copy()` method (lines 510-527)** ✅ ADD TEST
   - **Guide:** [03-error-handling-testing.md](03-error-handling-testing.md)
   - **How:** Test happy path + validation errors
   - **Uncovered lines:** 516-517 (validation), 522-523 (validation)
   - **Why:** File operation with validation logic
   - **Priority:** HIGH (untested file operation)

3. **`readJsonDocument()` method (lines 728-743)** ✅ ADD TEST
   - **Guide:** [03-error-handling-testing.md](03-error-handling-testing.md)
   - **How:** Test JSON parsing, null handling, FormatException
   - **Why:** Data transformation with error handling
   - **Priority:** MEDIUM (convenience method)

#### 3b. Error Paths - SHOULD ADD

**These are legitimate error scenarios that should be tested:**

1. **`rename()` source validation (lines 361, 365)** ✅ ADD TEST
   - **Guide:** [03-error-handling-testing.md](03-error-handling-testing.md)
   - **What:** Test when source file doesn't exist
   - **Why:** Error path validation
   - **Priority:** MEDIUM

2. **`getMetadata()` error handling (line 550)** ✅ ADD TEST
   - **Guide:** [03-error-handling-testing.md](03-error-handling-testing.md)
   - **What:** Test when file not found
   - **Why:** Null return case
   - **Priority:** LOW (error branch)

3. **`writeJsonDocument()` validation (lines 668, 698)** ✅ ADD TEST
   - **Guide:** [03-error-handling-testing.md](03-error-handling-testing.md)
   - **What:** Test path validation and JSON encoding
   - **Why:** Input validation
   - **Priority:** MEDIUM

4. **`updateDocument()` error cases (lines 643, 490)** ✅ ADD TEST
   - **Guide:** [03-error-handling-testing.md](03-error-handling-testing.md)
   - **What:** Test validation and missing file scenarios
   - **Why:** Complex operation with multiple error paths
   - **Priority:** MEDIUM

#### 3c. Lines That Are Unreachable or Low Value

**Lines 299, 325-326, 331-332:** Internal validation in `delete()`, `move()`
- **Status:** ⚠️ Check if reachable
- **Why:** These appear to be defensive error checks
- **Action:** Verify if these can actually be triggered, if not, consider
  removing dead code

### 4. Models (90.9% coverage) - LOW PRIORITY

**File:** `lib/models/icloud_file.dart`

**Uncovered lines:** 69-70 (hashCode and equality operator)

**Recommendation:** ✅ OPTIONAL - Add if time permits

**Rationale:**
- These are generated/standard Dart patterns
- Low value tests but easy to add
- Only adds value if you're using these objects in Sets or as Map keys
- **Guide:** Basic equality testing (standard Dart pattern, no special guide)

**How to test:**
```dart
test('ICloudFile equality', () {
  final file1 = ICloudFile(relativePath: 'test.txt', ...);
  final file2 = ICloudFile(relativePath: 'test.txt', ...);
  final file3 = ICloudFile(relativePath: 'other.txt', ...);

  expect(file1, equals(file2));
  expect(file1, isNot(equals(file3)));
  expect(file1.hashCode, equals(file2.hashCode));
});
```

### 5. Exceptions (33.3% coverage) - LOW PRIORITY

**File:** `lib/models/exceptions.dart`

**Uncovered lines:** 9-10 (`toString()` method)

**Recommendation:** ✅ ADD TEST (quick win)

**Rationale:**
- Easy to test and verify exception message formatting
- Useful for debugging
- **Guide:** [03-error-handling-testing.md](03-error-handling-testing.md),
  section "Testing Custom Exceptions"

**How to test:**
```dart
test('InvalidArgumentException toString', () {
  final exception = InvalidArgumentException('test message');
  expect(
    exception.toString(),
    'InvalidArgumentException: test message',
  );
});
```

**Note:** `PlatformExceptionCode` is all constants, no code to test.

## Prioritized Action Plan

### Priority 1: CRITICAL (Do First)

1. ✅ **Test Document API methods in MethodChannelICloudStorage**
   - `readDocument()`, `writeDocument()`, `documentExists()`,
     `getDocumentMetadata()`
   - **Why:** New major features with zero test coverage
   - **Guide:** [02-method-channel-testing.md](02-method-channel-testing.md)
   - **Estimated tests:** 8-10 tests

2. ✅ **Test `copy()` method (both layers)**
   - Method channel implementation
   - High-level API wrapper
   - **Why:** File operation with no coverage
   - **Guide:** [02-method-channel-testing.md](02-method-channel-testing.md)
     and [03-error-handling-testing.md](03-error-handling-testing.md)
   - **Estimated tests:** 4-5 tests

### Priority 2: HIGH (Do Next)

3. ✅ **Test `icloudAvailable()` method**
   - Method channel implementation
   - High-level API wrapper
   - **Why:** Core availability check
   - **Guide:** [02-method-channel-testing.md](02-method-channel-testing.md)
   - **Estimated tests:** 2 tests

4. ✅ **Test error paths in high-level API**
   - `rename()` source validation
   - `copy()` validation
   - `writeJsonDocument()` validation
   - **Why:** Proper error handling verification
   - **Guide:** [03-error-handling-testing.md](03-error-handling-testing.md)
   - **Estimated tests:** 6-8 tests

### Priority 3: MEDIUM (Nice to Have)

5. ✅ **Test `getContainerPath()` method**
   - **Guide:** [02-method-channel-testing.md](02-method-channel-testing.md)
   - **Estimated tests:** 2 tests

6. ✅ **Test `readJsonDocument()` method**
   - **Guide:** [03-error-handling-testing.md](03-error-handling-testing.md)
   - **Estimated tests:** 3-4 tests

7. ✅ **Test `downloadAndRead()` with onProgress**
   - **Guide:** [02-method-channel-testing.md](02-method-channel-testing.md)
     and [04-async-stream-testing.md](04-async-stream-testing.md)
   - **Estimated tests:** 2 tests

### Priority 4: LOW (Optional)

8. ⚠️ **Test `InvalidArgumentException.toString()`**
   - **Guide:** [03-error-handling-testing.md](03-error-handling-testing.md)
   - **Estimated tests:** 1 test (quick win)

9. ⚠️ **Test `ICloudFile` equality operators**
   - Basic Dart equality testing
   - **Estimated tests:** 1 test (quick win)

### DO NOT TEST

❌ **Platform interface default implementations**
- All methods in `ICloudStoragePlatform` that throw `UnimplementedError`
- **Rationale:** See
  [01-platform-interface-testing.md](01-platform-interface-testing.md)
- Testing framework code provides false security

## Summary of Expected Coverage After Tests

If all Priority 1-3 tests are added:

```
lib/icloud_storage_method_channel.dart:     ~95% (was 59.5%)
lib/models/icloud_file.dart:                 90.9% (unchanged)
lib/icloud_storage.dart:                    ~92% (was 78.8%)
lib/icloud_storage_platform_interface.dart:  18.8% (unchanged - correct!)
lib/models/exceptions.dart:                 ~66% (was 33.3%)
```

**Note:** Platform interface will remain at 18.8% and that's correct - we're
only testing the token mechanism, not stub methods.

## Key Principles

Based on the research documentation:

1. **Test your code, not the framework** - Don't test Flutter's platform
   channel infrastructure
2. **Test behavior, not implementation** - Focus on what the code does, not how
3. **Meaningful tests only** - A test that provides false security is worse
   than no test
4. **Error paths matter** - Test validation and error handling
5. **Use proper mocking** - Follow Flutter's recommended mock patterns for
   platform code

## References

- [Platform Interface Testing Guide](01-platform-interface-testing.md)
- [Method Channel Testing Guide](02-method-channel-testing.md)
- [Error Handling Testing Guide](03-error-handling-testing.md)
- [Async & Stream Testing Guide](04-async-stream-testing.md)

## Next Steps

1. Review this strategy document
2. Start with Priority 1 tests (Document API)
3. Follow the linked guides for proper test implementation
4. Run coverage after each test group to verify improvement
5. Stop when meaningful coverage is achieved - don't chase 100%
