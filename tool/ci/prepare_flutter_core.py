#!/usr/bin/env python3
"""Prepare the one fork-only widget in a GitHub-hosted runner checkout.

Consumers must invoke this before official-Flutter analysis, tests or builds.
OHOS mode validates the original implementation without changing its bytes.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


VIEW = Path("lib/pages/auth/huawei_quick_login_view.dart")
ORIGINAL_SHA256 = "8af40cfa6efac753a59f1a41c295a73e7823684c020669584357c0789ab58d1e"
SOURCE_ROOTS = ("lib", "vendor/re_editor/lib", "vendor/xterm/lib")
FORK_NAMES = ("TargetPlatform.ohos", "OhosView")
# API-compatible upstream shim previously owned by qflistudio-next at
# c5f4bc3afe9c81ba488fd3f544d43c3dac061512:tool/ci/patch_upstream_core.sh.
OFFICIAL_VIEW = """import 'package:flutter/material.dart';

class HuaweiQuickLoginView extends StatelessWidget {
  const HuaweiQuickLoginView({
    super.key,
    required this.agreementAccepted,
    required this.onAuthorizationCode,
    required this.onError,
  });

  final bool agreementAccepted;
  final ValueChanged<String> onAuthorizationCode;
  final ValueChanged<String> onError;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
"""


def normalized_text(path):
    return path.read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n")


def git_output(root, *arguments):
    result = subprocess.run(
        ["git", "-C", str(root), *arguments],
        text=True,
        encoding="utf-8",
        capture_output=True,
        check=True,
        timeout=25,
    )
    return result.stdout.strip()


def validate_sdk(sdk_root, revision, flavor):
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("--sdk-revision must be a full lowercase immutable commit")
    actual = git_output(sdk_root, "rev-parse", "HEAD")
    if actual != revision:
        raise ValueError(f"SDK HEAD {actual} differs from --sdk-revision {revision}")
    if git_output(sdk_root, "status", "--porcelain", "--untracked-files=no", "--", "packages/flutter/lib"):
        raise ValueError("SDK packages/flutter/lib has local modifications")
    library = sdk_root / "packages/flutter/lib/src"
    platform = normalized_text(library / "foundation/platform.dart")
    has_enum = re.search(r"^\s*ohos\s*[,}]", platform, re.MULTILINE) is not None
    has_view = any(
        re.search(r"\bclass\s+OhosView\b", normalized_text(path))
        for path in (library / "widgets").glob("*.dart")
    )
    expected = flavor == "ohos"
    if has_enum != expected or has_view != expected:
        raise ValueError(f"SDK source does not match --flavor {flavor}: ohos={has_enum}, OhosView={has_view}")
    return actual


def prepare(core_root, sdk_root, revision, flavor, app_root=None):
    if os.environ.get("GITHUB_ACTIONS") != "true" or os.environ.get("RUNNER_ENVIRONMENT") != "github-hosted":
        raise ValueError("Preparation is permitted only on GitHub-hosted runners")
    core_root = core_root.resolve(strict=True)
    sdk_root = sdk_root.resolve(strict=True)
    if not re.search(r"^name:\s*qfli_studio_core\s*$", normalized_text(core_root / "pubspec.yaml"), re.MULTILINE):
        raise ValueError("--core-root is not the qfli_studio_core package")
    actual_revision = validate_sdk(sdk_root, revision, flavor)
    view_path = core_root / VIEW
    original_bytes = view_path.read_bytes()
    original_text = normalized_text(view_path)
    digest = hashlib.sha256(original_text.encode("utf-8")).hexdigest()
    is_original = digest == ORIGINAL_SHA256
    is_stub = original_text == OFFICIAL_VIEW
    if not is_original and not (flavor == "official" and is_stub):
        raise ValueError(f"Unexpected {VIEW.as_posix()} contents (normalized SHA256 {digest}); review the new source before updating this shim")

    roots = [(core_root / relative, core_root) for relative in SOURCE_ROOTS]
    if app_root is not None:
        app_root = app_root.resolve(strict=True)
        roots.append((app_root / "lib", app_root))
    offenders = []
    for root, base in roots:
        if not root.is_dir():
            raise ValueError(f"Missing source directory: {root}")
        for path in sorted(root.rglob("*.dart")):
            if path == view_path:
                continue
            for number, line in enumerate(normalized_text(path).splitlines(), 1):
                for name in FORK_NAMES:
                    if name in line:
                        offenders.append(f"{path.relative_to(base).as_posix()}:{number}: {name}")
    if offenders:
        raise ValueError("Unexpected fork-only references; no source was changed:\n" + "\n".join(offenders))

    changed = flavor == "official" and not is_stub
    if changed:
        view_path.write_bytes(OFFICIAL_VIEW.encode("utf-8"))
    if flavor == "ohos" and view_path.read_bytes() != original_bytes:
        raise ValueError("OHOS view changed during preparation")
    return {
        "flavor": flavor,
        "sdk_revision": actual_revision,
        "core_root": str(core_root),
        "view": VIEW.as_posix(),
        "changed": changed,
        "native_ohos_view_preserved": flavor == "ohos",
        "view_sha256": hashlib.sha256(view_path.read_bytes()).hexdigest(),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--sdk-root", type=Path, required=True)
    parser.add_argument("--sdk-revision", required=True)
    parser.add_argument("--flavor", choices=("official", "ohos"), required=True)
    parser.add_argument("--app-root", type=Path)
    args = parser.parse_args()
    try:
        result = prepare(args.core_root, args.sdk_root, args.sdk_revision, args.flavor, args.app_root)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        parser.exit(1, f"prepare_flutter_core: {error}\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
