# iCloud Write Path Reset Design

Date: 2026-04-18
Repo: `icloud_storage_plus`
Status: Approved for implementation, Part 1 contract locked

## Purpose

Reset the `writeInPlace` rewrite from first principles.

The current branch mixed together feature work, architecture repair,
error shaping, test churn, and packaging drift. That made it hard to tell
which changes express real plugin contracts and which changes only defend
against imagined misuse or preserve branch-local abstractions.

This reset adopts a strict contract-first standard:

- keep public plugin names unless the name no longer describes the truth
- prefer direct Foundation behavior over speculative native preflight
- treat Swift Package Manager as the primary source of truth
- keep CocoaPods working while it remains supported, but do not let it
  dictate architecture
- review nearly every touched native method with a senior Swift standard:
  keep, simplify, merge, or delete

## Problem Statement

The production problem is clear.

`writeInPlace` still turns recoverable iCloud states into failures. The
rewrite branch tried to fix that, but it also introduced design drift.

The core drift looks like this:

- preflight guards expanded beyond real plugin contracts
- observer-path conflict logic was reused for write-path save semantics
- helper structure became more important than clear boundaries
- shipping concerns drifted away from the actual source of truth

The reset does not start from "how do we save the branch?" It starts from
"what does the plugin actually promise, and what is the smallest honest
Swift design that delivers it?"

## Reset Scope

This reset covers the native Swift surface involved in overwriting an
existing item and the boundaries that shape that behavior for Dart.

In scope:

- `writeInPlace` overwrite behavior
- download-before-write behavior for non-current ubiquitous items
- conflict handling for write-path saves
- observer-path conflict handling only where the write-path reset must keep
  existing observer call sites compiling and semantically separate
- native error shaping that Dart relies on
- SPM layout and tests
- CocoaPods compatibility validation

Concrete native file scope for the method audit and semantic rewrite:

- `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/`
  `CoordinatedReplaceWriter.swift`
- `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/`
  `CoordinatedReplaceWriter.swift`
- `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/`
  `ConflictResolver.swift`
- `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/`
  `ConflictResolver.swift`
- the iOS and macOS plugin entrypoints only at the call sites that invoke the
  overwrite path and map native errors to Dart-visible failures

If Part 2 extracts dedicated foundation conflict helpers, they are target
extraction files for the reset rather than baseline requirements. In the
current baseline worktree, the observer conflict winner-selection logic still
lives inside the platform `ICloudDocument` implementations.

The reset does not authorize a broad repo-wide Swift cleanup.

Out of scope unless a later design change requires it:

- consumer app behavior outside the plugin
- unrelated plugin cleanup
- broad API redesign of public Dart method names
- architecture changes driven only by CocoaPods convenience

## Design Principles

### 1. Contract First

Every behavior in the native layer must justify itself as a real plugin
contract.

A valid contract must satisfy all of these:

- it describes something the plugin explicitly promises to callers
- Foundation, Flutter, or the packaging layer does not already own it
- it can be tested at the plugin boundary
- a consumer would care if it broke in production

If a behavior does not pass that test, it should not anchor design.

### 2. Public Stability, Internal Freedom

Preserve public plugin method names and Dart-facing behavior when the names
still describe the truth.

Internal Swift helpers are free to change, merge, split, or disappear.

The reset favors consumer stability. It does not preserve internal names or
shapes for sentimental reasons.

### 3. No Speculative Preflight By Default

The native layer should not proactively guard against every strange input.

Preflight checks survive only if they protect a real plugin promise that the
OS layer would not protect in a consumer-meaningful way.

"This yields a slightly nicer earlier error" is not enough.

### 4. Different Flows Stay Different

Observer conflict handling and explicit overwrite handling start as separate
flows.

They may share code only if they have the same winner, the same failure
semantics, and the same cleanup semantics.

Until that is proven, they remain separate.

### 5. SPM Is Primary

Swift Package Manager is the primary source of truth for source layout,
native tests, and module organization.

