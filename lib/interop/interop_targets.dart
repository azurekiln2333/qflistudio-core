/// Which sibling app answers for which language, and what to say when it is
/// not installed.
///
/// The bundle names are observed values from each sibling repository's
/// `ohos/AppScope/app.json5`; they are not derived from the product key. Keep
/// this table the single source of truth so a rename is one edit.
library;

import 'package:path/path.dart' as p;

/// A receiver app and the ability that must answer a request.
class InteropTarget {
  const InteropTarget({
    required this.language,
    required this.bundleName,
    required this.abilityName,
    required this.productName,
    required this.languages,
  });

  /// The language key used on the wire and in project metadata.
  final String language;
  final String bundleName;
  final String abilityName;

  /// Human-readable product name for the install hint.
  final String productName;

  /// Every project language this receiver compiles.
  final Set<String> languages;
}

/// The Studio side's own identity on the wire.
abstract final class InteropStudio {
  /// Bundle name of the Studio app. The receiver allowlists exactly this.
  static const String bundleName = 'com.azurekiln.qflistudio';

  /// Ability that receives response events from a sibling app.
  static const String bridgeAbility = 'InteropBridgeAbility';

  /// Implicit action the receiver uses to start [bridgeAbility].
  static const String bridgeAction = 'action.system.qfli.interop.event';
}

/// Language to receiver map. Ordered by the shared product catalogue.
abstract final class InteropTargets {
  static const InteropTarget java = InteropTarget(
    language: 'java',
    bundleName: 'com.azurekiln.qfli.java',
    abilityName: 'InteropAbility',
    productName: 'QFLIJVMX',
    languages: <String>{'java'},
  );

  static const InteropTarget cpp = InteropTarget(
    language: 'c',
    bundleName: 'com.azurekiln.qfli.cpp',
    abilityName: 'InteropAbility',
    productName: 'QFLIForge',
    languages: <String>{'c', 'cpp'},
  );

  static const InteropTarget python = InteropTarget(
    language: 'python',
    bundleName: 'com.azurekiln.qfli.pyflow',
    abilityName: 'InteropAbility',
    productName: 'QFLIPyFlow',
    languages: <String>{'python'},
  );

  static const List<InteropTarget> all = <InteropTarget>[java, cpp, python];

  /// Bundle names the Studio bridge answers. Anything else is dropped.
  static final Set<String> allowedCallerBundles = <String>{
    for (final target in all) target.bundleName,
  };

  /// Receiver for [language], or null when no sibling app owns it.
  static InteropTarget? forLanguage(String language) {
    final key = language.toLowerCase().trim();
    for (final target in all) {
      if (target.languages.contains(key)) return target;
    }
    return null;
  }

  /// Receiver implied by an entry file name (`Main.java`, `main.c`, ...).
  static InteropTarget? forEntryFile(String entryFile) {
    switch (p.extension(entryFile).toLowerCase()) {
      case '.java':
        return java;
      case '.c':
      case '.cc':
      case '.cpp':
      case '.cxx':
        return cpp;
      case '.py':
        return python;
      default:
        return null;
    }
  }

  /// Install hint for a language whose receiver is not answering.
  static String installHint(String language) {
    final target = forLanguage(language);
    if (target == null) {
      return '没有支持 $language 的配套应用，无法在本机编译运行。';
    }
    return '未检测到 ${target.productName}（${target.bundleName}）。'
        '安装后可在本机编译运行，或改用「在线终端」。';
  }
}
