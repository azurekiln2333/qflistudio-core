import 'dart:io' show Platform;

/// True when this host has no vetted GitHub credential vault implementation.
bool get isUnsupportedGithubCredentialPlatform =>
    Platform.operatingSystem == 'ohos';