CocoaPods remains a supported compatibility path while the plugin still
declares it, but it does not control architecture.

### 6. Fresh Branch Is The Default

The default execution mode for this reset is a fresh branch from `main`.

Reuse from the current rewrite branch requires explicit justification on a
case-by-case basis. The current branch is reference material, not trusted
architecture.

## Working Definitions

### Valid Helper

A helper survives only if it does at least one of these:

- encodes a real domain rule
- preserves a meaningful boundary such as error mapping or coordinator
  bridging
- reduces duplication that would otherwise obscure correctness
- makes a real system workflow easier to reason about

A helper should be deleted if it is mainly:

- a one-line wrapper over Foundation with no semantic value
- a place to park speculative checks
- a seam created to support a branch-local abstraction
- a wrapper that is less clear than inline code

### Acceptable Preflight

A preflight check is acceptable only if:

- it prevents a known bad operation the plugin wants to shape differently
  from the OS
- it produces a stable, consumer-meaningful outcome
- that outcome belongs in the plugin contract

Otherwise, let the underlying coordinated file operation fail naturally.

### Valid Test

A test survives only if it proves one of these:

- a public or Dart-visible contract
- a critical native boundary
- a real production regression
- a concurrency or packaging invariant that could hurt users

Tests that mainly prove helper existence or preserve branch structure should
be rewritten or deleted.

## Known Example: File vs Directory Guard

The current branch contains a helper that checks whether the destination URL
is a directory before the overwrite path proceeds.

That kind of check is a good example of the reset rule.

The condition can happen. A caller can point at a directory path. The real
question is whether the plugin should own that distinction as part of its
contract.

Under this reset, the answer is "no" unless we can name a concrete
Dart-facing promise that depends on it. A helper that exists only to be more
protective than the OS should be removed.

This document therefore treats directory/file guards as presumptively
invalid until justified.

The contract question is not whether directory destinations can exist. They
can. The question is whether the plugin must detect that case proactively or
whether it can map the resulting failure into a stable Dart-visible category
without preserving a dedicated speculative preflight helper.

Part 1 resolves this by locking the Dart-visible `invalidArgument` / `E_ARG`
outcome while leaving the implementation free to use either a minimal
validation seam or a mapped OS failure, whichever stays more honest.

## Target Contracts

### `writeInPlace`

`writeInPlace` should preserve its public name and public API shape if the
name remains truthful.

Its contract should be:

- if the destination does not exist, the overwrite path reports that and
  exits without pretending work happened
- if the destination is a ubiquitous item that is not locally current, the
  plugin attempts to make it locally available before writing
- if the destination is in a recoverable conflict state, the plugin attempts
  to recover instead of refusing immediately
- if the overwrite still cannot complete, the plugin surfaces a typed error
  that Dart can map reliably

This contract deliberately says nothing about speculative native preflight.

`writeInPlaceBytes` shares the same overwrite contract and differs only in the
replacement payload type.

### Write-Path Outcome Table

The reset must lock these Dart-visible outcomes before implementation.

| State | Native behavior target | Dart-visible category/code | Retryable |
|---|---|---|---|
| Destination missing | Overwrite path reports no handled existing destination; caller falls back to normal create/write path or typed not-found behavior, depending on the entrypoint's existing contract | No new overwrite-only category; preserve existing plugin behavior per entrypoint | Existing behavior |
| Destination path is file-centric but resolves to an existing directory | Preserve a stable invalid-argument outcome; do not allow this to degrade into opaque unknown-native noise | `invalidArgument` / `E_ARG` | No |
| Destination is a ubiquitous item that is not locally current | Attempt download/localization before overwrite | No error if recovery succeeds | N/A |
| Destination download cannot complete before write | Surface stable not-downloaded or timeout outcome based on the actual failing condition | `itemNotDownloaded` / `E_NOT_DOWNLOADED` or `timeout` / `E_TIMEOUT` | Yes |
| Destination has unresolved conflicts but recovery succeeds | Attempt recovery, then continue overwrite | No error if recovery succeeds | N/A |
| Conflict recovery fails before replacement write | Surface conflict failure with stable mapping and underlying native details | `conflict` / `E_CONFLICT` | No |
| Coordination fails | Surface stable coordination failure | `coordination` / `E_COORDINATION` | No by default; revisit only if an existing stable mapping proves otherwise |
| Replacement write succeeds but post-write cleanup fails | The user's replacement remains the conceptual winner, but cleanup remains part of honest success so the operation still reports a stable failure | `conflict` / `E_CONFLICT` | No |
| Unclassified native failure | Preserve structured fallback behavior | `unknownNative` / `E_NAT` | No |

