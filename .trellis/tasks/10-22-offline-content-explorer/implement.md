# Implementation

1. [x] Inspect core architecture, content path, existing lazy/idle/import tests and header specs.
2. [x] Implement backwards-compatible language/level metadata and saved-example serialization.
3. [x] Add inline search, language/difficulty chips and reset/empty behavior to both content tabs. Preserve lazy rows and source/import/edit behavior.
4. [x] Add consistent circle language labels on lists/details and reuse project identification styles.
5. [x] Test compound filters, reset, custom/saved metadata, large text/narrow layouts, cache/lazy/idle/import regressions.
6. [ ] Independent review, spec update and coherent conventional commit. Do not include unknown explorer/history modifications.

Commands: flutter analyze; focused content tests plus existing local_content_lazy_catalog_test.dart, content_idle_frames_test.dart, content_code_import_test.dart, home_content_repository_test.dart, java_content_render_test.dart and python_content_render_test.dart. Product host/device acceptance remains separate.

## Input fixture integration (accepted shared defect)

Preserve optional inputFixtures through aggregate and legacy lesson/example models,
saved overrides and detail projections. When older aggregate tutorials lack their
fixture, join examples by sourceLessonId once when loading the tutorial. Materialize
stdin as root input.txt and other fixtures as validated relative files on scratch,
new-project and existing-project import. Reject traversal, aliases, links, metadata
and source collisions before writing. Include every existing target in the replacement
confirmation. Preflight the whole set and restore earlier writes if a later write fails.
Do not call host verification phone acceptance or conceal failing engine examples.
