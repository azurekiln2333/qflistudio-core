# Released consumer fixes

The brain released core on 2026-11-27 at 23:35 after the other 13 repositories
had migrated/completed receipts. The release permits only the already active
filter overflow and Note compilation fixes before the exact-commit push gate.
The older core-last hold is superseded. No local product checks are permitted.

## Filter ownership and repair

SQL `50b1703049f9afbb07fd2b6fad606617cf6684e0`, run `46018672426`, job
`140572422633`, attempt 1, explicitly reports the tutorials 320px/text-scale-2
107px overflow at core `lib/pages/local_content_pages.dart:1068:11`, creator
`Row -> Column -> Padding -> _ContentFilterBar`. Executed core is `476a30a`,
executed Flutter revision `62357a93d653bf844f730bb1f4b7cc9e2139d14e`.
The retained diagnostic report SHA-256 is
`1737f8d58baec23d1fb1b62e15d6ba97ea4645902943b7eef1fe74fb13e934d5`;
the full raw log SHA-256 is
`b329ecd88206e965b2450a9f2f7bd8b0ec310cdaefc597c78487b5c1320c6389`.
Only tutorial ownership was verified in that report; do not infer example
ownership, final counts or the unrelated Web missing-language-chip cause.

Replace the result/reset Row with OverflowBar vertical fallback. Keep chip
scrolling, result labels and reset callback intact. Add tutorial/example widget
regressions at 320px/text scale 2, retaining every existing assertion and covering
filter/query selection, count/reset bounds, hit-testable reset and no reload.
Independent source review passed; formatting and execution remain hosted-pending.

## Follow-up: catalog title overflow after the first wave

Web `a689f58887b4de8e2ccd2480c2785cc1c713400f`, Core
`1ae4674a4b153701b0c3b3ff04b1a1b77a318611`, executed Flutter
`244a0e8abb3085e8675589b13e219af8c41cb7aa`: owner-retained App run
`46046455210`, job `140667074731`, reports 11px right overflow at
`lib/pages/local_content_pages.dart:1134:41`. Tutorials at
`18:08:11.6896419Z` and examples at `18:08:15.8516601Z` name
`Row <- _ContentTitle <- DefaultTextStyle <- AnimatedDefaultTextStyle <- _ListTile`.
Both have `BoxConstraints(w=208.0, 0.0<=h<=Infinity)` and `Size(208.0,96.0)`.
The retained excerpt resolves catalog ownership; no new log download was needed.

Only tutorial/example list callers select the wrapping title layout. Preserve
subject badge identity and text scale, allow oversized badges to scroll, keep
two-line title ellipsis and preserve detail AppBar layout. Two additive
320px/text-scale-2 regressions retain title reachability, bounds, badge identity,
navigation and no-exception assertions. Existing tests remain intact.

Independent static review passed. Formatting and execution remain hosted-pending.
This repair changes consumer-facing library behavior. Under `core-ref-wave.md`
item 7, the next gate-passed SHA requires a brain-coordinated wave; consumers keep
`1ae4674` until that instruction. The resolver and workflow bootstrap repairs are
Core-internal CI changes. Web's missing-language-key failures remain separately
owned and are not attributed to this Row.

## Follow-up: desktop card height at text scale 2

Web retained exact evidence at Core `8e031313ffc8d531c5a6b4d131f721f35da04c86`,
run `46069023957`, job `140741374987` (same owner diagnostic in App run
`46069023876`, job `140741314086`): `320px desktop keeps workbench navigation
with 2x text` reported a 44px bottom overflow at
`lib/pages/local_content_pages.dart:1536:18`. The `_LargeScreenContentGridCard`
Column received 168x104 after its 16px card padding. Phone navigation and the
catalog title regressions already passed.

The bounded repair derives additional grid-card height from the active
`TextScaler` for one label, one title and two summary lines, while retaining the
normal 144px geometry at scale 1, grid count/spacing and lazy construction. The
language label remains single-line in a horizontal scroll view. Tutorial and
example desktop regressions use a 320x900 viewport, 80px rail-equivalent inset,
2x text, 168px card-column width, content bounds, full label/title/summary
reachability, detail navigation and no-exception assertions. Existing assertions
remain unchanged. This is consumer-facing library behavior and requires the
targeted Web wave after the next Core gate; other consumers remain on `8e03131`.

## Note compile boundary

Note `bcd7c879d32ac95327f069b5d6fac5932c76765d`, validation run `46011327362`,
job `140547283034`, named missing UnicodeV11 and cascading num-to-int errors in
core Herdr code, plus undefined OhosView under official Flutter. Prior installer
run `45998337349` also named hosted xterm 4.0.0's non-exhaustive OHOS switch.

Core now declares xterm directly at `vendor/xterm`. The retained vendor exports
UnicodeV11 with integer wcwidth and has an OHOS-safe default shortcut branch.
No casts or vendor implementation changes are made. Core's existing overrides
and lock stay intact; consumer root overrides still take precedence. A hosted
consumer with no xterm override must prove resolution to the bundled tree.

Runtime platform checks cannot remove the compiler's undefined OhosView symbol.
The core-owned runner preparation script therefore carries the existing app
shim contract with exact SDK/source guards. Official mode stubs only the Huawei
view; OHOS preserves the original bytes. The source file itself stays unchanged.
The consumer wave MUST include an explicit preparation invocation for official
jobs; changing CORE_REF alone is insufficient. No Note files are modified.

The new hosted consumer workflow covers official 3.50.1 at
`ae9b586f34a8443573f82ef57c3bf914a908cbf7` and OHOS 3.41.10-ohos-1.0.1 at
`adaf911c35c9136a7d18fc424d714c9ec7724e60`, using pinned app installer
`69656b4ab14e706e85907ef4c4205d8cd35a1338`. It checks script rejection/no-op
boundaries, resolved core/re_editor/xterm roots, terminal widths and Huawei API.
No native package, physical device, full official core suite or additional
code_assets/hooks_runner compatibility is asserted by these smoke tests.

## Publication and remaining gates

Only reviewed fix files, their focused hosted coverage and corresponding
spec/progress updates are eligible for the local commits. Submit exact clean
main through the shared push gate with an empty allow list. After gate PASS,
target owner w6A:p1 performs ff-only pull/parity/ACK while one worker observes
hosted checks. migrated.json records parity; done.json requires the remaining
actual CI evidence. Old worktrees, backups and WSL remain protected.
