package io.github.fifothehein.tminus.ui

import android.content.Intent
import io.github.fifothehein.tminus.sync.SyncNotifications

/**
 * The Feed broken notice's Fix opens `/sources/<id>` (Plan 4). MainActivity is exported, so any app
 * can send this extra: only that one shape is honoured, and an extra whose parcel cannot be read
 * (BadParcelableException and friends) is dropped.
 */
object RouteExtra {
    private val ALLOWED = Regex("^/sources/(?!add$)[A-Za-z0-9-]{1,64}$")

    fun from(intent: Intent?): String? {
        val value = try {
            intent?.getStringExtra(SyncNotifications.EXTRA_ROUTE)
        } catch (e: RuntimeException) {
            null
        }
        return value?.takeIf(ALLOWED::matches)
    }
}
