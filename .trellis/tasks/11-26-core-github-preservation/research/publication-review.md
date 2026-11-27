# Static publication review

Date: 2026-11-27. Reviewer: Herdr `w63:p5`, resumed `trellis-check` worker. Baseline: `476a30acee21dc486ee2849dd8064a7be665e4d5`; the migration candidate is uncommitted. Sole write scope: this report.

## Final disposition — frozen

**Bounded static review: candidate-ready; hosted checks and publication remain pending.** The repaired branch manifest and excluded-fixture artifact pass the targeted checks below, and the final documentation prose has been re-read against the coordinator's frozen hashes. No bounded static publication blocker remains. This does not grant publication permission, establish hosted validation, imply feature adoption, target parity, or cleanup acceptance.

## Evidence and bounded method

Read the parent `check.jsonl` references, then parent and preservation-child PRD/design/implementation plans. Reused the coordinator-supplied findings from the interrupted review rather than repeating history or semantic scans:

- 18 context manifests / 53 entries / zero unresolved targets.
- Root `AGENTS.md` equals the shared E-drive parent policy after end-of-line normalization.
- No `lib/`, package-manifest or `tool/` product delta; preserved features remain inert research patches.
- 269 portable document/configuration files had zero matches for the checked high-signal credential signatures. This is a bounded pattern scan, not a guarantee of secret absence.
- Seven WIP patches / 41 derivative paths passed independent hash, size and mapping checks.
- Branch export had 30 refs / 83 commits / 52 artifacts passing hash, size and mapping checks before the final fixture exclusion. Only the affected artifact/metadata and final prose were rechecked in this resumed review.

P4 owns `publication-review-backup.md`; it is a historical checkpoint, not the final publication gate. Its patch-count/hash and bounded credential findings supplement, but do not expand, this review. No whole-feature adoption or semantic-equivalence audit is required to publish inactive recovery derivatives. Original commit histories and intentionally excluded bytes remain in the verified external bundle/snapshots.

## Targeted resolutions

1. **Herdr runtime fixture provenance:** `branch-039-e7f31261900e.patch` contains neither `test/harness_herdr_models_test.dart` nor `test/harness_herdr_platform_test.dart` diff sections. The model fixture's real-output claim and unproven exact IDs/paths/titles/session values are not relabeled synthetic. Both original paths remain recorded in the manifest as changed and excluded; 23 original changed paths = 21 included + two excluded.
2. **Post-exclusion metadata:** the branch manifest parses successfully and retains 30 refs / 83 commits / 52 artifacts. The affected commit and artifact agree on derivative patch ID `581df5505cbdc5c1276e788ec6a98f37252f0dbb`; original patch ID `29a0f00a7bbc903ecffa8d0a2cdc55a3b1387a64` is separately labeled. The artifact's bytes, SHA-256 and filename agree with the manifest. The transient malformed JSON seen by P4 was replaced, not accepted.
3. **Portable context follow-up:** P3's two frozen hashes match. Read-only ignore queries confirm direct/nested task-research stdout/stderr and the two named JSON capture classes are ignored, while research Markdown and patches remain eligible. The backend index names both `re_editor` and `xterm` vendor overrides. The raw-capture provenance summaries retain original commit/blob/hash identities without repeating captures.
4. **Portability source freeze:** all four byte identities in `../../11-26-core-cloud-ci-policy/research/portability-review.md` still match. That report clears static source review only; formatting, analysis, complete suites, matrix execution and screenshots remain hosted-pending. No new review of the four source files was performed here.
5. **Cloud/consumer qualifications:** `coverage.md` distinguishes successful App run `45922692530` at `76b8a1580ae455b8157cc69f4929178eb402179f` (18 verification/package jobs successful; publication skipped) from the unvalidated core candidate. Native/intermediate provenance, retention, signing and device-install boundaries remain incomplete. `core-consumers.md` distinguishes SQL's declared alternate SDK from unproven executed revision and requires a hosted consumer rerun with both vendor overrides. Publication must use the shared push gate, not a direct push, and remains subject to the core-last hold below.
6. **Final preservation prose freeze:** re-read the changed ledger/recovery prose and verified the three coordinator-supplied final hashes. The ledger distinguishes selected inert text derivatives from exact unpublished commit history in the external bundle, no longer infers missing features from non-ancestry, and points to the now-present branch README and recovery guide. It accounts for the seven WIP artifacts separately from the branch collection. Semantic/adoption review remains deferred, not a migration acceptance blocker.

## Reviewed byte identities (SHA-256)

| File | Bytes where applicable | SHA-256 |
| --- | ---: | --- |
| `11-27-core-preserved-followups/research/branches/branch-patch-manifest.json` | 136714 | `F66D43ED77E6D4FC799B35EFBCAA731B3CCD08D2B0684718ABADB111267662B3` |
| `11-27-core-preserved-followups/research/branches/branch-039-e7f31261900e.patch` | 190767 | `724EBF9523BFCDE50890FE3149CA7232C10D3A53A8B83FA458011C2C001EAE3E` |
| `11-26-core-github-preservation/research/branch-dispositions.md` | — | `E725B5377C752EAC64B003901A35B8B184D0CFC75EEB8EFD241F95CC9EBE9B73` |
| `11-27-core-preserved-followups/research/README.md` | — | `37F6B9312CFBAD0484296EC937FC3989A0166ABE09CED48A5D1BFA06C8DDF9E6` |
| `11-27-core-preserved-followups/research/branches/README.md` | — | `3C29432CDB3F0011EC6DC9381FF5F1AF3C59FB538F7A8B45500804513B138D39` |
| Root `.gitignore` | — | `D102D3591E9220D655FADB5B6BA513AE2B6B5192EDF933D4B6D4F11E8B525215` |
| `.trellis/spec/backend/index.md` | — | `D78F6D3147BF6F7B29AB18CC5CEF7A93FA2848324947CF1E6DE72EEF055BAF5A` |
| `11-26-core-cloud-ci-policy/coverage.md` | — | `F021A4C7CD0F3C76EAC9B01551F669CEAF394324407CDB9549457B591D1DA6F2` |
| `.trellis/spec/backend/core-consumers.md` | — | `167007DB630CF64D5BCDE54F7690C202F92E6BCE3F4B29B71D2CFDDB77589103` |

Task paths in this table are relative to `.trellis/tasks/`. The final coordinator-frozen documentation identities match; the branch manifest and branch-039 artifact identities remain unchanged. This report is now frozen. Changes outside the listed/referenced identities require targeted re-review.

## Finite remaining gates

- **Core-last publication hold:** no push request until brain explicitly confirms that all other repositories are done (`done.json`). Continue preparation only until that confirmation; this signoff does not override the hold.
- Coordinator reviews the actual staged tree/allowlist, manifest targets and content/privacy delta, and prepares a clean fast-forward candidate. Only after the core-last hold is released may that exact SHA be submitted through the shared gate; verify its result plus fresh GitHub advertisement. This reviewer does not stage, commit, push or mutate refs.
- GitHub-hosted formatting, analysis, complete suites for canonical/legacy/relocated layouts, both negative modes and screenshots must pass on the exact candidate, with immutable run/job/artifact evidence. Existing baseline/App runs cannot substitute.
- Final source/GitHub/target equality, target acknowledgement, native/package gaps and owner-authorized cleanup remain separate acceptance gates. Retain external backups, linked worktrees and WSL storage.

No agents were spawned. No local build, test, formatter, analyzer, dependency/SDK operation, artifact download, WSL action or Git mutation was performed. Coordination used Herdr; other workers' files were not edited.
