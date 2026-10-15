# Offline-only editor Git and AI entry gating

## Requirements

- A product that sets `StudioProfile.offlineOnly == true` must not expose any
  entry that reaches the network from the editor or the profile settings route.
- The editor «more» popup currently renders the `Git` entry unconditionally and
  `从云端拉取` for cloud projects, even when `offlineOnly` is true. `GitPage`
  performs `git push` / `git pull` / `git remote add`, all network operations.
- The profile tab's `_openSettings()` opens `SettingsPage` without
  `showAi: false`, so the «AI 助手 → 个人 AI 接口» section remains reachable for
  an offline product. That section configures a user-supplied external AI
  endpoint (base URL + key).
- Online (non-offline-only) products (`offlineOnly == false`) must keep both
  entries exactly as today.

## Acceptance

- Under an offline-only profile the editor popup has no `Git` / `从云端拉取`
  item, and the settings route has no `AI 助手` section; the handler cases are
  unreachable too.
- Under a networked profile (`offlineOnly == false`) both entries remain and
  their handlers still navigate as before.
- A real widget regression covers both profiles.
- `flutter analyze --no-pub lib test` and `flutter test --no-pub` pass.
