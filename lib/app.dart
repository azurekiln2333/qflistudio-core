import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'i18n/studio_localizations.dart';
import 'editor/editor_fonts.dart';
import 'editor/retained_editor_host.dart';
import 'pages/home_page.dart';
import 'pages/restore_complete_page.dart';
import 'services/app_restore_gate.dart';
import 'services/studio_profile.dart';
import 'splash_screen.dart';
import 'store/auth_store.dart';
import 'store/project_store.dart';
import 'store/settings_store.dart';
import 'theme/app_theme.dart';

class QfliApp extends StatefulWidget {
  const QfliApp({
    super.key,
    required this.store,
    required this.auth,
    this.settings,
    this.ready,
    this.navigatorKey,
  });

  final ProjectStore store;
  final AuthStore auth;
  final SettingsStore? settings;
  final ValueListenable<bool>? ready;

  /// Lets a product push routes from outside the widget tree, e.g. when the
  /// OS opens a document with this app.
  final GlobalKey<NavigatorState>? navigatorKey;

  static const Color brandSeed = AppTheme.brandSeed;

  @override
  State<QfliApp> createState() => _QfliAppState();
}

class _QfliAppState extends State<QfliApp> {
  final _editors = RetainedEditorController();
  late final SettingsStore _fallbackSettings = SettingsStore();
  late final ValueNotifier<
    ({ThemeMode theme, bool ready, AppRestoreStatus? restoreStatus})
  >
  _appearance;

  SettingsStore get _settings => widget.settings ?? _fallbackSettings;

  @override
  void initState() {
    super.initState();
    EditorFonts.registerLicense();
    _appearance = ValueNotifier((
      theme: _settings.themeModeValue,
      ready: widget.ready?.value ?? true,
      restoreStatus: AppRestoreGate.status.value,
    ));
    _settings.addListener(_updateAppearance);
    widget.ready?.addListener(_updateAppearance);
    AppRestoreGate.status.addListener(_updateAppearance);
  }

  void _updateAppearance() {
    _appearance.value = (
      theme: _settings.themeModeValue,
      ready: widget.ready?.value ?? true,
      restoreStatus: AppRestoreGate.status.value,
    );
  }

  @override
  void didUpdateWidget(covariant QfliApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      (oldWidget.settings ?? _fallbackSettings).removeListener(
        _updateAppearance,
      );
      _settings.addListener(_updateAppearance);
    }
    if (oldWidget.ready != widget.ready) {
      oldWidget.ready?.removeListener(_updateAppearance);
      widget.ready?.addListener(_updateAppearance);
    }
    _updateAppearance();
  }

  @override
  void dispose() {
    _settings.removeListener(_updateAppearance);
    widget.ready?.removeListener(_updateAppearance);
    AppRestoreGate.status.removeListener(_updateAppearance);
    _appearance.dispose();
    _editors.dispose();
    _fallbackSettings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return ValueListenableBuilder<
      ({ThemeMode theme, bool ready, AppRestoreStatus? restoreStatus})
    >(
      valueListenable: _appearance,
      builder: (context, appearance, _) => MaterialApp(
        navigatorKey: widget.navigatorKey,
        navigatorObservers: [_editors.navigatorObserver],
        builder: (context, child) =>
            RetainedEditorHost(controller: _editors, child: child!),
        title:
            StudioProfile.current?.appTitle ?? StudioProductCatalog.qfliStudio,
        debugShowCheckedModeBanner: false,
        locale: StudioLocalizations.resolveLocale(
          WidgetsBinding.instance.platformDispatcher.locale,
        ),
        supportedLocales: StudioLocalizations.supportedLocales,
        localizationsDelegates: const [
          StudioLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: appearance.theme,
        home: appearance.restoreStatus != null
            ? RestoreCompletePage(status: appearance.restoreStatus!)
            : !appearance.ready
            ? const SplashScreen()
            : HomePage(
                store: widget.store,
                auth: widget.auth,
                settings: settings,
              ),
      ),
    );
  }
}
