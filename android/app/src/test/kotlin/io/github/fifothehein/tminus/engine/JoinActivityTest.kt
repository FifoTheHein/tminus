package io.github.fifothehein.tminus.engine

import android.app.Application
import android.content.ActivityNotFoundException
import android.content.ContextWrapper
import android.content.Intent
import io.github.fifothehein.tminus.LoggedErrors
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.shadows.ShadowLog

@RunWith(RobolectricTestRunner::class)
class JoinActivityTest {
    private val app: Application = RuntimeEnvironment.getApplication()

    @Test
    fun `a join link nothing can open logs the exception's class and no part of the link`() {
        val url = "https://teams.example/l/meetup-join/${LoggedErrors.SECRET}"
        // As on a device, the exception's message quotes the intent, and with it the link.
        val refusing = object : ContextWrapper(app) {
            override fun startActivity(intent: Intent) {
                throw ActivityNotFoundException("No Activity found to handle Intent { act=${intent.action} dat=${intent.dataString} }")
            }
        }
        ShadowLog.clear()

        JoinActivity.openJoinUrl(refusing, url)

        LoggedErrors.assertClassOnly(
            "Nothing can open the join link",
            "ActivityNotFoundException",
            forbidden = listOf(LoggedErrors.SECRET, "teams.example", "meetup-join"),
        )
    }
}