Notes:

- This table intentionally locks the category/code pairs already exposed by
  `lib/models/exceptions.dart` and the current native `FlutterError` mapping.
- The destination-directory row preserves Dart-visible stability without
  committing the implementation to a dedicated native preflight helper.
- The destination-missing row stays tied to the existing entrypoint contract;
  the implementation plan must state that exact behavior explicitly instead of
  inventing a new overwrite-specific category.
- `downloadInProgress` does not survive Part 1 as a terminal write-path
  outcome. The write path should wait for localization and surface only the
  locked `E_TIMEOUT` or `E_NOT_DOWNLOADED` failures if recovery does not
  complete.

### Observer Conflict Handling

The observer path may still use a "pick a winner among existing versions"
strategy if that remains correct for document-presentation callbacks.

That does not make it the right model for a user save.

The reset does not redesign observer behavior beyond keeping the surviving
observer call sites correct if a shared helper changes shape.

### Copy Over Existing Destination

Copy-path behavior remains separate unless a later design explicitly proves
that it should converge with overwrite behavior.

The reset assumes separation by default.

## Platform Alignment

iOS and macOS must preserve the same write-path contract and Dart-visible
error outcomes for any behavior changed by this reset.

Implementation details may differ only when platform APIs force the
difference. Contract divergence is not allowed.

## Architectural Correction

### The Write Path Must Treat The User's Replacement As The Winner

This is the central design rule.

In an explicit overwrite/save operation, the user's replacement content is
the intended winner. Conflict handling exists to make that write possible and
to clean up the state around it. Conflict handling does not define the final
content.

This is why the branch's current design is not trusted. A flow that first
restores the latest conflict version into the destination and only then tries
to apply the user's replacement is not conceptually right for a save. It can
also create bad failure modes if cleanup fails after an old conflict version
has already been restored.

The write path must therefore be re-derived from first principles, not
patched.

Part 1 locks the ordering explicitly: replacement write first, post-write
conflict cleanup second. If cleanup fails after the replacement write, the
operation still reports `conflict` / `E_CONFLICT`, but the user's replacement
remains the conceptual winner.

### The Coordinator Bridge Must Be Honest

If `NSFileCoordinator.coordinate(...)` is blocking and synchronous, the
design must admit that. The native bridge should not pretend a true async
accessor exists if the underlying work must complete inline.

The outer API may remain async if it is bridging a blocking native operation
back to the caller. The inner accessor should reflect the actual Foundation
contract.

### Error Mapping Must Stay Minimal And Stable

The Dart layer depends on stable error categories. That is a real boundary.

The reset should keep native error shaping only where Dart actually needs a
stable domain, code, or marker. It should not expand error shaping into a new
source of speculative behavior.

## Method Audit Standard

For each touched Swift method in the scoped native files above, apply this
audit:

1. Why does this method exist?
2. Is that responsibility real?
3. Is the signature honest about sync, async, and throwing behavior?
4. Is the abstraction clearer than inline code?
5. Is it preserving accidental architecture?
6. Would a senior Swift engineer write this today from an empty file?

Each method gets one classification:

- Keep
- Simplify
- Merge
- Delete

No method survives by inertia.

## Reset Map

### Discard By Default

- speculative native preflight guards that do not protect a real contract
- helper structure created mainly to support branch-local abstractions
- tests whose primary job is preserving helper existence
- the assumption that observer conflict resolution is the right save-path
  model

