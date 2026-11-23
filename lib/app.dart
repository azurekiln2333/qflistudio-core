import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'i18n/studio_localizations.dart';
import 'editor/editor_fonts.dart';
import 'editor/retained_editor_host.dart';
import 'harness/hub/harness_hub.dart';
import 'github/github_auth_controller.dart';
import 'github/github_scope.dart';
import 'layout/app_form_factor.dart';
import 'pages/home_page.dart';
import 'pages/restore_complete_page.dart';
import 'services/app_restore_gate.dart';
import 'services/studio_profile.dart';
import 'services/runner_service.dart';
import 'shell/large_screen_workbench.dart';
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
    this.formFactor,
    this.githubController,
  });

  final ProjectStore store;
  final AuthStore auth;
  final SettingsStore? settings;
  final ValueListenable<bool>? ready;

  /// Device-family override for embedded products and deterministic tests.
  final AppFormFactor? formFactor;

  /// The caller owns an injected GitHub controller.
  final GitHubAuthController? githubController;

  /// Lets a product push routes from outside the widget tree, e.g. when the
  /// OS opens a document with this app.
  final GlobalKey<NavigatorState>? navigatorKey;

  static const Color brandSeed = AppTheme.brandSeed;

  @override
  State<QfliApp> createState() => _QfliAppState();
}

class _QfliAppState extends State<QfliApp> {
  final _editors = RetainedEditorController();
  late GitHubAuthController _github;
  late bool _ownsGitHub;

  void _configureGitHub() {
    _ownsGitHub = widget.githubController == null;
    _github =
        widget.githubController ??
        GitHubAuthController(
          openBrowser: (uri) => RunnerService.openUrl(uri.toString()),
        );
    _githubRestored = false;
  }

  AppFormFactor? _formFactor;
  bool _githubRestored = false;
  late final SettingsStore _fallbackSettings = SettingsStore();
  late final ValueNotifier<
    ({ThemeMode theme, bool ready, AppRestoreStatus? restoreStatus})
  >
  _appearance;

  /// 退出钩子：把还活着的 harness 主机（以及它们的子进程）收尾完再放行。
  AppLifecycleListener? _lifecycle;

  SettingsStore get _settings => widget.settings ?? _fallbackSettings;

  @override
  void initState() {
    super.initState();
    _configureGitHub();
    _formFactor = widget.formFactor;
    if (_formFactor == null) unawaited(_resolveFormFactor());
    EditorFonts.registerLicense();
    _appearance = ValueNotifier((
      theme: _settings.themeModeValue,
      ready: widget.ready?.value ?? true,
      restoreStatus: AppRestoreGate.status.value,
    ));
    _settings.addListener(_updateAppearance);
    widget.ready?.addListener(_updateAppearance);
    AppRestoreGate.status.addListener(_updateAppearance);
    _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
    _restoreGitHub();
  }

  Future<void> _resolveFormFactor() async {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final display = views.isEmpty ? null : views.first.display;
    final size = display == null || display.devicePixelRatio <= 0
        ? Size.zero
        : display.size / display.devicePixelRatio;
    final family = await resolveAppFormFactor(
      operatingSystem: Platform.operatingSystem,
      displaySize: size,
    );
    if (mounted && widget.formFactor == null) {
      setState(() => _formFactor = family);
    }
  }

  void _restoreGitHub() {
    if (_githubRestored ||
        widget.ready?.value == false ||
        StudioProfile.current?.offlineOnly == true) {
      return;
    }
    _githubRestored = true;
    unawaited(_github.restore());
  }

  /// 关窗前等子进程结束。
  ///
  /// 桌面端的终端与 Herdr 都是子进程：Dart 侧不 await 释放，它们会比应用活得
  /// 久，下次打开会说窗格被占用。手机上不会走到这里（没有本机子进程）。
  Future<AppExitResponse> _onExitRequested() async {
    await HarnessHub.shutdownOpenHubs();
    return AppExitResponse.exit;
  }

  void _updateAppearance() {
    _restoreGitHub();
    _appearance.value = (
      theme: _settings.themeModeValue,
      ready: widget.ready?.value ?? true,
      restoreStatus: AppRestoreGate.status.value,
    );
  }

  @override
  void didUpdateWidget(covariant QfliApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.githubController != oldWidget.githubController) {
      if (_ownsGitHub) _github.dispose();
      _configureGitHub();
    }
    if (widget.formFactor != oldWidget.formFactor) {
      _formFactor = widget.formFactor;
      if (_formFactor == null) unawaited(_resolveFormFactor());
    }
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
    _lifecycle?.dispose();
    _settings.removeListener(_updateAppearance);
    widget.ready?.removeListener(_updateAppearance);
    AppRestoreGate.status.removeListener(_updateAppearance);
    _appearance.dispose();
    _editors.dispose();
    if (_ownsGitHub) _github.dispose();
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
        builder: (context, child) => GitHubScope(
          controller: _github,
          child: _formFactor == AppFormFactor.phone
              ? RetainedEditorHost(controller: _editors, child: child!)
              : child!,
        ),
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
            : !appearance.ready || _formFactor == null
            ? const SplashScreen()
            : _formFactor == AppFormFactor.phone
            ? HomePage(
                store: widget.store,
                auth: widget.auth,
                settings: settings,
              )
            : LargeScreenWorkbench(
                editors: _editors,
                store: widget.store,
                auth: widget.auth,
                settings: settings,
              ),
      ),
    );
  }
}
