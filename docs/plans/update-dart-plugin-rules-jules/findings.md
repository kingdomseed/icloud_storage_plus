# Findings & Decisions
<!-- 
  WHAT: Your knowledge base for the task. Stores everything you discover and decide.
  WHY: Context windows are limited. This file is your "external memory" - persistent and unlimited.
  WHEN: Update after ANY discovery, especially after 2 view/browser/search operations (2-Action Rule).
-->

## Requirements
<!-- 
  WHAT: What the user asked for, broken down into specific requirements.
  WHY: Keeps requirements visible so you don't forget what you're building.
  WHEN: Fill this in during Phase 1 (Requirements & Discovery).
  EXAMPLE:
    - Command-line interface
    - Add tasks
    - List all tasks
    - Delete tasks
    - Python implementation
-->
<!-- Captured from user request -->
- Update repo rules to align with current Flutter/Dart plugin guidance.
- Add a Jules setup script modeled after `mythicgme2e/scripts/jules_setup.sh`.
- Research latest Flutter AI rules and plugin patterns.

## Research Findings
<!-- 
  WHAT: Key discoveries from web searches, documentation reading, or exploration.
  WHY: Multimodal content (images, browser results) doesn't persist. Write it down immediately.
  WHEN: After EVERY 2 view/browser/search operations, update this section (2-Action Rule).
  EXAMPLE:
    - Python's argparse module supports subcommands for clean CLI design
    - JSON module handles file persistence easily
    - Standard pattern: python script.py <command> [args]
-->
<!-- Key discoveries during exploration -->
- Flutter AI rules page provides a rules template in multiple sizes (rules.md, rules_10k.md, rules_4k.md, rules_1k.md) and recommends adapting to each editor's rules file format.
- Flutter AI rules page lists common rule file names per tool (CLAUDE.md, AGENTS.md, .github/copilot-instructions.md, .instructions.md, .junie/guidelines.md, .agent/rules/<rule-name>.md) and notes support is evolving.
- Flutter plugin docs emphasize package types and federated plugins, and recommend FFI packages (flutter create --template=package_ffi) for bundling native code since Flutter 3.38.
- Flutter plugin docs call out plugin packages (Dart API + platform implementations) and distinguish FFI packages vs legacy FFI plugin packages.
- Flutter AI rules page shows tool-specific limits (e.g., Copilot ~4k chars) and notes page last updated 2026-01-22.
- Federated plugin structure is defined as app-facing interface + platform interface + platform implementations, with endorsed vs non-endorsed implementations.
- plugin_platform_interface docs recommend platform implementations extend (not implement) the interface, use PlatformInterface.verify with a token, and use MockPlatformInterfaceMixin for tests; Dart 3 `base` may eventually replace this package.
- Plugin pubspec `flutter.plugin.platforms` map specifies per-platform pluginClass (and package for Android, fileName for web); federated platform packages add `implements`, and endorsed implementations use `default_package`.
- `sharedDarwinSource: true` enables shared `darwin/` sources for iOS + macOS and requires updating podspec dependencies/targets.

## Technical Decisions
<!-- 
  WHAT: Architecture and implementation choices you've made, with reasoning.
  WHY: You'll forget why you chose a technology or approach. This table preserves that knowledge.
  WHEN: Update whenever you make a significant technical choice.
  EXAMPLE:
    | Use JSON for storage | Simple, human-readable, built-in Python support |
    | argparse with subcommands | Clean CLI: python todo.py add "task" |
-->
<!-- Decisions made with rationale -->
| Decision | Rationale |
|----------|-----------|
|          |           |

## Issues Encountered
<!-- 
  WHAT: Problems you ran into and how you solved them.
  WHY: Similar to errors in task_plan.md, but focused on broader issues (not just code errors).
  WHEN: Document when you encounter blockers or unexpected challenges.
  EXAMPLE:
    | Empty file causes JSONDecodeError | Added explicit empty file check before json.load() |
-->
<!-- Errors and how they were resolved -->
| Issue | Resolution |
|-------|------------|
| web.run open failed repeatedly | Proceeded with web.run search snippets for sources |

## Resources
<!-- 
  WHAT: URLs, file paths, API references, documentation links you've found useful.
  WHY: Easy reference for later. Don't lose important links in context.
  WHEN: Add as you discover useful resources.
  EXAMPLE:
    - Python argparse docs: https://docs.python.org/3/library/argparse.html
    - Project structure: src/main.py, src/utils.py
-->
<!-- URLs, file paths, API references -->
- https://docs.flutter.dev/ai/ai-rules
- https://docs.flutter.dev/packages-and-plugins/developing-packages
- https://pub.dev/packages/plugin_platform_interface

## Visual/Browser Findings
<!-- 
  WHAT: Information you learned from viewing images, PDFs, or browser results.
  WHY: CRITICAL - Visual/multimodal content doesn't persist in context. Must be captured as text.
  WHEN: IMMEDIATELY after viewing images or browser results. Don't wait!
  EXAMPLE:
    - Screenshot shows login form has email and password fields
    - Browser shows API returns JSON with "status" and "data" keys
-->
<!-- CRITICAL: Update after every 2 view/browser operations -->
<!-- Multimodal content must be captured as text immediately -->
-

---
<!-- 
  REMINDER: The 2-Action Rule
  After every 2 view/browser/search operations, you MUST update this file.
  This prevents visual information from being lost when context resets.
-->
*Update this file after every 2 view/browser/search operations*
*This prevents visual information from being lost*
