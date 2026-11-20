# #26 - Alarm scheduling off the main thread: orchestration plan

Planned 2026-11-20 · Repo `C:\Projects\tminus` · Worktree: none, the main checkout (see section 2) ·
Branch `fix/26-alarm-calls-off-main-thread` from `main` (8ed9d4a) · Lightweight `/orchestrate` (project
CLAUDE.md): one session plans and runs, no fresh session per wave, gates record evidence and do not stop.

Issue: https://github.com/FifoTheHein/tminus/issues/26 (Plan 6 run log R24, R42, R43).

---

## 1. Facts nobody may re-argue

- Every `AlarmManager` call (`set*`, `cancel`) and every `PendingIntent.getBroadcast` / `getActivity`
  lookup the engine and the pre-sync scheduler make runs on one process-wide serial executor
  (`AlarmCalls`), never on the caller's thread. Reason: each is a Binder call; 150-300 of them on the
  main thread blocked input for more than 5 s on a slow system_server (the issue's ANR traces).
- State stays on the caller's (main) thread. `PlanStore` transitions, `EngineReducer`, the presenter,
  `RingingSession` and engine events are unchanged and stay main-thread-confined. Only the Binder calls
  move. Reason: `RingingSession` is an unsynchronised `object`, and `EngineActions` is documented as
  main-thread-only.
- The executor is serial, so alarm calls run in the order they were issued. A race between a main-thread
  transition and a queued call can at worst leave a stray alarm for an alert the store no longer lists;
  `EngineReducer.fire` ignores it. It can never leave a scheduled alert unarmed.
- Receivers that cause alarm calls call `goAsync()` and finish when `AlarmCalls` is idle, so Android
  keeps the process alive until the re-arm is done.
- The `alarm_engine` `applyPlan` reply is sent only after the queue has drained. Success still means
  "armed"; a call that threw still reaches Dart as `engine_error` (Dart's sync then reports `retry`).
  The reply's map shape (`armed`, `cancelled`, `kept`) is unchanged, and the Dart side is not touched.
- Robolectric tests run with a direct (same-thread) executor installed by a test `Application`
  (`robolectric.properties` `application=`), so the existing tests keep asserting synchronously.
- `getHealth`'s single `canScheduleExactAlarms()` and other `getHealth` system calls stay where they are.

## 2. Standing rules for this plan

- Work in the main checkout `C:\Projects\tminus` on branch `fix/26-alarm-calls-off-main-thread`. A
  worktree would need the git-ignored Gradle and Flutter files copied, and nothing else runs here now.
- Gradle: `.\gradlew.bat` from `C:\Projects\tminus\android` in PowerShell. One Gradle build at a time,
  across every agent.
- Logging: class name only (`e.javaClass.simpleName`), never a message, URL or event text.
- No em dashes (U+2014) in Kotlin strings or comments that ship as text.
- Never edit or `dart format` `lib/core/model/alert.dart` or `planned_alert.dart`. No Dart change at all
  in this plan.
- Commits are authored by the repo-local git identity and carry no Claude attribution of any kind.

## 3. How the parts connect

All Kotlin is in package `io.github.fifothehein.tminus.engine` unless a path says otherwise
(main root `android/app/src/main/kotlin/io/github/fifothehein/tminus/`).

| Name | Kind | Shape (signature / type / text) | Owner job | Behaviour on failure |
|-|-|-|-|-|
| `AlarmCalls` | `object`, new file `engine/AlarmCalls.kt` | process-wide serial queue for Binder calls | W1.1 | - |
| `AlarmCalls.executor` | `@VisibleForTesting internal var executor: java.util.concurrent.Executor` | default: `Executors.newSingleThreadExecutor` with a thread named `tminus-alarm-calls`. Tests replace it | W1.1 | - |
| `AlarmCalls.run` | `fun run(block: () -> Unit)` | posts `block`; blocks run one at a time in posting order | W1.1 | an `Exception` thrown by `block` is caught, logged as `"Alarm call failed: <class>"` under tag `TMinusEngine`, and kept as the pending failure if none is kept yet; the queue carries on |
| `AlarmCalls.whenIdle` | `fun whenIdle(callback: (failure: Throwable?) -> Unit)` | posts a marker; `callback` runs on the executor after every block posted before it, with the first failure kept since the previous marker ran (null if none), and clears it | W1.1 | - |
| `AlarmCalls.awaitIdle` | `@VisibleForTesting fun awaitIdle(timeoutMs: Long): Boolean` | blocks the calling thread until a marker posted now has run; false on timeout. For instrumented tests only | W1.1 | - |
| `finishWhenAlarmCallsIdle` | `fun BroadcastReceiver.finishWhenAlarmCallsIdle()` (top level in `AlarmCalls.kt`) | `val pending = goAsync()`, then `AlarmCalls.whenIdle { pending?.finish() }`. `goAsync()` returns null when `onReceive` is called directly (tests), so null is allowed | W1.1 | - |
| `onMainThread` | `internal fun onMainThread(block: () -> Unit)` (top level in `AlarmCalls.kt`) | runs `block` inline when already on the main looper, else posts it to `Handler(Looper.getMainLooper())` | W1.1 | - |
| `AlarmScheduler.applyPlan` | `fun applyPlan(incoming: List<PlannedAlert>, onApplied: (ApplyResult) -> Unit = {})` (was `: ApplyResult`) | the `PlanStore` diff runs on the caller's thread; one `AlarmCalls.run` block cancels, arms, checks the kept alerts with `isArmed`, re-arms them, then calls `onApplied` with the same counts as before | W1.1 | `onApplied` is not called when the block throws |
| `AlarmScheduler.rearmAll` | `fun rearmAll(): Int` (unchanged) | reads the store on the caller's thread, posts the arms, returns the count at once | W1.1 | - |
| `AlarmScheduler.arm / cancel / armRecovery / armRingingRetry / cancelRecovery` | unchanged signatures, return `Unit` | post their `PendingIntent` lookup and `AlarmManager` call through `AlarmCalls.run` and return at once | W1.1 | - |
| `AlarmScheduler.isArmed`, `canScheduleExactAlarms`, `upcoming` | unchanged, synchronous | production code calls `isArmed` only inside an `AlarmCalls` block | W1.1 | - |
| `EngineActions.applyPlan` | `fun applyPlan(incoming: List<PlannedAlert>, onDone: (Result<ApplyResult>) -> Unit)` (was `: ApplyResult`) | `rewind()`, `scheduler.applyPlan`, `reconcile()` on the caller's thread as now, then `AlarmCalls.whenIdle`: success with the counts, or failure | W1.1 | failure = the kept failure (or an `IllegalStateException` if the counts never arrived) |
| `alarm_engine` `applyPlan` | method channel reply | `result.success(counts.toMap())` through `onMainThread`, after the drain | W1.1 | `result.error("engine_error", null, null)` through `onMainThread`, logged with the class only; argument errors stay `bad_args`, synchronously, as now |
| `tminus_sync` `configure` | method channel reply (`sync/SyncChannel.kt`) | `preSync.setTimes(...)` as now; `result.success(null)` is sent from `AlarmCalls.whenIdle` through `onMainThread` | W1.1 | a kept failure gets the same error reply the handler's generic catch gives today |
| `PreSyncScheduler.armNext` | unchanged signature (`sync/PreSyncScheduler.kt`) | works out `next()` on the caller's thread, posts the `PendingIntent` and `AlarmManager` calls through `AlarmCalls.run` | W1.1 | - |
| Receivers | `onReceive` | `BootReceiver`, `TimeChangeReceiver`, `AlarmReceiver`, `NotificationActionReceiver`, `PreSyncReceiver`, `SyncBootReceiver`: do their work as now, then `finishWhenAlarmCallsIdle()` on every path that did work (early returns for unknown actions need not) | W1.1 | - |
| `TestTMinusApplication` | `src/test/kotlin/io/github/fifothehein/tminus/TestTMinusApplication.kt` | extends the class the manifest's `${applicationName}` resolves to (check the merged manifest; `android.app.Application` if plain); `onCreate` sets `AlarmCalls.executor = Executor { it.run() }` | W1.1 | - |
| `robolectric.properties` | `android/app/src/test/resources/robolectric.properties` | adds `application=io.github.fifothehein.tminus.TestTMinusApplication`; keeps `sdk=34` and its comment | W1.1 | - |

## 4. Acceptance criteria -> tests

Test-author tests install their own executor: a queue they run by hand (`val queued = ArrayDeque<Runnable>()`,
`AlarmCalls.executor = Executor { queued.add(it) }`), and put the direct executor back in `@After`.

| AC | Test (scenario / method name) | Test-author job | Implementation job |
|-|-|-|-|
| AC1 Re-arm makes no alarm call on the caller's thread: after `BootReceiver` (each of `BootReceiver.ACTIONS`) and `TimeChangeReceiver` (each of `TimeChangeReceiver.ACTIONS`) with a stored plan of future alerts, `ShadowAlarmManager` has no alarm until the queue runs; after it runs, every future alert is armed | `AlarmCallsOffMainThreadTest.rearm receivers make no alarm call until the queue runs` | W2.1 | W1.1 |
| AC2 `EngineActions.applyPlan` makes no alarm call on the caller's thread, and `onDone` is not called until the queue runs; afterwards every alert is armed and the counts are right | `AlarmCallsOffMainThreadTest.applyPlan arms and reports only when the queue runs` | W2.1 | W1.1 |
| AC3 The `alarm_engine` `applyPlan` channel reply comes only after the queue drains, with `armed`/`cancelled`/`kept` | `AlarmCallsOffMainThreadTest.applyPlan channel replies after the drain` | W2.1 | W1.1 |
| AC4 A block that throws makes the next `applyPlan` reply `engine_error`; the failure does not leak into the marker after it (`whenIdle` then reports null) | `AlarmCallsOffMainThreadTest.a failed alarm call fails that applyPlan only` | W2.1 | W1.1 |
| AC5 Order holds: arm then cancel of one alert from the main thread, queue run, leaves no alarm; cancel then arm leaves one | `AlarmCallsOffMainThreadTest.alarm calls run in the order they were issued` | W2.1 | W1.1 |
| AC6 A receiver delivered as a real broadcast (`context.sendBroadcast` / `sendOrderedBroadcast` and an idle main looper, so Robolectric gives it a `PendingResult`) goes async, and its pending result finishes only after the queue runs: `BootReceiver`, `TimeChangeReceiver`, `AlarmReceiver`, `NotificationActionReceiver`, `PreSyncReceiver`, `SyncBootReceiver` | `ReceiversFinishWhenIdleTest.<receiver> finishes only after the alarm calls ran` (one per receiver) | W2.1 | W1.1 |
| AC7 `PreSyncScheduler.setTimes` makes no alarm call until the queue runs; the `tminus_sync` `configure` reply comes after the drain | `AlarmCallsOffMainThreadTest.pre-sync alarm and configure reply wait for the queue` | W2.1 | W1.1 |

## 5. Out of scope - do not build, do not propose

- Moving `EngineActions`, the presenter, `RingingSession`, notifications or service starts off the main thread.
- `getHealth`'s system calls, `DeviceCalendarReader` queries, and any other channel method.
- Any Dart change, including timeouts on the `applyPlan` call.
- R29 (the boot window rule) and decision 9's 30 s recovery delay.
- `SyncActionReceiver` and `QuietTileService`.

## 6. Waves

### Setup

Done by the orchestrator's first scout: branch `fix/26-alarm-calls-off-main-thread` created from `main`
at 8ed9d4a in the main checkout; baseline `:app:testDebugUnitTest` must pass before Wave 1.

### Wave 1 - AlarmCalls and its callers

Implementation: W1.1. No test author in this wave (W2.1 follows it).

```
## W1.1 - Serial AlarmCalls executor, async receivers and channel replies

AGENT:   dev-worker
TASK:    #26
SKILL:   none
WORKDIR: C:\Projects\tminus

OWNS:
  android/app/src/main/kotlin/io/github/fifothehein/tminus/engine/AlarmCalls.kt (new)
  android/app/src/main/kotlin/io/github/fifothehein/tminus/engine/AlarmScheduler.kt
  android/app/src/main/kotlin/io/github/fifothehein/tminus/engine/EngineActions.kt
  android/app/src/main/kotlin/io/github/fifothehein/tminus/engine/AlarmEngineChannel.kt
  android/app/src/main/kotlin/io/github/fifothehein/tminus/engine/BootReceiver.kt
  android/app/src/main/kotlin/io/github/fifothehein/tminus/engine/TimeChangeReceiver.kt
  android/app/src/main/kotlin/io/github/fifothehein/tminus/engine/AlarmReceiver.kt
  android/app/src/main/kotlin/io/github/fifothehein/tminus/engine/NotificationActionReceiver.kt
  android/app/src/main/kotlin/io/github/fifothehein/tminus/sync/PreSyncScheduler.kt
  android/app/src/main/kotlin/io/github/fifothehein/tminus/sync/SyncChannel.kt
  android/app/src/test/kotlin/io/github/fifothehein/tminus/TestTMinusApplication.kt (new)
  android/app/src/test/resources/robolectric.properties
  existing tests under android/app/src/test that no longer compile or pass only because of the two
    signature changes (AlarmScheduler.applyPlan, EngineActions.applyPlan) - adapt the call, never the assertion
  android/app/src/androidTest/kotlin/io/github/fifothehein/tminus/engine/RearmReceiversInstrumentedTest.kt
    (add AlarmCalls.awaitIdle before each assertion on armed alarms)
  CLAUDE.md (one sentence under Architecture item 7, engine/: AlarmManager and PendingIntent calls run on
    AlarmCalls' serial thread, issue #26)
READS: anything in the repo

CONTEXT:
  <plan sections 1, 2 and 3, pasted>

DOES:
  1. Create AlarmCalls.kt with every AlarmCalls name in section 3.
  2. Route every AlarmManager and PendingIntent lookup in AlarmScheduler and PreSyncScheduler through
     AlarmCalls.run, to the section 3 shapes. Update the KDoc of the changed methods.
  3. EngineActions.applyPlan and the alarm_engine applyPlan reply, then the tminus_sync configure reply.
  4. The six receivers call finishWhenAlarmCallsIdle().
  5. TestTMinusApplication and robolectric.properties.
  6. Adapt existing tests to the two signature changes only; the instrumented test gets awaitIdle.
  7. The CLAUDE.md sentence.

ACCEPTANCE (run it, paste the real output):
  cd C:\Projects\tminus\android; .\gradlew.bat :app:testDebugUnitTest      ->  BUILD SUCCESSFUL, 0 failures
  cd C:\Projects\tminus\android; .\gradlew.bat :app:compileDebugAndroidTestKotlin  ->  BUILD SUCCESSFUL
  rg -n "alarmManager\.|PendingIntent\.get" android/app/src/main/kotlin  ->  every hit is inside an AlarmCalls.run block, or is isArmed / canScheduleExactAlarms / showIntent called only from one
  git -C C:\Projects\tminus status --short                               ->  only the OWNS files (and the untracked plan)

NEVER: change an existing test's assertion; touch Dart; move state transitions, the presenter or
       RingingSession off the main thread; log an exception message.
```

**Wave 1 close** - through scouts:
- Build and tests: `:app:testDebugUnitTest` -> BUILD SUCCESSFUL, the same test count as the baseline
- Review: `review-worker` on the wave diff; `deep-review` on W1.1 (threading in the alarm engine: the one place a lost alarm hides)
- Negative controls: each one the reviewers name, run by the test runner

### Gate 1 (lightweight: evidence only)

- [ ] Unit tests pass, the count matches the baseline
- [ ] No Binder call left on the caller's thread (the acceptance grep, read by the reviewer)
- [ ] Review and deep review clean, or every finding fixed and re-reviewed

### Wave 2 - Tests for the new behaviour

Test author: W2.1, sent once W1.1 has passed Check.

```
## W2.1 - Tests: alarm calls off the caller's thread

AGENT:   dev-worker
TASK:    #26
SKILL:   none
WORKDIR: C:\Projects\tminus

OWNS:
  android/app/src/test/kotlin/io/github/fifothehein/tminus/engine/AlarmCallsOffMainThreadTest.kt (new)
  android/app/src/test/kotlin/io/github/fifothehein/tminus/engine/ReceiversFinishWhenIdleTest.kt (new)
READS: acceptance criteria and CONTEXT only - not AlarmCalls.kt, AlarmScheduler.kt, EngineActions.kt,
       AlarmEngineChannel.kt, the six receivers, PreSyncScheduler.kt or SyncChannel.kt. You may read the
       existing tests under android/app/src/test (for helpers such as engine/TestAlerts.kt `alert(...)`,
       `NOW`, `HOUR`, and the ShadowAlarmManager idioms) and the AndroidManifest.

CONTEXT:
  <plan sections 1 and 3, and section 4's table and executor note, pasted>

DOES:
  Map each of AC1-AC7 to the named test. Install a hand-run queue executor in each test and restore the
  direct executor in @After.

ACCEPTANCE (run it, paste the real output):
  cd C:\Projects\tminus\android; .\gradlew.bat :app:compileDebugUnitTestKotlin  ->  BUILD SUCCESSFUL
  git -C C:\Projects\tminus status --short                                    ->  only the OWNS files, plus W1.1's uncommitted files if any

NEVER: read the implementation files listed under READS; weaken a criterion to make a test pass (report it instead).
```

**Wave 2 close** - through scouts:
- Tests: `:app:testDebugUnitTest --tests "*AlarmCallsOffMainThreadTest" --tests "*ReceiversFinishWhenIdleTest"` -> all pass, then the full `:app:testDebugUnitTest`
- Review: `review-worker` (same instance) on the wave diff; names a negative control per AC
- Negative controls: at least: `AlarmCalls.run` made to call `block()` inline (AC1, AC2, AC5, AC7 must fail);
  `finishWhenAlarmCallsIdle` finishing at once (AC6 must fail); the channel replying before the drain (AC3 must fail);
  `whenIdle` not clearing the failure (AC4 must fail)
- `flutter test test/app/pages_config_test.dart` -> pass (the plan file is under the excluded `docs/superpowers`)

### Gate 2 (lightweight: evidence only)

- [ ] New tests pass; every named negative control fails under its revert and passes restored
- [ ] Full unit suite passes
- [ ] Optional, if an emulator starts: `:app:connectedDebugAndroidTest` on Pixel_9 (`-gpu swiftshader_indirect`); otherwise NOT VERIFIED

## 7. Orchestrator-only steps

- Booking: report-only. TASK lines are labels; nothing is written to ADO (this repo uses GitHub).
- Overhead task: none - reported unbooked.
- Push `fix/26-alarm-calls-off-main-thread` with an explicit refspec and open a PR to `main` that closes #26.
  The PR description carries no Claude attribution (project CLAUDE.md).

## 8. Bookmark - the orchestrator edits this section only

Reviewer: review-worker (id in the session transcript, W1 review row)

W1 evidence: check scout - status matches OWNS, compile BUILD SUCCESSFUL, no U+2014; runner - :app:testDebugUnitTest BUILD SUCCESSFUL, 375 tests, 0 failures (= baseline). Review: no BLOCK; 2 WARN (kept failure goes to the next marker; non-receiver posters such as RingingService.refuseForeground have no process keep-alive), 4 NOTE.

### Steps

| Step | State (todo / running / done / blocked) | Evidence | Commit |
|-|-|-|-|
| Setup | done | branch created from 8ed9d4a; baseline :app:testDebugUnitTest BUILD SUCCESSFUL, 375 tests, 0 failures (results under C:\Projects\tminus\build\app\test-results) | |
| W1.1 (+F1, F2, F3) | done | checks passed; review and deep review findings fixed or accepted (Decisions) | 5b81c4a |
| W1 close | done | 375/375 after W1.1; review + deep review done | |
| Gate 1 | done | lightweight: evidence above | |
| W2.1 (as W2.1a, W2.1b) + W2.2 | done | 17 new tests (7 + 6 + 4) and 2 added to RingingServiceTest; re-review clean | d283478 |
| W2 close | done | full suite 394 tests, 0 failures; negative controls C1-C25 all failed as expected and restored clean | |
| Gate 2 | done | lightweight; instrumented test (RearmReceiversInstrumentedTest) compiled, not run on a device: NOT VERIFIED | |
| PR | todo | waits for the user's go (section 7) | |

### Built differently

- Tests: AC6 was written by its own job (W2.1b) after the first W2.1 stalled; AC8 (boot window) was added during the run; T1-T6 (W2.2) cover the fix behaviours. Test files: AlarmCallsOffMainThreadTest, ReceiversFinishWhenIdleTest, AlarmCallsFixesTest, plus two tests in RingingServiceTest. FailingAlarmManagerShadow lives in AlarmCallsFixesTest.kt.
- Two callers arm synchronously, against section 1's "never on the caller's thread", by the user's decision: the alarm screen's Snooze (`AlarmScheduler.armNow`, which also posts a copy behind the queue so a cancel for the same id queued earlier cannot undo it) and RingingService's ringing retry (`armRingingRetryNow`, wrapped so a failure still stops the service).
- testAlarm (a channel method section 5 left alone) also replies after the drain, to keep its error path.
- AlarmCalls.failureHook (test-only) makes a failed alarm call throw under Robolectric's direct executor.
- rearmAll posts nearest-first.
- Notification PendingIntents (NotificationFactory, SyncNotifications) stay on the caller's thread.
- Accepted: the kept failure goes to the next marker (one spurious applyPlan retry possible); goAsync holds a broadcast only within its timeout; JoinActivity and AndroidAlertPresenter's queued paths have no keep-alive beyond the foreground app or the receiver that called them.
- The CLAUDE.md sentence (W1.1 DOES 7) is not written: left for the user.

### Sessions

| Session | Started | Ended | Check / note |
|-|-|-|-|
| plan+run (lightweight) | 2026-11-20T13:45:28+0200 | | Opus at medium effort (the skill asks for high; this session cannot raise its own) |

### Time log

| Job | Task | Agent id | Dispatched | Reported | Checked | Worker ms | Committed |
|-|-|-|-|-|-|-|-|
| Baseline test run | overhead | runner (scout) | 2026-11-20T13:49:50+0200 | 2026-11-20T13:55:00+0200 | 2026-11-20T13:55:00+0200 | 273297 | n/a |
| W1.1 | #26 | dev-worker | 2026-11-20T13:56:18+0200 | 2026-11-20T14:14:33+0200 | 2026-11-20T14:16:15+0200 | 1076871 | |
| W1.1 check | overhead | scout | 2026-11-20T14:14:40+0200 | 2026-11-20T14:16:15+0200 | | 94866 | n/a |
| W1 review | overhead | review-worker | 2026-11-20T14:15:00+0200 | 2026-11-20T14:19:00+0200 | | 229369 | n/a |
| W1.1 deep review | overhead | deep-review | 2026-11-20T14:15:00+0200 | 2026-11-20T14:24:00+0200 | | 527810 | n/a |
| W1 test run | overhead | runner (scout) | 2026-11-20T14:16:15+0200 | 2026-11-20T14:18:55+0200 | | 159738 | n/a |
| W2.1 | #26 | dev-worker | 2026-11-20T14:19:10+0200 | stopped 2026-11-20T15:03:00+0200 (no file written; user called it stuck) | | | n/a |
| W2.1a (AC1-5, 7, 8) | #26 | dev-worker | 2026-11-20T15:04:35+0200 | 2026-11-20T15:27:30+0200 | | | |
| W2.1b (AC6) | #26 | dev-worker | 2026-11-20T15:04:35+0200 | 2026-11-20T15:36:00+0200 | | 1745732 | |
| W2.1b follow-up (AlarmReceiver group fire) | #26 | dev-worker (same) | 2026-11-20T15:36:40+0200 | 2026-11-20T15:43:30+0200 | 2026-11-20T15:43:30+0200 (own class 6/6 pass; reorder control fails all 6) | | |
| W2 test run | overhead | runner (scout) | 2026-11-20T15:43:46+0200 | 2026-11-20T15:47:00+0200 (BUILD SUCCESSFUL; 388 tests = 375 + 13 new, 0 failures; XML fresh) | | | n/a |
| W2 review | overhead | review-worker (same) | 2026-11-20T15:44:00+0200 | 2026-11-20T15:47:00+0200 (1 BLOCK armNow vs queued cancel; 1 WARN F1/F2 untested; controls named) | | 179572 | n/a |
| F3 (armNow also queued) | #26 | dev-worker | 2026-11-20T15:47:41+0200 | 2026-11-20T15:52:00+0200 | 2026-11-20T15:52:00+0200 (compile executed BUILD SUCCESSFUL; status unchanged but for AlarmScheduler.kt) | | |
| W2.2 (T1-T6) | #26 | dev-worker | 2026-11-20T15:47:41+0200 | 2026-11-20T15:57:30+0200 | 2026-11-20T15:57:30+0200 (compile OK; own classes 4/4 and 33/33 pass) | 605747 | |
| W2 re-review (F3, W2.2) | overhead | review-worker (same) | 2026-11-20T15:57:54+0200 | 2026-11-20T16:01:00+0200 (clean; controls for T1-T6 and the BLOCK fix named) | | | n/a |
| W2 full run 2 | overhead | runner (scout) | 2026-11-20T15:57:54+0200 | 2026-11-20T16:00:30+0200 (BUILD SUCCESSFUL; 394 tests, 0 failures; XML fresh) | | | n/a |
| Commits | overhead | scout | 2026-11-20T16:00:45+0200 | 2026-11-20T16:01:30+0200 | | | 5b81c4a (W1.1+F1+F2+F3), d283478 (W2.1a+W2.1b+W2.2) |
| Negative controls C1-C25 | overhead | runner (scout) | 2026-11-20T16:02:01+0200 | 2026-11-20T16:14:00+0200 (25/25: every named test failed under its edit; every file restored by sha256; tree clean at d283478) | | 711547 | n/a |
| F2 | #26 | dev-worker | 2026-11-20T15:36:40+0200 | 2026-11-20T15:41:00+0200 | 2026-11-20T15:41:00+0200 (compile executed BUILD SUCCESSFUL; diff matches brief) | | |
| F1 | #26 | dev-worker | 2026-11-20T15:04:35+0200 | 2026-11-20T15:21:21+0200 | | 832348 | |
| F1 check | overhead | scout | 2026-11-20T15:21:30+0200 | 2026-11-20T15:25:00+0200 | 2026-11-20T15:25:00+0200 (steps 1-4; compile deferred to the W2 runner: the scout stopped on another session's vstest.console, unrelated to Gradle) | | n/a |

### Booked

| Task | Clock | Booked h | Last booking |
|-|-|-|-|

Decisions taken (each overturnable - say so and the next session acts on it):
- Plan - the main checkout, not a worktree - the git-ignored Gradle and Flutter files would need copying, and nothing else is running here.
- Plan - deep-review on W1.1 although it is not money, migration or security - it changes when alarms get armed.
- Plan - one implementation job, not several - the files share AlarmCalls and two signatures, and split owners would meet at every seam.

- W1.1 - the CLAUDE.md sentence is not written: the worker's rules bar it from editing CLAUDE.md on an agent's brief, and it is left for the user to approve at the end.
- W1.1 - the acceptance grep's notification PendingIntents (NotificationFactory, SyncNotifications) stay on the caller's thread: section 5 puts notifications out of scope; the grep's wording was too broad.
- W1.1 - the worker ran compiles only, not the unit suite (its rules give test runs to the runner); the runner runs it as the wave's test step.

- W1 deep review (no BLOCK; 5 WARN, 4 NOTE; ordering proven equal to the old synchronous order after the drain) - fix job F1 for W1.1: testAlarm replies after AlarmCalls.whenIdle (engine_error on failure), restoring the Health and onboarding error paths; rearmAll posts in fire-time order so a broadcast-timeout kill loses the latest alarms, not the nearest; AlarmCalls.failureHook (reset by the executor setter) lets TestTMinusApplication rethrow so a failed alarm call fails a test.
- W1 deep review - accepted, not fixed: (a) the process-wide kept failure goes to the next marker, so a marker-less failure (MainActivity start-up, activities, RingingService) can make one applyPlan reply engine_error: one spurious retry, no lost alarm; (b) paths outside receivers (RingingService.refuseForeground's ringing retry, AlarmActivity snooze, JoinActivity) post with no process keep-alive: a refused foreground service must stop at once, and the queue drains in milliseconds unless system_server is slow; a snooze lost that way returns at the next rearmAll. Follow-up issue candidate; (c) goAsync keeps the process alive only within the broadcast timeout (10 s for TIME_SET/TIMEZONE_CHANGED, 60 s for boot), not "until the re-arm is done" as section 1 words it; (d) a stale alarm can fire during the queue delay and ring a moved alert early (never lost); (e) batching canScheduleExactAlarms/showIntent per re-arm is left for later.
- User, 2026-11-20 - "fix the RingingService one too": F1 also makes RingingService.refuseForeground arm its ringing retry synchronously (a blocking variant of armRingingRetry) before stopSelfResult. It is a rare path and one alarm (a few Binder calls), it uses its own request code so jumping the queue cannot reorder another alert's calls, and delaying stopSelf instead would risk Android's "did not start foreground in time" crash. Supersedes the RingingService part of accepted item (b) above.
- User, 2026-11-20 - "Snooze sync too": F1 also arms a snooze from AlarmActivity synchronously. Shape: EngineActions.snooze gains `armNow: Boolean = false`; AlarmActivity passes true; NotificationActionReceiver keeps the queued arm (its goAsync covers it). AlarmScheduler gains blocking `armNow(alert)` and `armRingingRetryNow(ids, at)` for these two callers only. Cost accepted by the user: the Snooze tap makes one alarm call per snoozed alert on the UI thread.
- W2.1 - AC8 added by message: a boot-window test with the hand-run queue (deep review's uncaught control).

- W2.1 stopped after 44 min with no file (user: stuck). Split into W2.1a (AlarmCallsOffMainThreadTest, AC1-5, 7, 8) and W2.1b (ReceiversFinishWhenIdleTest, AC6, the Robolectric-research part), each time-boxed to ~30 min. F1 runs in parallel with them (disjoint files); compile lock waits are retried. W2.1b may run its own test class to prove its technique.

- F1 report - decided: the follow-up fix F2 wraps RingingService.refuseForeground's armRingingRetryNow in a catch (class-only log) so a throw cannot skip stopSelfResult (a skipped stop risks the "did not start foreground in time" crash). AlarmActivity's armNow keeps letting a throw reach the caller, as before W1.1. AndroidAlertPresenter's queued refused-start retry is accepted: present() runs from receivers (goAsync), the channel (reply waits) or the foreground app.

- W2 review BLOCK - armNow armed inline could be undone by a cancel for the same id still queued (snoozing a snooze reuses its id; reconcile queues cancels). Fix F3: armNow arms inline and posts the same arm behind the queue. W2.2 adds tests T1-T6 for F1/F2 (testAlarm, snooze armNow incl. the BLOCK case, synchronous ringing retry, F2 catch, rearmAll order, failure hook). AC8 is part of section 4 by the W2.1 message (section 4 stays as planned).
- Controls run on committed work: after F3 and W2.2 pass and the re-review is clean, the parts are committed, then each control reverts against the commit.

Stopped at: PR - waiting for the user's go to push and open the PR; earlier: next: check each, then the full W2 test run, review of F1 and the tests, and the negative controls
