# Cloud coverage and evidence boundaries

Read from GitHub run/job/artifact metadata on 2026-11-27. No artifact downloads or local product checks were performed.

## Core responsibility

The shared core repository owns source verification, interoperability contracts, layout portability and workbench screenshots. It does not own application installers or native-runtime release packages. Baseline `476a30acee21dc486ee2849dd8064a7be665e4d5` has successful main run `45689025146`, updated `2026-11-25T19:58:10Z`. The two successful jobs are `check` and `screenshots`.

Its immutable SDK is Flutter OHOS `3.41.10-ohos-1.0.1` at `adaf911c35c9136a7d18fc424d714c9ec7724e60`. Fixture inputs are App `69656b4ab14e706e85907ef4c4205d8cd35a1338` and Java `60d97c783f29da767fafe503980812101f6aa61f`. No Rust native-hook override or universal official-Flutter compatibility is implied.

Baseline artifact metadata:

| Artifact | Compressed bytes | Expiry |
| --- | ---: | --- |
| `core-verification-476a30acee21dc486ee2849dd8064a7be665e4d5` | 207797 | 2027-02-23T19:49:50Z |
| `workbench-screenshots-476a30acee21dc486ee2849dd8064a7be665e4d5` | 1527686 | 2027-02-23T19:49:50Z |

These artifacts were not expired at inspection. Their contents were not downloaded. The new migration candidate still requires its own successful canonical/legacy/relocated and negative fixture coverage, complete tests and screenshots. Baseline success cannot satisfy that gate.

## Six-platform application ownership

Owner: qflistudio-next coordinator w65:p1. Final App run `45922692530` at `76b8a1580ae455b8157cc69f4929178eb402179f` is completed/success, updated `2026-11-27T01:36:40Z`, independently read from GitHub metadata on 2026-11-27. Eighteen verification/package jobs passed; `Publish verified release or preview` was skipped. This supersedes the earlier App documentation run `45912697544` at `b052d77aa64d11c2baab686ffefadbe9f3a33156`. The owner retains core baseline `476a30a`, plugin `697291a`, and a temporary legacy-fixture symlink. It does not validate the migration candidate or remove the core-owned portability defect. App's committed cloud-acceptance.json still covers older run `45908020703` at `da74782`; do not conflate these records.

| Family | Successful package jobs | Artifact names, prefix `qflistudio-5.0.14-` | Signing boundary |
| --- | --- | --- | --- |
| Windows | x64 and arm64 installers | `windows-x64`, `windows-arm64` | Owner reports unsigned; no device-install acceptance |
| Linux | x64 and arm64 packages | `linux-x64`, `linux-arm64` | Owner reports unsigned; installation not inspected |
| macOS | x86_64 and arm64 DMG | `macos-x86_64`, `macos-arm64` | Owner reports ad-hoc signing; notarization not established |
| iOS | Unsigned IPA | `ios-arm64` | Explicitly unsigned |
| Android | Release APKs | `android-x86_64`, `android-armeabi-v7a`, `android-arm64-v8a` | Owner reports CI test key; store signing not established |
| OHOS | Unsigned HAP | `ohos-arm64` | Explicitly unsigned |

All listed package artifacts exist and were unexpired in the metadata response, with expiry on 2026-12-11 UTC (14-day retention). Other artifacts include `verification-flutter-core`, `verification-flutter-app`, `verification-java-interop`, `verification-companion-ubuntu-24.04`, `verification-companion-windows-2022`, `verification-windows-assistant`, `git-ios-integration-45922692530` and `qfli-remote-assistant-5.0.14-windows-x64`; nineteen artifacts total. Artifact names and successful upload steps are not content checksums or proof of installation/device behavior. No permanent release retention or physical-device acceptance is established.

Native/Flutter intermediates remain runner/cache/artifact responsibilities of the App and language/native owners. App's current recorded contract builds and packages Flutter within the same job; its owner reports no standalone reusable Flutter intermediate pipeline and no newer final immutable native contract. Core's verification artifacts are logs and screenshots, not native payloads. Complete intermediate provenance, retention and final candidate consumer compatibility must be supplied by those owners through their immutable contracts. This product-line gap remains explicit and is not core six-platform completion. No self-hosted runner, local cache download or local SDK setup is authorized.
