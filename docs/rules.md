# AGENTS.md

This file provides guidance to AI coding assistants that read `AGENTS.md` (for example, Cursor).

## Project Overview

iCloud Storage Plus is a Flutter plugin that provides comprehensive iCloud integration for iOS and macOS. This fork focuses on improved file coordination using NSFileCoordinator and UIDocument/NSDocument.

## Scope

This repository is a Flutter plugin, not a Flutter app. UI/widget, theming, routing, and app state guidance is out of scope unless you are editing the example app.

## Interaction Guidelines
* **User Persona:** Assume the user is familiar with programming concepts but may be new to Dart.
* **Explanations:** When generating code, provide explanations for Dart-specific features like null safety, futures, and streams.
* **Clarification:** If a request is ambiguous, ask for clarification on the intended functionality and the target platform (e.g., iOS, macOS, web).
* **Dependencies:** When suggesting new dependencies from `pub.dev`, explain their benefits.
* **Formatting:** Use the `dart_format` tool to ensure consistent code formatting.
* **Fixes:** Use the `dart_fix` tool to automatically fix many common errors, and to help code conform to configured analysis options.
* **Linting:** Use the Dart linter with a recommended set of rules to catch common issues. Use the `analyze_files` tool to run the linter.

## Plugin Structure

- **lib/**: Dart API layer
  - `icloud_storage.dart`: Main public API
  - `icloud_storage_platform_interface.dart`: Platform interface definition
  - `icloud_storage_method_channel.dart`: Method channel implementation
  - `models/`: Data models and exceptions
- **ios/Classes/**: iOS native implementation
- **macos/Classes/**: macOS native implementation

## Flutter/Dart Plugin Rules

1. Prefer federated plugin architecture: app-facing API + platform interface + platform implementations.
2. Platform implementations must `extend` the platform interface (do not `implement`) and verify tokens via `PlatformInterface.verifyToken`. Use `MockPlatformInterfaceMixin` in tests that mock the interface.
3. Keep `flutter.plugin.platforms` in `pubspec.yaml` accurate (per-platform `pluginClass`, Android `package`, web `fileName`). For federated packages, use `implements` and endorse with `default_package` where applicable.
4. For native bindings, prefer `flutter create --template=package_ffi` (recommended since Flutter 3.38). Treat `plugin_ffi` as legacy.
5. If iOS + macOS implementations are shared, consider `sharedDarwinSource: true` and move sources to `darwin/`, updating podspec dependencies/targets accordingly.
6. iOS/macOS code must use background queues (avoid blocking main thread).
7. Surface all native errors as typed Dart exceptions.
8. When adding native functionality, update both iOS and macOS implementations.
9. Check iCloud availability with `icloudAvailable()` before operations.

## Package Management
* **Pub Tool:** To manage packages, use the `pub` tool, if available.
* **External Packages:** If a new feature requires an external package, use the `pub_dev_search` tool, if it is available. Otherwise, identify the most suitable and stable package from pub.dev.
* **Adding Dependencies:** To add a regular dependency, use the `pub` tool, if it is available. Otherwise, run `flutter pub add <package_name>`.
* **Adding Dev Dependencies:** To add a development dependency, use the `pub` tool, if it is available, with `dev:<package name>`. Otherwise, run `flutter pub add dev:<package_name>`.
* **Dependency Overrides:** To add a dependency override, use the `pub` tool, if it is available, with `override:<package name>:1.0.0`. Otherwise, run `flutter pub add override:<package_name>:1.0.0`.
* **Removing Dependencies:** To remove a dependency, use the `pub` tool, if it is available. Otherwise, run `dart pub remove <package_name>`.

## Code Quality
* **Code structure:** Adhere to maintainable code structure and separation of concerns (Dart API vs. platform code).
* **Naming conventions:** Avoid abbreviations and use meaningful, consistent, descriptive names for variables, functions, and classes.
* **Conciseness:** Write code that is as short as it can be while remaining clear.
* **Simplicity:** Write straightforward code. Code that is clever or obscure is difficult to maintain.
* **Error Handling:** Anticipate and handle potential errors. Don't let your code fail silently.
* **Styling:**
  * Line length: Lines should be 80 characters or fewer.
  * Use `PascalCase` for classes, `camelCase` for members/variables/functions/enums, and `snake_case` for files.
* **Functions:** Keep functions short and single-purpose (strive for less than 20 lines).
* **Testing:** Write code with testing in mind. Use the `file`, `process`, and `platform` packages, if appropriate, so you can inject in-memory and fake versions of the objects.
* **Logging:** Use the `logging` package instead of `print`.

## Dart Best Practices
* **Effective Dart:** Follow the official Effective Dart guidelines (https://dart.dev/effective-dart)
* **Class Organization:** Define related classes within the same library file. For large libraries, export smaller, private libraries from a single top-level library.
* **Library Organization:** Group related libraries in the same folder.
* **API Documentation:** Add documentation comments to all public APIs, including classes, constructors, methods, and top-level functions.
* **Comments:** Write clear comments for complex or non-obvious code. Avoid over-commenting.
* **Trailing Comments:** Don't add trailing comments.
* **Async/Await:** Ensure proper use of `async`/`await` for asynchronous operations with robust error handling.
  * Use `Future`s, `async`, and `await` for asynchronous operations.
  * Use `Stream`s for sequences of asynchronous events.
* **Null Safety:** Write code that is soundly null-safe. Leverage Dart's null safety features. Avoid `!` unless the value is guaranteed to be non-null.
* **Pattern Matching:** Use pattern matching features where they simplify the code.
* **Records:** Use records to return multiple types in situations where defining an entire class is cumbersome.
* **Switch Statements:** Prefer using exhaustive `switch` statements or expressions, which don't require `break` statements.
* **Exception Handling:** Use `try-catch` blocks for handling exceptions, and use exceptions appropriate for the type of exception. Use custom exceptions for situations specific to your code.
* **Arrow Functions:** Use arrow syntax for simple one-line functions.

## Lint Rules

Include the package in the `analysis_options.yaml` file. Use the following
analysis_options.yaml file as a starting point:

```yaml
include: package:flutter_lints/flutter.yaml

linter:
  rules:
    # Add additional lint rules here:
    # avoid_print: false
    # prefer_single_quotes: true
```

## Code Generation
* **Build Runner:** If the project uses code generation, ensure that `build_runner` is listed as a dev dependency in `pubspec.yaml`.
* **Code Generation Tasks:** Use `build_runner` for all code generation tasks, such as for `json_serializable`.
* **Running Build Runner:** After modifying files that require code generation, run the build command:

```shell
dart run build_runner build --delete-conflicting-outputs
```

## Testing
* **Running Tests:** To run tests, use the `run_tests` tool if it is available, otherwise use `flutter test`.
* **Unit Tests:** Use `package:test` for unit tests.
* **Widget Tests:** Use `package:flutter_test` for widget tests (only for example app changes).
* **Integration Tests:** Use `package:integration_test` for integration tests (only for example app changes).
* **Assertions:** Prefer using `package:checks` for more expressive and readable assertions over the default `matchers`.

### Testing Best Practices
* **Convention:** Follow the Arrange-Act-Assert (or Given-When-Then) pattern.
* **Mocks:** Prefer fakes or stubs over mocks. If mocks are absolutely necessary, use `mockito` or `mocktail` to create mocks for dependencies.
* **Coverage:** Aim for high test coverage on the Dart API layer.
