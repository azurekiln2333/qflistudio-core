# Research: OHOS native ABI consumer contract

- Query: Did Core's 1ae4674 wave introduce qfli_git, and which owner should select an arm64-only HAP when a dependency supplies both native ABIs?
- Scope: Core source and two immutable GitHub manifest reads; primary Huawei documentation. No plugin/sibling source scan, Git mutation, product execution, artifact download or native inspection.
- Date: 2026-11-28

## Findings

### Core dependency did not change

GitHub Contents API reads of `pubspec.yaml` at both immutable Core revisions show the same dependency at lines 29-32:

- Baseline `476a30acee21dc486ee2849dd8064a7be665e4d5`, manifest blob `66fbd3089c1c915659782d84cb5f3eb979b25cba`.
- Wave `1ae4674a4b153701b0c3b3ff04b1a1b77a318611`, manifest blob `ad088eb5dcaac2e5b0fdb77afdd5bdaa02f385f2`.
- Both select `qfli_git` from `https://github.com/azurekiln2333/qflistudio-git.git` at `697291a27818612ae9dc53d83d4f99fa5887908e`.
- The relevant changed declaration is xterm: baseline line 34 selects hosted `^4.0.0`; wave lines 34-35 select `vendor/xterm` directly. qfli_git was neither added nor repinned by this wave.

This rules out the specific claim that Core newly introduced this dependency between the two pins. It does not prove that consumer lock resolution, dependency preparation or native packaging inputs stayed identical across the consumer's runs.

### Existing preparation does not select native ABIs

`tool/ci/prepare_flutter_core.py:17-20` restricts its source target and scan roots. Lines 59-77 validate the Flutter SDK revision/flavor; lines 80-119 validate source and may replace only the reviewed Huawei login view in official mode. OHOS mode preserves that view's bytes. There is no HAP/HAR/ABI or native-library mutation in this script.

Related contract: `.trellis/spec/backend/core-consumers.md`, sections 6 and 8, requires resolved vendor paths and exact SDK preparation, and explicitly excludes native-package acceptance from its smoke claims. `research/consumer-fixes.md` likewise covers filter layout and Note compilation, not native ABI selection.

### Build ABI and packaged dependency ABI have distinct controls

Huawei's V13 C++ configuration documentation defines `externalNativeOptions.abiFilters` as a native build setting, while `nativeLib.filter.excludes` controls which `.so` files enter the application package. Its example retains an arm64 build setting and separately excludes x86_64 `.so` paths. The V13 build-profile documentation explicitly describes nativeLib filtering of HAR dependency resources. Current C++ documentation also demonstrates selecting libraries from mixed-ABI HAR inputs into a HAP.

Therefore, an arm64 CMake ABI setting alone is not evidence that every prebuilt HAR library has been excluded from packaging. This is a documented configuration distinction, not a verified reproduction of Dart's exact Hvigor pipeline.

### Smallest ownership-correct candidate

The Dart app owner should retain the arm64 native build setting and the strict package inspector, then apply a packaging filter only to the intended arm64 product/target. A narrow candidate is `nativeLib.filter.excludes: ["**/x86_64/libqfli_git.so"]`; a product explicitly restricted to arm64 can instead exclude `"**/x86_64/*.so"` as the documented whole-ABI rule. Preserve existing filters when composing this change. Place it in the selected target's configuration when other targets still need x86_64; Huawei documents target-specific `config.buildOption.nativeLib.filter`.

Do not remove qfli_git from Core, change its immutable pin speculatively, delete x86_64 support globally from the plugin, or weaken the HAP inspector. The plugin owner's responsibility is a portable multi-ABI dependency; the app's target configuration selects its deliverable architecture. Escalate a plugin defect only if retained exact inputs show packaging controls are ignored or the advertised package structure is wrong.

Required hosted acceptance remains actual arm64 native library presence, absence of the forbidden x86_64 library/ABI in the final arm64 HAP, and unchanged strict inspector success. No such rerun was executed here.

## Files found

- `pubspec.yaml:29` — immutable Git dependency and direct vendored xterm declaration.
- `tool/ci/prepare_flutter_core.py:80` — SDK/source-only runner preparation boundary.
- `.trellis/spec/backend/core-consumers.md:60` — official/OHOS consumer preparation and acceptance limits.
- `.trellis/tasks/11-26-github-cloud-workspace-migration/research/consumer-fixes.md:29` — previously reviewed Note dependency/compiler repair.

## External references

- GitHub API: `repos/azurekiln2333/qflistudio-core/contents/pubspec.yaml?ref=476a30acee21dc486ee2849dd8064a7be665e4d5` and the same endpoint at `1ae4674a4b153701b0c3b3ff04b1a1b77a318611`.
- Huawei V13 C++ configuration: `https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V13/ide-hvigor-cpp-V13/`.
- Huawei V13 build profile: `https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V13/ide-hvigor-build-profile-V13/`.
- Huawei current C++ configuration: `https://developer.huawei.com/consumer/en/doc/HarmonyOS-Guides/ide-hvigor-cpp/`.
- Huawei V13 target configuration: `https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V13/ide-customized-multi-targets-and-products-guides-V13/`.

## Caveats / Not Found

The reported Dart run `46047966414`, job `140671879891`, consumer SHA `2d3d12ea055397c2040bd553687f2ad6ff7b5a1d`, HAP contents, arm64-only entry setting, and plugin's two packaged ABIs are owner-supplied evidence, not re-fetched or independently extracted here. Dart already owns plugin/config tracing. No Core native ABI selector or preparation mechanism was found in the bounded manifest/script/consumer-contract scope. Actual Hvigor version and merged target configuration must be checked by that owner before adopting the candidate.
