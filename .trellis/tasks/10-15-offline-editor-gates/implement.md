# Execution plan

- [ ] Confirm core worktree clean and no concurrent dirty writers.
- [ ] Gate `git` / `cloud_pull` menu items and handler cases in `editor_page.dart`.
- [ ] Pass `showAi: offlineOnly != true` in `profile_page.dart::_openSettings`.
- [ ] Add widget regression: offline hides Git/AI, online keeps both.
- [ ] Run `flutter analyze --no-pub lib test` and `flutter test --no-pub`.
- [ ] `git -C D:/MyNewProjects/qfli_studio_core` stage only the two source files
      and the new test, conventional commit.

## Validation

- `flutter analyze --no-pub` from the core root.
- `flutter test --no-pub` (or the new test file plus the existing editor/settings
  tests) from the core root.
- Confirm `git status` afterwards lists only intended paths.
