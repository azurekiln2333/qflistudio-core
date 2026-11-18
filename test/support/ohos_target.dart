import 'package:flutter/foundation.dart';

/// The HarmonyOS target of the OHOS Flutter fork.
///
/// Resolved by name so this file also compiles under official Flutter, whose
/// `TargetPlatform` has no `ohos` value. Only the fork defines it at run time,
/// so these tests are meaningful only on the OHOS toolchain.
final TargetPlatform ohosPlatform = TargetPlatform.values.byName('ohos');
