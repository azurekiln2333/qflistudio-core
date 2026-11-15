# Explicit saved workspaces

## 1. Scope / Trigger

`StudioProfile.supportsSavedWorkspaces` defaults to true, including the compatible
null-profile shell. It offers local named-workspace save and Home entries across
products independently of `offlineOnly`, `showHomeTabs` and product identity.
Named workspaces are independent documents. A cloud primary cannot start a named
workspace: direct explorer actions explain that a local project must be opened.
Do not silently filter that primary during save and leave a different live tree.

`isMainStudioRelease` still selects only the main `qflistudio` product and null
profile. This capability adds the workspace scope alongside previously enabled
scopes; it does not change cloud filtering, creation or fetching. Main-release
cloud suppression is a separate Home policy owned by that product. Network-enabled
language products expose both workspace and cloud scopes. Offline products
expose only local scopes. Child products retain the legacy
[offline workspace](offline-workspace.md) history contract until explicitly saving
a named document. Disabling the capability preserves their legacy member picker,
disables new named saves in the main product, and hides Home's workspace scope;
already-open explicit documents remain manageable.

## 2. Signatures

- `WorkspaceStore({Directory? root})` uses the override as the workspace
  directory, or `AppPaths.storageDirectory()/workspaces` by default.
- `save({existing?, required name, required members, required primary,
  session?})` returns `({String? error, SavedWorkspace? workspace})`.
- `saveSession(SavedWorkspace, WorkspaceSessionSnapshot)`, `remove(String id)`,
  `load({bool force = false})`, and `settle()` return `Future<void>`.
- `addMembers(String workspaceId, Iterable<Project> additions)` appends local
  members to the latest stored document and returns the updated workspace.
  Snapshot inputs before queueing and deduplicate by `workspacePathKey`.
- `resolve(SavedWorkspace, ProjectStore)` returns `WorkspaceResolution` with
  `projects`, `missing`, `primary`, `primaryMissing`, and `isEmpty`.
- `openEditorPage(..., workspace?, workspaceProjects?, workspaceStore?)` opens
  a standalone session when `workspace` is null.
- The explorer project selector changes temporary browsing in standalone mode.
  In a saved workspace it opens the additions picker directly.

## 3. Contracts

Each `<id>.json` contains version, id, name, creation/update timestamps, ordered
member references (`projectId`, `path`, `name`, `primary`), and session
metadata (owner-relative documents/cursors/active tab and per-root expansion).
Source buffers are never stored in this document. Names are trimmed, nonempty
and unique ignoring case. A one-project workspace is valid. Type and language
are resolved from the current registered project rather than copied into member
references.

Snapshot mutable inputs before enqueueing. Serialize store calls in invocation
order and transactions across instances addressing the same physical directory.
Read current disk state inside the transaction, merge the fields the caller
owns, atomically replace the document, and only then publish memory. Metadata
updates without an explicit session retain the latest session; session saves
retain latest name/membership/timestamps. Session saves do not reorder Home.
Deleted workspace ids cannot be recreated by stale timers or metadata dialogs.

Retained workspace identity is its id, independent of effective primary path.
Promotion of a standalone session keeps its live state; subsequent standalone
opens use one distinct standalone session. Reopening W after its primary A
disappears resumes W with survivor B and preserves B's live dirty buffers.
Main standalone history ignores foreign-owner documents and remembered foreign
tree roots. Child products continue restoring legacy multi-root history.

In standalone mode, the explorer selector changes only the browsed tree and
default creation target. Keep the editor, Agent project, live buffers and route.
Opening a file from another project passes that project's owner to the editor.
Temporary foreign roots do not become saved-workspace members.

In saved-workspace mode, the same selector directly opens a multi-select
additions dialog. One confirmation appends selected local projects. Do not open
a second naming or membership-edit dialog. Existing members cannot be unchecked.
The store transaction preserves the latest name, identity, primary, member order,
missing-member references and session data. A stale additions picker must not
overwrite a concurrent session save or resurrect a deleted workspace. Preserve
live buffers and tree expansion when publishing the updated document. Report a
failed addition visibly. Legacy language-product unsaved browsing retains its
history contract.

Same-id metadata changes must propagate through retained host, page and explorer.
Reopening or saving a rename/member edit updates the retained session snapshot
without changing its key, page/controller identity, live expansion or dirty text.
A metadata-only explorer update does not rebuild its tree. Subsequent expansion
notifications must not re-emit an older name or membership. Compare the incoming
workspace object as well as paths, rather than treating equal ids/timestamps as
proof that all metadata is unchanged.

On reopening, validate registry membership and actual directories. Skip missing
members and report them; select a surviving primary. Reconcile retained tabs:
close clean tabs of unavailable members, retain dirty buffers for explicit Save
As recovery, and block their original-root save, autosave and run. Retaining
expansion metadata for a removed root does not restore its membership.

