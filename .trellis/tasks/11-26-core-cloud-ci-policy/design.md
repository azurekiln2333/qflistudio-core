# Cloud CI design

Core policy is a discoverable versioned contract in unmanaged AGENTS content plus Trellis workflow/spec. It allows source editing, metadata/Git inventory and remote CI control, prohibits local builds/tests/restores/SDK bootstraps and artifact downloads. It does not claim to sandbox a shell.

Read integrated core-check and its pinned APP_REF/JAVA_REF. Preserve explicit runner aliases unless all dependent path consumers change together. qflistudio-next owns its upstream Flutter/OHOS adaptation script; do not invent a core script contract. Pin final core after UI handoff and cloud checks, not initial ee83f1c.

Map six platforms to native dependencies, Flutter build, final package/signing, cloud artifacts/cache retention and successful immutable-input runs. Detect skipped/incomplete jobs and real signing/runner/access constraints. Coordinate fixes with existing repository owners via Herdr; never edit their work without ownership assignment. CI outputs stay in GitHub storage.

Keep runtime functionality and existing intentional assets intact. Verification must exercise relevant code contracts in cloud, not merely YAML syntax. Review cloud workflow permissions and reusable input/output compatibility.

