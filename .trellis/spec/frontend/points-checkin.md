# Points loading and check-in transitions

## 1. Scope / Trigger

Points/reward tabs and daily tasks share account balances but have independent
network and local persistence lifetimes. Slow requests must leave visible local
feedback and cannot overwrite a newer mutation or another signed-in account.

## 2. Signatures

`PointsFeed(auth:, client?, clock?, cacheDirectory?)` exposes `rewards`, `ledger`,
`orders` and `adminOrders` sections with value/loading/error state. `initialize()`
restores cache then loads stale sections concurrently. `refreshAll` and each
section refresh accept `force` and `afterMutation` booleans. Call
`noteBalanceMutation()` before applying a successful redemption's balance.

`TaskActivityService.checkin(AuthStore)` returns
`({bool alreadyChecked, int reward, int streak})`.
`TaskActivityService.refreshIfDue(AuthStore, {bool force = false})` refreshes the
task snapshot. `TasksPage(activity?)` supports an injected service for transition
tests; production uses the singleton.

## 3. Contracts

The section cache is `points_<userId>.json`, version 2, with an independent
day/data pair per section. Read version 1 for compatibility. Cache failures fall
back to live sections. Populated data stays visible during refresh. Retain tab
children/scroll state and subscribe at section scope; changing balance must
update redemption eligibility without rebuilding the entire page.

Manual refreshes share one in-flight request and one trailing forced refresh.
`afterMutation: true` starts a new section generation so a pre-mutation request
or already-running tail cannot become the authoritative post-mutation result.
Capture token, user id, generation, balance and mutation revision before awaits;
discard stale responses. Same-account token rotation starts replacement loads.
Admin/user changes rebuild role-dependent tabs/actions.

Check-in immediately replaces the button in its 88x40 slot with indeterminate
progress; a synchronous guard prevents taps before the next frame. Clear loading
in `finally`. Suppress old-account feedback. Successful server results update
memory even when local cache/auth persistence fails; show a persistence warning
without suggesting the reward claim failed. A result that is unknown disables
check-in and offers refresh confirmation, scoped by account/day. Only a confirmed
current-token refresh may clear uncertainty. A delayed tasks GET must not undo a
newer check-in or task-event snapshot.

`TaskActivityService` captures `_revisionOf(userId)` immediately before the tasks
GET. Successful check-in and task-event responses call `_bumpRevision(userId)`
when publishing their snapshot. A GET must match token, user id and revision
before assigning its snapshot, and again after `_persist()` before updating
`AuthStore`. The per-account revision protects requests in this service instance;
account identity or balance equality alone does not prove that a response is new.

`TasksPage._refreshTasks()` captures both the token and account/day key before
awaiting confirmation. Check both on success and failure before changing its
error or uncertainty state. Keep uncertainty across same-account token rotation:
an old-token GET discarded by the service cannot confirm a cached snapshot.

## 4. Validation & Error Matrix

| Condition | Behavior |
| --- | --- |
| One points endpoint stalls/fails | Other sections show content and localized status. |
| Revisit populated tab | Retain content and scroll; no duplicate initial request. |
| Repeated manual refresh | At most one trailing fetch per section. |
| Mutation completes while GET/tail runs | New generation fetches post-mutation state. |
| Account/token changes | Discard old response and old feedback; load current session. |
| Remote mutation succeeds, local write fails | Keep server success and refresh stock/orders; visible local warning. |
| Check-in API error | Stop progress; visible error and appropriate retry. |
| Unknown check-in result | Disable claim, offer current-session refresh confirmation. |
| Token rotates during confirmation for the same account/day | Keep uncertainty until a refresh started with the current token completes. |
| Tasks GET predates successful check-in | Preserve newer checkedToday/balance. |

## 5. Good/Base/Bad Cases

Good: rewards arrive while ledger is pending; rewards render immediately, and
buttons update when balance arrives. Base: a cached same-day section needs no
new initial GET. Bad: tab switching remounts lists and starts all requests again,
or an old ledger response restores a pre-redemption balance.

Bad: a delayed tasks GET returns `checkedToday=false`, `points=10` after check-in
has published `checkedToday=true`, `points=20`. The GET must leave both the task
snapshot and auth balance at the newer values, even though its account matches.

## 6. Tests Required

Run `points_feed_test.dart`, `points_page_test.dart`,
`tasks_page_checkin_test.dart` and `task_activity_service_test.dart`. Use blocked
responses to prove concurrency, duplicate guards, account/token rotation,
post-mutation request generations and delayed pre-check-in snapshots. Assert the
actual button becomes progress, failure clears it, uncertainty disables it and
refresh confirmation respects token identity. Inject local write failures after
server success. Retained content/request counts prove lifecycle behavior; they
do not establish device frame timing or backend performance.

REVIEW5 evidence: all 29 cases in those four files passed with exit 0 using the
installed cached Dart/Flutter snapshot and `--no-pub --concurrency=1 --timeout
60s`. Coverage includes cached pending tasks, a blocked GET, successful check-in,
then GET completion; token rotation during unknown-result confirmation followed
by a current-token confirmation; and mutation refresh superseding an
already-running manual tail. Dart analysis of the four source and four test files
reported no issues; scoped `git diff --check` passed.

## 7. Wrong vs Correct

Wrong: await cache persistence after an identity check, then update whichever
account is currently signed in. Correct: capture identity before the request,
recheck it after every relevant await and before publishing balance/feedback.
Wrong: join an existing manual tail after redemption. Correct: invalidate its
generation and issue a request that starts after the mutation.

Wrong: accept a tasks response because its user id still matches. Correct:
capture its activity revision before the GET and compare it before publication
and after local persistence. Wrong: clear unknown check-in state because the
account/day matches and no error was reported. Correct: also require the captured
token to match the current token before accepting refresh confirmation.
