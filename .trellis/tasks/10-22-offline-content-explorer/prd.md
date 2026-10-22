# Shared offline language filters and explorer restoration

## Goal

Coordinated shared-core first batch for all standalone products: language filters and consistent badges, correct initial sidebar expansion and asynchronous restore guards.

## Requirements

- R1: Multi-language standalone tutorial/example pages expose intersecting language, query and difficulty filters, with C / C++ labels and clear empty/reset states. Preserve source, import and saved-example behavior, lazy lists and repository caching.
- R2: Show consistent small circular language badges beside content titles and detail titles, matching project language identification. Propagate optional language/level metadata with backwards-compatible defaults and saved-example round trips.
- R3: Restore expanded folders/root visibility after drawer/page reconstruction. Persist multiple local workspace roots and preserve owner-aware file actions, open tab order, active file and cursors across application sessions.

## Acceptance Criteria

- [ ] Language, difficulty and search filters combine on both lists; reset and no-result behavior work, including single-language profiles.
- [ ] Content row/detail badges accurately distinguish C/C++ and retain legacy custom content.
- [ ] Saved-example metadata and editing survive serialization, copy and reload.
- [ ] Lazy catalog, idle frames, imports and existing language content tests pass; narrow/large-text content remains usable.
- [ ] Multiple roots retain independent expansion and membership without losing concurrent history updates.
- [ ] Cross-root tab order, active file and cursors restore with the correct registered owner; stale/foreign entries do not escape their roots.

## Notes

User explicitly authorizes Trellis then implementation and conventional commits without repeated permission prompts. This batch is owned by C coordinator w1R:p1 with exclusive native worker paths. Dart/Java/Lua keep their product adapters separate. Umbrella task: D:/MyNewProjects/qfli_c/.trellis/tasks/10-22-offline-standalone-ide.

C root explicitly adopted the previously unattributed explorer/history work on
October 22 after attribution requests returned no current owner. Other product
coordinators continue to reserve those files for C. Review found tree membership
implemented but EditorPage still discarded foreign-root tabs on save; this batch
will complete and verify that missing session behavior before committing it.
