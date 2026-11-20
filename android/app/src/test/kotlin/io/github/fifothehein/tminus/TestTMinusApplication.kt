package io.github.fifothehein.tminus

import android.app.Application
import io.github.fifothehein.tminus.engine.AlarmCalls
import java.util.concurrent.Executor

/**
 * The Application every Robolectric test runs with (`application=` in robolectric.properties). The
 * manifest names the plain android.app.Application, so this extends it.
 *
 * It installs an AlarmCalls executor that runs each call on the caller's thread. A test then reads
 * what AlarmManager holds right after the call that armed it, as it did before the calls moved to
 * AlarmCalls' own thread. It also installs a failure hook that rethrows, so a failed alarm call
 * reaches the caller and fails the test, as it did before the calls moved. A test of the threading
 * installs its own executor, which removes the hook, and puts a direct one back when it is done.
 * onCreate runs for every test, so none inherits another's executor or hook.
 */
class TestTMinusApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        AlarmCalls.executor = Executor { it.run() }
        // After the executor: assigning it resets the hook.
        AlarmCalls.failureHook = { throw it }
    }
}
