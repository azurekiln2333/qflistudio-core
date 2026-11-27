# Terminal output failure verification provenance

The original generated capture files in this directory are intentionally omitted from the current source tree. Their original bytes remain recoverable from the verified external migration snapshot and the Git objects listed below. The preservation snapshot's root manifest is `D:/MyNewProjects/_migration-backup/qflistudio-core-20261127/snapshot-20261127T062635Z/manifest.json`; coordinator reports bundle SHA-256 `104A7192E63C19DE09486DEC5ACBF2AAA77C44600FF788BCF343828A08A5C69A` verified complete.

## Durable verification summary

The adjacent `../terminal-output-errors-20261026.md` records the 2026-10-26 focused terminal lifecycle result: format, scoped analysis and all 47 terminal widget tests (36 existing and 11 new) passed. The run was host SDK-focused, with exact child jobs terminal and handles closed. The publication budget was exceeded; early compiler/fixture attempts failed and remain non-acceptance evidence. Exceptional exit futures remain unproven, and the result does not establish OHOS packaging, device behavior, or full-product acceptance.

## Original capture provenance

Every listed raw capture was present in the preservation manifest as `preserved`; its size and SHA-256 below identify its original bytes. In Git history, these paths were last recorded by commit `c3f67def86a5dd1a60d09be24006fbcec76db7e8` (`fix(terminal): retain ownership through output failures`). The blob IDs make the historical bytes independently addressable in that commit.

| Original path | Bytes | SHA-256 | Git blob |
| --- | ---: | --- | --- |
| `analyze.stdout` | 96 | `2b093dcc0a0aa28209adc60ecbc9066f150d806f60f776dfdfab0dd1b484d1b2` | `7e2a78e48a75ee09c8b2ed3eec5445b11d96555f` |
| `analyze.stderr` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` |
| `format.stdout` | 47 | `40f77278b207e7b34e8996c0fe9c582929dad3049f45062297f6b58782fab9b8` | `32aa0e5672f2e9c9176942c2002a2c37508e1187` |
| `format.stderr` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` |
| `report.json` | 2873 | `02c923f93925031685ae2c7ecafb0b5475e6a76af9b81d628ded9a31a90730d5` | `d6095aa0271ba2322c2864edf67b06e9a07ec237` |
| `tests.stdout` | 3338 | `57b5c19421d221fc82019d7370906d57ee710aa1d54e2b5614aa7ec62d2e9f07` | `548c47dc00921673f1bc499fe86e27dda3dfc4d0` |
| `tests.stderr` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` |

The hashes were read from the preservation manifest and independently matched to the source files before removal. Raw capture content is not repeated here; use the specified snapshot or Git blob when byte-for-byte recovery is required.
