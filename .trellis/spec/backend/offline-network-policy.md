# Offline API request policy

## Scope

`lib/services/api_client.dart` owns shared account, community, cloud project,
online terminal and cloud SQL HTTP requests. UI visibility is not an enforcement
boundary: callers may retain clients or invoke a service directly.

Check `StudioProfile.current?.offlineOnly` on every request, not at construction.
The main application (`current == null`) and an explicit `offlineOnly: false`
profile retain online behavior. Do not substitute `isOffline` for this policy.

## Request boundary

The shared `_requireOnline` assertion is the first operation in `_send` and
`terminalEvents`. It runs before endpoint/URI construction, request creation,
authorization-header construction, JSON/body serialization, lazy HTTP-client
access and sending. Streaming policy is checked when the stream is listened to,
so a stream created online cannot start a request after switching offline.

All current GET, POST, PATCH, PUT and DELETE API methods use `_send`; the NDJSON
terminal stream is the only separate HTTP send path and uses the same assertion.
There is currently no multipart/file-loading method or internal retry loop in
this client. Future request methods, multipart preparation, file loading and
caller retries must enter the same policy boundary before preparing a request.
Do not make network activity an offline fallback.

## Error contract

Offline denial uses the existing `ApiException` type, with a user-readable
message, `details['code'] == 'OFFLINE_ONLY'` and `statusCode == null`. No server
responded, so do not fabricate HTTP 403 or report a connection failure. This is a
policy denial, not a transient request to retry. Existing callers already handle
`ApiException`; this client has no `RequestException` type.

`health()` preserves its existing exception-to-`false` contract. Terminal streams
deliver `ApiException` as a stream error. Cleanup remains available in offline
mode; closing a client must not be blocked by request policy.

## Limits

This gate denies requests started through this API client. It does not revoke an
already-started request or retries internal to an injected transport that began
online. It does not intercept other libraries, native platform channels, authored
programs or local preview servers. Product permissions, native host policies,
runtime isolation and packaged-device verification remain separate requirements.

## Verification

`test/api_client_offline_test.dart` uses a real loopback `HttpServer` sentinel and
an injected transport that redirects every actual socket to that sentinel. It
never delegates to the configured Internet API origin. Positive online controls
prove the server path works, including authentication, mutations and NDJSON.

Cover derived and explicit offline profiles, every current HTTP verb, cloud/SQL/
terminal entrypoints, a previously used online client, an unlistened stream,
repeated caller retries and content that must not be inspected or serialized.
Offline cases require both zero transport sends and zero server requests.
Run the focused test plus existing service configuration/background tests once
the shared validation slot is available; source changes alone are not a passed
host or device acceptance claim.
