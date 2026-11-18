package io.github.fifothehein.tminus

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.shadows.ShadowAlarmManager
import org.robolectric.shadows.ShadowNotificationManager

/**
 * An AlarmManager that refuses every exact alarm, with a message that holds [LoggedErrors.SECRET] the
 * way Android's messages hold a package name or a type. Use it with `@Config(shadows = [...])`.
 */
@Implements(AlarmManager::class)
class RefusingExactAlarmsShadow : ShadowAlarmManager() {
    @Implementation
    override fun setAlarmClock(info: AlarmManager.AlarmClockInfo, operation: PendingIntent) {
        throw SecurityException("Caller needs SCHEDULE_EXACT_ALARM: ${LoggedErrors.SECRET}")
    }

    @Implementation
    override fun setExactAndAllowWhileIdle(type: Int, triggerAtMillis: Long, operation: PendingIntent) {
        throw SecurityException("Caller needs SCHEDULE_EXACT_ALARM: ${LoggedErrors.SECRET}")
    }
}

/**
 * A NotificationManager that refuses to post, as Android does without POST_NOTIFICATIONS, with a message
 * that holds [LoggedErrors.SECRET]. Use it with `@Config(shadows = [...])`.
 */
@Implements(NotificationManager::class)
class RefusingNotificationsShadow : ShadowNotificationManager() {
    @Implementation
    override fun notify(id: Int, notification: Notification) {
        throw SecurityException("Permission Denial: posting a notification needs POST_NOTIFICATIONS: ${LoggedErrors.SECRET}")
    }

    @Implementation
    override fun notify(tag: String?, id: Int, notification: Notification) {
        throw SecurityException("Permission Denial: posting a notification needs POST_NOTIFICATIONS: ${LoggedErrors.SECRET}")
    }
}
