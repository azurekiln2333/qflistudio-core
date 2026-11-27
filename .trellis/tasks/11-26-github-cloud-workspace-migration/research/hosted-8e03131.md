# Hosted repair evidence at 8e03131

Core `8e031313ffc8d531c5a6b4d131f721f35da04c86` passed the shared push gate
at 2026-11-28 03:24:38. Target owner w6A:p1 acknowledged clean main/tree parity
at 04:11:06 +08:00, tree `122f8f37553ae5aea1478a4e485abfe29695c1ea`.
This is publication/migration evidence, not complete CI acceptance.

## Core workflow 46056507608, attempt 1

| Job | Conclusion | Complete suite |
| --- | --- | --- |
| check 140700181461 | Failure: changed Dart formatting only | 3343 passed, 27 skipped, 0 failed; terminal success=true |
| canonical 140700181432 | Success | 3343 passed, 27 skipped |
| legacy 140700181545 | Success | 3343 passed, 27 skipped |
| relocated 140700181726 | Success | 3343 passed, 27 skipped |

The observer parsed visible test completion events; 361 hidden events in the
main suite are excluded from its displayed counts. Main analysis and full suite
passed. Screenshots and both intentional-negative jobs also passed. No fixture
symlink or assertion removal was used to resolve the package identity failure.

The hosted main formatter emitted three whitespace hunks: wrap the protocol-file
`File(...)` expression in `test/interop_fixture_roots_test.dart`, and wrap two
`_packageConfigError(...)` calls in `test/support/interop_fixture_roots.dart`
(invalid version/packages list and missing package file). Apply the retained
patch; do not infer that successful tests waive formatting.

## Consumer workflow 46056507619, attempt 1

- OHOS job `140700181353`: formatting failed on one multiline `Text(resultLabel,
  style: Theme.of(context).textTheme.bodyMedium)` call in
  `lib/pages/local_content_pages.dart`. The emitted patch places it on one line.
  Resolution and smoke execution were skipped.
- Official job `140700181706`: preparation and package resolution passed.
  Executed SDK evidence is Flutter 3.50.1, framework
  `ae9b586f34a8443573f82ef57c3bf914a908cbf7`, Dart 3.14.0. Analyzer stopped on
  deprecated `package:flutter/material.dart` import in the smoke template.
  No smoke tests ran.

The smoke only exercises the non-OHOS inert view, so use `widgets.dart` with
`Directionality`; it does not require a Material application. Preserve every
callback, Unicode-width, compilation and no-exception assertion. This is a
test-only repair. All three resolver hunks and the one library hunk are whitespace
only. There is no consumer-facing behavior change after `8e03131`, so consumers
retain the brain-approved wave-2 SHA unless a new instruction supersedes it.

## Consumer-owner reports (not independently re-fetched here)

Web `715c796ddac36c869b67e12f5b63c3ad0bc77daa`, Cloud `46059969291` and App
`46059969298`, using Core `8e03131`: both narrow tutorial/example catalog title
cases passed. Full suite 309 passed, 2 failed, 6 skipped. Remaining navigation/
example fixture cases remain Web-owned; this is not six-platform acceptance.

Note `845fe879`, validation `46061127018`, job `140715379711`, reports prior
compiler/load failures cleared with official preparation and vendored roots
confirmed. Newly reached badge-layout and workspace assertions remain under
owner diagnosis, not established Core defects by this evidence alone.

## Boundary

Only source and hosted metadata/log-text reads were used. No local formatter,
analyzer, test, build, package installation, SDK/artifact download or WSL action
ran. The next immutable repair commit must pass both Core workflows before
done.json. Preserve target parity as a separate gate and do not claim consumer
package, signing, device or cleanup acceptance.
