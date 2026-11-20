# Remote computer ownership

## 1. Scope / Trigger

Apply when changing `lib/remote_control`, host navigation, or remote session
subscriptions. The module runs inside Studio's navigator and theme.

## 2. Signatures

- `RemoteComputerPage({store, controller, onExit})` owns only the controller it creates.
- `RemoteController.subscribe(String id, {required Object owner})` acquires a route's stream.
- `unsubscribe(String id, {required Object owner})` releases only that route.
- `HerdrController.claimPaneWatching()` returns an opaque `HerdrPaneLease`.
- `watchPane(lease, paneId)`, `resumeWatching(lease)` and `releasePaneWatching(lease)` reject stale leases.

## 3. Contracts

Each session route retains one identity token. Overlapping owners share the
subscription Future and see the same failure. Only the final release sends
`unsubscribe`. Reconnect clears the wire request cache, retains mounted owners,
and restores one subscription per session with its last sequence cursor.

A Herdr lease belongs to one mounted pane route. A replacement invalidates the
old lease before deferred callbacks execute. Stale disposal cannot stop the
replacement's watch. Pane destinations replace each other. An embedder stacking
pane routes must claim a new lease when revealing an older route.

Claude structured sessions use their own `send` operation. They never follow
Herdr focus or send composer text to a pane. PTY disposal clears terminal input
and resize callbacks only when those callbacks still belong to that widget.

Module exit resolves the host navigator above the module navigator. A drawer
exit closes its local history entry before popping the host. Exiting releases
owned client resources and never closes desktop sessions. Pairing uses
`qfli_remote_control.json`, separate from Studio credentials.

## 4. Validation & Error Matrix

| Event | Required behavior |
| --- | --- |
| Two routes show the same session | One wire subscription and two owner tokens |
| Old route disposes during replacement | New stream and input callbacks survive |
| Shared subscribe fails | Both routes receive failure; retry remains possible |
| Reconnect after final release | No subscription is restored |
| Old Herdr callback executes | Stale lease produces no mutation |
| User leaves remote module | Client resources close; desktop session stays alive |

## 5. Good / Base / Bad Cases

- Good: A-B-A navigation uses a fresh token on every route instance.
- Base: A single route acquires once and releases once.
- Bad: A `Set<String>` of session IDs lets old disposal erase a replacement.

## 6. Tests Required

Run the full Flutter suite in cloud CI. `session_ownership_test.dart` covers
overlap, shared failures, replay cursors, input ownership and final release.
`remote_module_regression_test.dart` covers Claude routing, Herdr ownership,
host exit and controller teardown. Terminal capture fixtures retain ANSI
bytes and meaningful whitespace. Assert known grid fill separately.

## 7. Wrong vs Correct

Wrong: clear a session or terminal callback unconditionally in `dispose()`.

Correct: `controller.unsubscribe(id, owner: routeToken)` and clear a callback
only if it is still identical to the disposing route's callback.
