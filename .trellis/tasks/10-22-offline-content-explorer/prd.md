# Shared offline language filters and explorer restoration

## Goal

Coordinated shared-core first batch for all standalone products: language filters and consistent badges, correct initial sidebar expansion and asynchronous restore guards.

## Requirements

- R1: Multi-language standalone tutorial/example pages expose intersecting language, query and difficulty filters, with C / C++ labels and clear empty/reset states. Preserve source, import and saved-example behavior, lazy lists and repository caching.
- R2: Show consistent small circular language badges beside content titles and detail titles, matching project language identification. Propagate optional language/level metadata with backwards-compatible defaults and saved-example round trips.
- R3: Sidebar restoration and multi-root workspace are coordinated separately. Existing explorer/history modifications appeared during read-only audit and are unowned by this batch; do not overwrite them. Full umbrella R6 remains open pending owner identification.

## Acceptance Criteria

- [ ] Language, difficulty and search filters combine on both lists; reset and no-result behavior work, including single-language profiles.
- [ ] Content row/detail badges accurately distinguish C/C++ and retain legacy custom content.
- [ ] Saved-example metadata and editing survive serialization, copy and reload.
- [ ] Lazy catalog, idle frames, imports and existing language content tests pass; narrow/large-text content remains usable.

## Notes

User explicitly authorizes Trellis then implementation and conventional commits without repeated permission prompts. This batch is owned by C coordinator w1R:p1 with exclusive native worker paths. Dart/Java/Lua keep their product adapters separate. Umbrella task: D:/MyNewProjects/qfli_c/.trellis/tasks/10-22-offline-standalone-ide.
