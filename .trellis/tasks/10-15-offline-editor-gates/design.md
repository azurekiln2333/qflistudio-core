# Design and boundaries

## Behavior gap

`StudioProfile.offlineOnly` already gates the login/account/community/cloud
surfaces in `home_page.dart` and `profile_page.dart`. Two editor/settings
entries were missed:

1. `lib/editor/editor_page.dart` popup «more» menu items `git` (always) and
   `cloud_pull` (cloud only) and their `switch` handler cases
   (`_openGit`, `_pullFromCloud`).
2. `lib/pages/profile_page.dart` `_openSettings()` builds `SettingsPage`
   without `showAi`.

## Where the behavior lives

- The popup is built in `editor_page.dart`; its `onSelected` switch dispatches
  `git` / `cloud_pull`. Both the menu item and the case must be gated, so a
  programmatic value cannot reach the handler either.
- `SettingsPage.showAi` already exists and defaults to `true`; the editor route
  passes `showAi: StudioProfile.current?.offlineOnly != true`. The profile route
  must do the same.

## Change

- Wrap the `Git` and `从云端拉取` `PopupMenuItem`s in
  `if (StudioProfile.current?.offlineOnly != true)`.
- Guard the `case 'git'` / `case 'cloud_pull'` handlers with the same check.
- Add `showAi: StudioProfile.current?.offlineOnly != true` to the profile
  `SettingsPage` construction.

## Not doing

- No change to `StudioProfile` itself, to `GitPage`, or to how online products
  behave.
- No change to direct `GitPage` navigation guards unless a test proves one is
  reachable while offline; the menu/handler gate is sufficient and minimal.
- No refactor of the popup menu.

## Verification

- New widget test mounts `EditorPage` under a synthetic offline profile and
  asserts the popup lacks both entries; mounts under a networked profile and
  asserts both are present. Settings route asserted for both profiles.
- Existing suite must stay green.
