# Blocked-input cancellation verification provenance

The original generated capture files in this directory are intentionally omitted from the current source tree. Their original bytes remain recoverable from the verified external migration snapshot and the Git objects listed below. The preservation snapshot's root manifest is `D:/MyNewProjects/_migration-backup/qflistudio-core-20261127/snapshot-20261127T062635Z/manifest.json`; coordinator reports bundle SHA-256 `104A7192E63C19DE09486DEC5ACBF2AAA77C44600FF788BCF343828A08A5C69A` verified complete.

## Durable verification summary

The adjacent `../supervisor-blocked-input-20261026.md` records the 2026-10-26 focused Windows cancellation-ordering result: immutable format check passed with zero changed files, scoped Flutter analysis passed, and `process_supervisor_test.dart` passed 9/9 including three new pending-input controls. The root observation reports exit code 0, exact owned jobs terminal/empty with handles closed, and no forced cleanup. This evidence does not establish descendant containment, retries after cancellation failure, an OHOS build, or device behavior; see the adjacent research note for limitations.

## Original capture provenance

Every listed raw capture was present in the preservation manifest as `preserved`; its size and SHA-256 below identify its original bytes. In Git history, these paths were last recorded by commit `53b0303e8e8e19462f089a37054b3af446ddc39f` (`fix(process): terminate Windows tree before waiting for input`). The blob IDs make the historical bytes independently addressable in that commit.

| Original path | Bytes | SHA-256 | Git blob |
| --- | ---: | --- | --- |
| `analyze.stdout` | 96 | `f097a65ebeb694c4d591ee50f5539f211e17b837052f4b9b7eecf04e417ebd67` | `04be938c2780f1e08ef34be9d18cba0e03c34d86` |
| `analyze.stderr` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` |
| `format.stdout` | 47 | `48119b7f93f88ac166398c1576d4686ff2163286c1e198494980483fef718e84` | `a5b0a2bae10003f32de23a2c104075387862aefe` |
| `format.stderr` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` |
| `report.json` | 10652 | `527797a6a2e5ecc9767712b067c9e9ea6f4381c2d48124f45ba9387305acd3f0` | `31d22df91fbc6c1823e49673d8bd721fd3841d10` |
| `root-terminal-observation.json` | 610 | `5062e5273834d6de08e333039f66ef9ab192b1fe7f85dc4c2c98177be83f792f` | `bf2295243959287a6401867c5af362dd79f99e3f` |
| `test.stdout` | 791 | `3813f678b49febb811c3bc591239abda972a1b4c4c293ccb3c4934829ecd5356` | `fc2f05fd02604ae90379361a5e8e361c5ffb54e6` |
| `test.stderr` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` |

The hashes were read from the preservation manifest and independently matched to the source files before removal. Raw capture content is not repeated here; use the specified snapshot or Git blob when byte-for-byte recovery is required.
