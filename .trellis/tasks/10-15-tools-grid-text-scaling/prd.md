# Keep shared tools grid usable with large text

## Goal

Generic text-scaling-aware card extent fix, handed off by Go coordinator to Web coordinator; retain normal geometry and no product navigation changes.

## Requirements

- Adapt shared tools grid card extent to the active text scaler, keeping the
  existing 132 logical-pixel extent at normal scale.
- Keep all cards reachable at 320px width with 2x text in light and dark themes.
- Change only generic grid geometry and its regression test; no Web-specific
  navigation, content, labels or product merging in the shared core.
- Ownership transferred from Go coordinator on qfli-core-release-sync; all Web
  pi workers remain read-only in core. Do not touch concurrent retained editor work.

## Acceptance Criteria

- [x] Existing normal-scale grid/navigation tests pass.
- [x] 320px/2x light and dark regressions render actual cards with no overflow,
      retain a clickable terminal card and scroll to the last shared tool.
- [x] Analyze relevant files and commit only this task, grid source and tests.

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
