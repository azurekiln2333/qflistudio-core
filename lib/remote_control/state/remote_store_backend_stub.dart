// Browser / unsupported-platform persistence for the remote-control module.
//
// The web target has no application-support directory. Persistence degrades to
// memory: pairing still works for the lifetime of the page but is not restored,
// and nothing is written to shared browser storage. The module is not advertised
// on the web, so this is a safety net rather than a supported mode.

import 'remote_store_backend.dart';

/// Always yields an in-memory backend.
Future<RemoteStoreBackend> openDefaultRemoteStoreBackend() async =>
    MemoryRemoteStoreBackend();
