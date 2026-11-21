// OS capability checks isolated from dart:io so the storage wrapper remains
// compilable on browser builds (which must still fail closed for credentials).

/// True when the selected Flutter secure-storage implementation is not vetted
/// for the host OS. OHOS is intentionally unsupported until its plugin vault is
/// reviewed; Web local storage is also not accepted for GitHub tokens.
bool get isUnsupportedGithubCredentialPlatform =>
    throw UnsupportedError('platform stub not selected');
