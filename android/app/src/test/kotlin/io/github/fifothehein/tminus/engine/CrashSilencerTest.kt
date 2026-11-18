package io.github.fifothehein.tminus.engine

import io.github.fifothehein.tminus.LoggedErrors
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.shadows.ShadowLog

@RunWith(RobolectricTestRunner::class)
class CrashSilencerTest {
    @Test
    fun `a failure while silencing logs the exception's class and not its message or trace`() {
        val original = Thread.getDefaultUncaughtExceptionHandler()
        val seenByPrevious = mutableListOf<Throwable>()
        Thread.setDefaultUncaughtExceptionHandler { _, e -> seenByPrevious += e } // what the silencer hands the crash to
        try {
            CrashSilencer.install()
            CrashSilencer.register { throw IllegalStateException(LoggedErrors.SECRET) }
            ShadowLog.clear()
            val crash = RuntimeException("boom")

            Thread.getDefaultUncaughtExceptionHandler()!!.uncaughtException(Thread.currentThread(), crash)

            assertEquals(listOf<Throwable>(crash), seenByPrevious) // the crash still reaches the previous handler
            LoggedErrors.assertClassOnly("Could not silence the alarm while crashing", "IllegalStateException")
        } finally {
            CrashSilencer.register(null)
            Thread.setDefaultUncaughtExceptionHandler(original)
        }
    }
}
