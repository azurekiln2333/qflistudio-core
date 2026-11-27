# Enforce cloud-only verification and audit platform CI

## Goal
Make future core work and product consumption use cloud builds/tests, with explicit evidence for six-platform native/Flutter/package coverage.

## Requirements
Own parent R4-R5/R10. Version no-local-build/test/install/SDK/bootstrap/artifact-download instructions in AGENTS and Trellis; cloud runners perform verification. Preserve the core package name qfli_studio_core and coordinate target folder/legacy CI aliases. Audit core-check plus product workflows for Windows/Linux/macOS/iOS/Android/OHOS, including native/Flutter intermediate reuse and final installable packages.

## Dependencies and ownership
Final validation/pins depend on preservation's integrated candidate after wsui handoff. Source root had no workflow, so inspect actual integrated remote state before edits. App/native workflow changes belong to their own owners through Herdr; core directly owns core-check/policy and coordination. No self-hosted local execution.

SQL w62:p1 owns the shared parent AGENTS.md convenience rule; core must version its own repository rules. App w65:p1 owns six-platform app packaging. Current published core evidence covers Flutter-OHOS 3.41.10-ohos-1.0.1 at adaf911c35c9136a7d18fc424d714c9ec7724e60 on Ubuntu. Rust's different SDK candidate and official Flutter consumer patches remain unvalidated for the final core candidate; never generalize the existing core-check success into consumer or six-platform compatibility.

Confirmed portability defect at baseline 476a30a: test/interop_arkts_contract_test.dart:16 uses Directory.current.parent; :78 names qfli_studio_core for its own source and :21 throws on the absent path before test assertions run. Canonical qflistudio-core checkouts therefore need a core-owned fix. The same reader requires app qflistudio and Java qfli_java fixture aliases. App run 45897522770 was reported failing this load; core independently inspected the exact pinned test. App may retain the immutable pin with an explicitly recorded temporary CI path adaptation while the permanent core fix is pending.

## Acceptance
- New clones expose the cloud-only rule and portable instructions to all agents.
- Final core candidate has passing required cloud checks with exact run/SHA evidence.
- The interop source contract suite resolves its own package independent of checkout-folder spelling and explicitly resolves real app/Java fixture roots. Validate the canonical layout and supported legacy layout on GitHub, retain every contract assertion, and fail clearly when required fixture input is missing. Record any consumer runner-only adaptations separately from unmodified-source validation.
- Six-platform matrix records actual workflow/owner/input/stages/intermediates/package/signing/run/artifact evidence; unresolved gaps stay open.
- App owners receive final immutable core SHA and validated path/SDK compatibility contract.
- No build/test output or dependency installation occurred locally.

## Out of scope
Changing runtime product behavior merely to satisfy naming, storing generated artifacts in Git, fabricating signing success or disabling checks to claim success.

