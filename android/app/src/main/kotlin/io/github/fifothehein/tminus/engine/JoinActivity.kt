package io.github.fifothehein.tminus.engine

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log

/**
 * Invisible activity behind a notification's Join button. Android 12+ blocks starting activities
 * from a BroadcastReceiver behind a notification action, so Join must be an activity PendingIntent.
 */
class JoinActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val alertId = intent.getStringExtra(EXTRA_ALERT_ID)
        val url = alertId?.let { EngineActions.create(this).join(it) }?.event?.joinUrl
        if (url != null) openJoinUrl(this, url)
        finish()
    }

    companion object {
        const val EXTRA_ALERT_ID = "alertId"

        fun intent(context: Context, alertId: String): Intent =
            Intent(context, JoinActivity::class.java)
                .putExtra(EXTRA_ALERT_ID, alertId)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_HISTORY)

        /** Teams opens teams.microsoft.com links when installed; otherwise the browser does (spec §6). */
        fun openJoinUrl(context: Context, url: String) {
            try {
                context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            } catch (e: ActivityNotFoundException) {
                Log.w("TMinusEngine", "Nothing can open the join link", e)
            }
        }
    }
}
