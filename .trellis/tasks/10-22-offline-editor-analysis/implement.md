# Implementation plan

1. [x] Audit editor/profile/re_editor integration and publish stable provider schema in design.md.
2. [x] Add typed code_analysis.dart and StudioProfile.codeAnalyzer; test defaults/snapshots/validation.
3. [x] Add generation-safe bounded scheduler and structured diagnostics state; integrate lifecycle/content revisions/current owner root.
4. [x] Add color-preserving wave span builder and actual Problems tab/navigation/availability without altering terminal behavior.
5. [x] Register missing language grammars and aliases with actual token tests.
6. [ ] Focused editor/terminal/offline/retained/highlight regressions and analyzer/Problems integration tests, analysis; independent review, spec update, conventional commit.

Exclusive diagnostic worker files: services/code_analysis.dart, services/studio_profile.dart, new editor/diagnostic* files, editor/open_file.dart, editor/editor_page.dart (diagnostic integration only), editor/highlight_themes.dart, new diagnostic/highlighting tests. Do not edit file_explorer/project_history/content models/pages/stores, vendor code or product runtime source. Root handles product provider and coordination. Product compile/phone evidence is separate and must not be inferred from UI mocks.
