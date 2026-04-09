# Task Plan

## Goal
Document and drive the next combined API-hardening slice for the current Darwin
iCloud storage branch, covering typed errors, metadata semantics, and
download-status normalization in an Apple-aligned way.

## Phases
| Phase | Status | Notes |
| --- | --- | --- |
| 1. Map branch and native code layout | complete | Relevant Darwin files and branch diffs identified |
| 2. Review branch implementation details | complete | Read overwrite/copy replacement, preflight, placeholder, and error paths |
| 3. Compare with senior Swift/iCloud standards | complete | Priorities and anti-patterns distilled |
| 4. Address review follow-ups | complete | Fixed iOS overwrite queueing and tightened helper-test parity |
| 5. Design combined API-hardening slice | complete | User approved the design direction and design sections |
| 6. Write and commit design spec | complete | Spec written and committed to `docs/superpowers/specs/2026-04-09-icloud-api-hardening-design.md` |
| 7. External spec review and revision | complete | Revised through multiple review passes; final external review found no material issues |
| 8. Execute 2.0.0 API-hardening branch work | complete | Implemented Tasks 1-6, verified the full branch, and opened PR `#23` |
| 9. Review PR `#23` comments and merge readiness | complete | Triaged the full review surface, applied cleanup, fixed the two real helper bugs with a cleaner overwrite/copy boundary, then addressed the later doc and `copy()` coordination-error follow-ups locally and rechecked that all PR threads are resolved |

## Errors Encountered
| Error | Attempt | Resolution |
| --- | --- | --- |