### Keep Only After Revalidation

- the extracted download waiter concept
- the deadlock-free coordination bridge direction
- narrow NSError shaping that Dart actually depends on
- separation between copy-path behavior and overwrite behavior

### Re-Derive From First Principles

- write-path conflict semantics
- method-level keep/delete decisions
- exact failure semantics for overwrite, coordination, cleanup, and recovery
- packaging verification order with SPM primary and CocoaPods secondary

## Replacement Slices

The implementation should not follow the old branch phases. It should follow
these slices.

### Part 1 / Slice 1: Contract Lock And Method Audit

Write plain-language contracts for each touched public operation and each
critical Dart-visible error category.

Produce a method inventory for the scoped files and classify each touched
method as Keep, Simplify, Merge, or Delete.

Gate:

- no code changes until the contracts are explicit and consistent
- no semantic rewrite until the Dart-visible category/code table is final
- no scope expansion beyond the explicit file inventory without a new design
  decision

### Part 2 / Slice 2: Native Write-Path Reset

Define overwrite semantics from first principles:

- destination missing
- destination nonlocal
- destination conflicted
- coordination failure
- cleanup failure

Gate:

- the user's replacement content remains the conceptual winner for save
  operations
- copy-path behavior remains separate
- observer-path behavior remains out of scope except for compatibility with
  surviving call sites

### Part 2 / Slice 3: Minimal Native Rebuild

Implement only the methods needed to satisfy the contracts.

Gate:

- the Swift code reads like direct, honest Foundation coordination code

### Part 3 / Slice 4: Packaging And Integration Validation

Validate the real shipping paths in this order:

- SPM build and native tests
- Flutter plugin integration and Dart tests
- CocoaPods compatibility while still supported

Gate:

- SPM is the primary success path; CocoaPods remains compatible support

### Part 3 / Slice 5: Behavior Verification

Keep tests that prove contracts, real regressions, concurrency invariants,
and packaging compatibility. Rewrite or delete the rest.

Gate:

- coverage demonstrates behavior, not helper trivia

## Execution Mode

This reset should execute on a fresh branch from `main` by default.

The current rewrite branch remains historical reference only. Reuse from that
branch is allowed only when a specific artifact passes the contract-first
audit and is cheaper to import than to re-derive.

## Success Criteria

The reset is successful when all of these are true:

- public plugin names remain stable unless a name would be dishonest
- `writeInPlace` recovers from recoverable iCloud states instead of refusing
  too early
- write-path save semantics treat the user's replacement as the winner
- speculative native preflight has been removed unless explicitly justified
- touched Swift methods have been audited with keep/simplify/merge/delete
- the touched native file inventory stayed within the scoped write-path
  boundary
- SPM is clean and remains the primary truth
- Flutter integration is clean
- CocoaPods remains compatible while supported
- the surviving tests prove behavior, not branch residue

## Part 1 Resolutions

Part 1 locks these decisions before any Swift rewrite:

- the detailed method inventory and keep/simplify/merge/delete
  classifications live in
  `docs/superpowers/plans/2026-04-18-icloud-write-path-reset-contract-audit.md`
- the write-path cleanup sequence is replacement write first, conflict cleanup
  second
- post-write cleanup failure remains a visible `conflict` / `E_CONFLICT`
  failure rather than a silent success or rollback into old-content-wins
  semantics
- `downloadInProgress` is not a surviving terminal write-path outcome

Remaining execution details belong in the implementation plan:

- the minimum end-to-end integration test needed to prove Dart-visible error
  mapping
- the exact CocoaPods compatibility command set to retain while support
  remains declared

The execution mode is resolved by design default: fresh branch from `main`.
The implementation plan may override that only if it gives a specific reuse
justification.

## Summary

This reset rejects speculative native design and branch-driven inertia.

It preserves public stability where the public truth still matches the
existing names. It treats SPM as primary. It keeps CocoaPods compatible but
secondary. Most of all, it demands a senior Swift audit of the touched native
surface before more code is allowed to accumulate.
