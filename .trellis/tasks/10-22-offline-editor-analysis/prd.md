# Offline editor analysis and Problems integration

## Goal

Typed product syntax-analysis callback with unsaved snapshots, generation-safe scheduling, wavy diagnostics, Problems navigation and missing language highlighting; no program execution or network backend.

## Requirements

- Product-owned offline syntax analysis accepts current unsaved document snapshots, never runs user programs, writes user files or falls back to a network service.
- Typed shared results carry exact UTF-16 half-open source offsets and error/warning/information/hint severity. Empty success differs from unavailable backend.
- Editor debounces content changes, ignores stale generations/revisions/root changes/disposal, preserves syntax colors, and draws wavy underlines on actual diagnostic ranges.
- Problems panel shows real diagnostics and availability, navigates to owned file/range and coexists with the existing terminal. No fake debugger controls.
- Add missing default Rust/Go/Lua/Shell/SQL/TypeScript grammars and relevant header aliases, retaining imported TextMate/theme/large-file behavior.

## Acceptance Criteria

- [ ] Product profiles without an analyzer retain current behavior and an honest unavailable state.
- [ ] Tests prove unsaved snapshots, no source writes/execution, debounce, stale result rejection, cross-root/tab and dispose safety.
- [ ] Actual highlighted spans retain token styles while Unicode, multiline, empty-line and overlapping diagnostic ranges are correctly decorated.
- [ ] Problems navigation resolves correct owner root/file/range, clears invalid stale marks and remains usable at narrow/large-text sizes.
- [ ] Parameterized actual-token checks cover every supported standalone default language/extension.
- [ ] Existing editor/run/terminal/offline/retained-session/highlighting tests and analysis pass. Product OHOS adapter execution remains an additional gate.

## Notes

The user explicitly authorizes Trellis then implementation. Shared-core owner is C coordinator w1R:p1. Java/Lua/Dart implement their own providers against design.md; content filter and explorer workers own separate files. Preserve unrelated dirty work.
