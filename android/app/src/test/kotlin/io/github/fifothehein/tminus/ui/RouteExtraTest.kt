package io.github.fifothehein.tminus.ui

import android.content.Intent
import android.os.BadParcelableException
import io.github.fifothehein.tminus.sync.SyncNotifications
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class RouteExtraTest {
    private fun intent(value: String?) = Intent().apply { if (value != null) putExtra(SyncNotifications.EXTRA_ROUTE, value) }

    @Test
    fun `a source route is accepted`() {
        assertEquals("/sources/ics-0a1b2c3d4e5f", RouteExtra.from(intent("/sources/ics-0a1b2c3d4e5f")))
    }

    @Test
    fun `anything else is dropped`() {
        listOf(
            "/settings/developer",
            "/sources/",
            "/sources/a/b",
            "/sources/../settings",
            "/sources/abc?x=1",
            "/sources/abc#frag",
            "sources/abc",
            "/sources/add",
            "/sources/" + "a".repeat(65),
            "",
        ).forEach { assertNull(it, RouteExtra.from(intent(it))) }
    }

    @Test
    fun `no intent or no extra gives null`() {
        assertNull(RouteExtra.from(null))
        assertNull(RouteExtra.from(intent(null)))
    }

    @Test
    fun `an extra whose parcel throws is dropped`() {
        // Reading an extra unparcels the whole bundle, and another app can send one that cannot be read.
        val unreadable = object : Intent() {
            override fun getStringExtra(name: String?): String? = throw BadParcelableException("unreadable")
        }
        assertNull(RouteExtra.from(unreadable))
    }
}
