/// HarmonyOS detection that compiles on both Flutter variants.
///
/// The OHOS Flutter fork adds an `ohos` value to `TargetPlatform`; official
/// Flutter does not. Naming that enum value in source breaks every official
/// build of this package until the CI patch script learns the new string, so the
/// checks below compare the enum's runtime name instead. The answer is the same
/// on both variants: the fork reports `ohos` for HarmonyOS, official Flutter
/// never does.
library;

import 'package:flutter/foundation.dart';

/// Whether [target] is the HarmonyOS target of the OHOS Flutter fork.
///
/// Compares the enum name, so it is also correct under
/// [debugDefaultTargetPlatformOverride] in tests.
bool isOhosTarget(TargetPlatform target) => target.name == 'ohos';

/// Whether the running app targets HarmonyOS.
bool get isOhosPlatform => !kIsWeb && isOhosTarget(defaultTargetPlatform);
