# Cloud CI design

Core policy is a discoverable versioned contract in unmanaged AGENTS content plus Trellis workflow/spec. It allows source editing, metadata/Git inventory and remote CI control, prohibits local builds/tests/restores/SDK bootstraps and artifact downloads. It does not claim to sandbox a shell.

Read integrated core-check and its pinned APP_REF/JAVA_REF. Preserve explicit runner aliases unless all dependent path consumers change together. The 2026-11-27 Note compile ruling extends core ownership to a narrow explicit runner preparation entry point, based on the existing app-owned official-Flutter shim. It must preserve original OHOS source, validate exact SDK identity/flavor, reject unexpected source drift, and replace only the approved Huawei login widget in an official-Flutter runner checkout. Consumers invoke it explicitly; a core pin bump alone cannot run the shim. Keep the original app script as historical provenance. Pin final core after actual cloud evidence, not initial ee83f1c.

Map six platforms to native dependencies, Flutter build, final package/signing, cloud artifacts/cache retention and successful immutable-input runs. Detect skipped/incomplete jobs and real signing/runner/access constraints. Coordinate fixes with existing repository owners via Herdr; never edit their work without ownership assignment. CI outputs stay in GitHub storage.

Keep runtime functionality and existing intentional assets intact. Verification must exercise relevant code contracts in cloud, not merely YAML syntax. Review cloud workflow permissions and reusable input/output compatibility.

