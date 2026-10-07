package io.github.fifothehein.tminus.engine

import android.app.Activity
import android.content.Intent

/**
 * Opening T-Minus while an alarm rings goes to the alarm screen (from the launcher or a recents card),
 * so there is a stop even when notifications or full-screen intents are blocked. Call [attach] from
 * the activity's onResume and [detach] from its onPause. While attached, a session that is ringing,
 * or starts ringing (after a crash the session fills only once RingingService starts), opens it.
 */
class AlarmScreenRoute(private val activity: Activity) {
    private var unsubscribe: (() -> Unit)? = null

    fun attach() {
        detach()
        unsubscribe = RingingSession.observe { if (it.isNotEmpty()) open() }
        if (RingingSession.alerts.isNotEmpty()) open()
    }

    fun detach() {
        unsubscribe?.invoke()
        unsubscribe = null
    }

    private fun open() {
        // AlarmActivity is singleInstance in its own task, so a second start reuses it.
        activity.startActivity(Intent(activity, AlarmActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
