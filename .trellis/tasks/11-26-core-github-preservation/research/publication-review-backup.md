# Publication backup review (bounded static check)

Date: 2026-11-27. Reviewer: assigned backup publication reviewer. Scope: p2 branch-patch/dirty-WIP manifest and README freeze; p3 ignore/portable context freeze. This report does not self-approve the changed Dart portability files; p5's separate review is source review only. No Git mutation, staging, build, test, formatter, analyzer, install, or artifact download was performed.

## Result

The previously identified branch-manifest JSON blocker is repaired, independently confirmed by w63:p5. The repaired manifest is valid JSON with 30 refs, 83 commits, and 52 patch artifacts, at 136,714 bytes and SHA-256 `F66D43ED77E6D4FC799B35EFBCAA731B3CCD08D2B0684718ABADB111267662B3`. This backup reviewer has not repeated parsing or artifact scans.

The coordinator's bounded follow-up states that the `c1625ad65f78bf1d35b0ec9547c3da01c4d8f3e9` `changed_paths` now includes both withheld Herdr test paths. It also separates derivative patch ID `581df5505cbdc5c1276e788ec6a98f37252f0dbb` from original patch ID `29a0f00a7bbc...`; the branch-039 patch SHA-256/size remains unchanged. The repaired c162 fields and branch-039 were independently parsed/checked by w63:p5; this backup reviewer performed no new scan.

P2 is still completing the branch ledger/README bounded documentation freeze. Therefore this backup report records the corrected manifest status but does not independently clear all publication staging gates. Do not stage until P2 provides the final frozen documentation identities and the coordinator completes the candidate-tree checks.

## Bounded manifest/hash evidence

- Baseline recorded in branch manifest: `476a30acee21dc486ee2849dd8064a7be665e4d5`.
- README: `.trellis/tasks/11-27-core-preserved-followups/research/README.md`, 5,010 bytes, SHA-256 `1f5bdb407cdd04ddf4d376b4887b594a7d55f1edefd19041e6ee7fd32a8803bf`.
- Branch manifest (historical pre-repair snapshot): `.trellis/tasks/11-27-core-preserved-followups/research/branches/branch-patch-manifest.json`, 136,993 bytes, SHA-256 `6f3d40b8084fe747e1ac0fa36f37fbff2fa2acdf14686346c3fa82479ed65afe`. The repaired manifest independently checked by w63:p5 is 136,714 bytes, SHA-256 `F66D43ED77E6D4FC799B35EFBCAA731B3CCD08D2B0684718ABADB111267662B3`, and retains 30 refs, 83 commits, and 52 patch artifacts.
- The 52 branch patch files were checked against the manifest's listed SHA-256 and byte counts: 52 present; no mismatch observed before the manifest became malformed. This verifies artifact bytes against recorded entries, not the validity/completeness of every semantic disposition.
- Dirty-work manifest: `.trellis/tasks/11-27-core-preserved-followups/research/wip-patch-manifest.json`, 14,805 bytes, SHA-256 `804878e3c421f8ab557bc4c63269312294c4e3b82a44f560cc6753106ee13226`. Its seven patch entries match their listed SHA-256 and byte counts; together they account for 41 files / 397,018 bytes.
- Root-WIP and branch disposition ledgers remain the evidence for their own scopes; this review did not replay history or re-audit ancestry.

## p3 ignore/portable-context boundary

- `.gitignore` SHA-256 `d102d3591e9220d655fadb5b6ba513ae2b6b5192edf933d4b6d4f11e8b525215`.
- `.trellis/spec/backend/index.md` SHA-256 `d78f6d3147bf6f7b29ab18cc5cef7a93fa2848324947cf1e6de72eef055baf5a`.
- The ignore file does not blanket-ignore `.trellis/**/research/`; it has narrow patterns for `.stdout`, `.stderr`, `report.json`, and `root-terminal-observation.json` in task research. Markdown and patch files are not covered by those raw-capture patterns. This supports keeping durable research/patch derivatives eligible for version control while omitting the named captures.
- The backend index now points to the consumer dependency contract mentioning both `re_editor` and `xterm`. Portable-context files are selectively allowlisted under `.agents`, `.codex`, and `.pi`; user-level trust/auth and runtime/session state are not intended for publication. These are static path/rule observations, not a complete content or credentials certification.
- Bounded credential-pattern search over the 59 patch files (52 branch patches plus seven WIP patches) found no matches for the checked private-key, common GitHub-token, AWS access-key, JWT-shaped, or URL-user-info patterns. This does not certify arbitrary secrets, all 59 patch semantics, other task documents, or the complete staged candidate. A staged-tree content/privacy scan remains required by the coordinator.

## Remaining gates

1. P2 completes and freezes the branch ledger/README with final artifact identities. The repaired branch manifest has bounded independent confirmation from w63:p5; this backup reviewer has not repeated parsing or hash scans after that repair.
2. Coordinator confirms the final staged filenames/tree and performs its required publication content/privacy and manifest-target checks.
3. All execution validation, including changed-Dart formatting and portability CI, remains GitHub-hosted and pending. No local validation is claimed here.

Only this backup report was written by this reviewer. No sibling source/artifact or Git state was modified.