Workspace management dialogs explicitly use `AlertDialog(scrollable: true)`
with ordinary, intrinsically measurable project children. Let the dialog own
the content scroll while keeping its actions outside that scroll. Do not nest
a shrink-wrapping `ListView` under a width-only or maximum-height constraint:
the OHOS SDK's scrollable dialog asks for intrinsic height, which a viewport
cannot provide. That layout exception leaves the modal barrier visible without
a usable dialog. The same layout contract applies to legacy project selection.

## 4. Validation & Error Matrix

| Condition | Behavior |
| --- | --- |
| Empty/duplicate name or no local member | Return a useful save error; keep dialog open. |
| Missing secondary | Report and open surviving members. |
| Missing primary | Report and use a survivor in the same retained session. |
| All members missing | Actionable empty state; no editor using an invalid root. |
| Malformed document/id mismatch | Skip document; never traverse outside workspaces. |
| Write/delete fails | Preserve memory; propagate or return error for visible retry. |
| Session save after deletion | No-op; never resurrect metadata. |
| Metadata save after deletion | Return a save-as-new error. |
| Root removed then re-added | Restore its stored expansion; preserve other roots. |
| Standalone selector chooses another project | Change only the browsed tree; retain editor and Agent identity. |
| Workspace selector opens | Show one additions picker with existing members fixed. |
| Add multiple projects | Append unique local members; preserve missing references and latest session. |
| Cancel additions | Preserve membership and live editor state. |

## 5. Good/Base/Bad Cases

Good: W(A,B) and standalone A have independent session metadata; missing A falls
back to B without a second live W. Base: a single local project can be saved as
a named workspace. Bad: a hidden retained timer recreates a workspace the user
deleted, or a standalone A restores unrelated B tabs from legacy history.

## 6. Tests Required

Run `workspace_store_test.dart`, `main_workspace_sessions_test.dart`, legacy
`workspace_editor_session_test.dart` and `file_explorer_state_test.dart`, retained
editor and owner-run regressions. Assert disk JSON as well as controller state.
Cover concurrent metadata/session writes and failed deletion retries, missing
primary/secondary/all, same live session fallback with dirty buffers, standalone
reuse after promotion, actual tree fallback and remove/re-add expansion.
Keep child profiles explicit in legacy tests. Drain fake-time queued writes with
bounded duration pumps and real IO; awaiting them entirely inside `runAsync`
can deadlock. Include the explorer at 1100x175 and large text.
`workspace_dialog_layout_test.dart` must physically click settings through a
retained `EditorPage`, using OHOS/Chinese phone and desktop layouts plus an
Android control. Assert hit-testable title/name/actions, last-project selection
with ten registered projects and a 300px keyboard inset, persisted membership,
single-project save, unchanged source, retained page identity and cancellation
returning toolbar input. Include the explicit language-product legacy dialog.
Advance the initial frame and the keyboard-inset animation before scrolling
or clicking; finder presence alone does not establish a visible dialog.
`workspace_project_switch_test.dart` and
`editor_project_browse_semantics_test.dart` must physically use the selector.
Assert temporary standalone browsing, cross-project file ownership and unchanged
editor/Agent identity. In a workspace, select several additions in one dialog
and assert persisted order, missing-member retention, independent dirty buffers
and unchanged workspace identity. Cancellation must not save or navigate.
Store tests cover duplicate/mutable inputs and concurrent session writes.
Open the initially collapsed explorer through its toolbar before clicking rows;
mounted tree text can be clipped and is not evidence that it receives input.
Use a nonzero scroll offset and drain each project's queued history via
`ProjectHistory.load` after unmounting before deleting a temporary fixture.

`saved_workspace_capability_test.dart` covers default/null/optout capability and
independent offline/main/cloud policy, plus actual explorer rejection of a cloud
primary. Legacy-dialog fixtures explicitly opt out so they keep exercising that
compatibility path. `workspace_metadata_refresh_test.dart` covers same-id external
and in-page metadata refresh with live dirty buffers and unchanged retained
identity. Product-owned actual-profile Home/save/reopen tests remain required;
mocked identity changes cannot prove standalone entry availability.

## 7. Wrong vs Correct

Wrong: `byId(id) ?? staleWorkspace` before autosaving, or a session key containing
the primary path as a required identity component. Correct: update only an
existing disk document in the serialized transaction and locate a retained
workspace by id; update its effective primary/members without rebuilding buffers.

Wrong: navigate to another editor when the user only changes the browsed tree,
or reconstruct workspace membership from resolved projects and lose missing
references. Correct: keep browsing independent from editor identity and append
workspace additions inside the serialized store transaction.
