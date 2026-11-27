# Historical branch source derivatives

This collection is inert preservation research. It does not enable features, establish that current main lacks them, or authorize applying the patches wholesale.

Read the parent [recovery guide](../README.md) and `branch-patch-manifest.json` together. The manifest maps 30 refs and 83 original commits to 52 distinct text patches, recording original parents/order, included and excluded paths, patch IDs, byte lengths and SHA-256 identities. Patch-ID equality describes normalized textual equivalence; different IDs do not prove semantic novelty. Adoption/supersession review remains in the planning follow-up.

Each derivative uses the original commit's first parent. Exact unpublished commit objects and excluded bytes remain in the verified external bundle; public derivatives are not replacements for that full private recovery copy. Original base IDs remain provenance even where the filtered derivative cannot reconstruct a complete historical checkout from GitHub alone.

The mobile diagnostic test change is already content-equivalent to published ancestor `d3d899571382121d3b5d69dd36b60222e5fa0b37`; no duplicate patch is included. Historical suite-narrowing workflow changes are excluded.

`branch-039-e7f31261900e.patch` is a stable artifact filename, not its current patch-ID claim. After excluding the two unproven Herdr runtime-derived test sections, its derivative patch ID is `581df5505cbdc5c1276e788ec6a98f37252f0dbb`, SHA-256 is `724EBF9523BFCDE50890FE3149CA7232C10D3A53A8B83FA458011C2C001EAE3E`, and length is 190767 bytes. The manifest separately retains original patch ID `29a0f00a7bbc903ecffa8d0a2cdc55a3b1387a64`. Withheld paths are `test/harness_herdr_models_test.dart` and `test/harness_herdr_platform_test.dart`; exact identifiers, paths, titles and session values are not asserted synthetic.

Read the manifest exclusions before any future use. No local product validation, historical script execution, backup deletion or worktree retirement is authorized by this collection. Any adopted change requires its own reviewed implementation and GitHub-hosted checks.
