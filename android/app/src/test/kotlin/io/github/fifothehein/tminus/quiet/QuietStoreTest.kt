package io.github.fifothehein.tminus.quiet

import android.app.Application
import android.content.Context
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

@RunWith(RobolectricTestRunner::class)
class QuietStoreTest {
    private val app: Application = RuntimeEnvironment.getApplication()
    private var now = 1_791_270_000_000L
    private lateinit var store: QuietStore

    @Before
    fun setUp() {
        app.getSharedPreferences(QuietStore.PREFS, Context.MODE_PRIVATE).edit().clear().commit()
        store = QuietStore(app) { now }
    }

    @Test
    fun `the latest request wins and take clears it`() {
        store.request(QuietStore.MUTE)
        now += 1000
        store.request(QuietStore.END)
        assertEquals(QuietStore.Request(QuietStore.END, now), store.take())
        assertNull(store.take())
    }

    @Test
    fun `a waiting mute shows on, a waiting end shows off`() {
        store.mirror(now + 3_600_000, "Until 07:00")
        store.request(QuietStore.END)
        assertFalse(store.display().active)
        store.request(QuietStore.MUTE)
        assertEquals(QuietStore.Display(true, "Muting…"), store.display())
    }

    @Test
    fun `the mirror shows on until its end`() {
        store.mirror(now + 60_000, "Until 07:00")
        assertEquals(QuietStore.Display(true, "Until 07:00"), store.display())
        now += 60_000
        assertFalse(store.display().active)
        store.mirror(null, null)
        assertFalse(store.display().active)
    }

    @Test
    fun `a tap while on asks to end, while off asks to mute`() {
        assertEquals(QuietStore.MUTE, store.actionForTap())
        store.mirror(now + 60_000, "Vacation")
        assertEquals(QuietStore.END, store.actionForTap())
    }

    @Test
    fun `two instances share one store`() {
        QuietStore(app) { now }.request(QuietStore.MUTE)
        assertTrue(store.display().active)
    }

    @Test
    fun `a taken request still shows as waiting until the next configure`() {
        // Dart is applying an end: the mirror still says on, but the tile and a second tap read it as ended.
        store.mirror(now + 3_600_000, "Until 07:00")
        store.request(QuietStore.END)
        assertEquals(QuietStore.Request(QuietStore.END, now), store.take())
        assertEquals(QuietStore.Display(false, null), store.display())
        assertEquals(QuietStore.MUTE, store.actionForTap())

        // ...and a mute being applied shows on, so a second tap asks to end it.
        store.request(QuietStore.MUTE)
        assertEquals(QuietStore.Request(QuietStore.MUTE, now), store.take())
        assertNull(store.take())
        assertEquals(QuietStore.Display(true, "Muting…"), store.display())
        assertEquals(QuietStore.END, store.actionForTap())
    }

    @Test
    fun `the next configure clears a taken request`() {
        store.request(QuietStore.MUTE)
        store.take()
        store.mirror(now + 60_000, "Until 07:00")
        assertEquals(QuietStore.Display(true, "Until 07:00"), store.display())

        store.request(QuietStore.END)
        store.take()
        store.mirror(now + 60_000, "Until 07:00")
        assertEquals(QuietStore.Display(true, "Until 07:00"), store.display())

        store.request(QuietStore.MUTE)
        store.take()
        store.mirror(null, null)
        assertEquals(QuietStore.Display(false, null), store.display())
    }

    @Test
    fun `a taken request older than ten minutes no longer shows`() {
        store.request(QuietStore.MUTE)
        now += 8 * 60_000
        store.take() // taken eight minutes after the tap
        now += 1 * 60_000
        assertEquals(QuietStore.Display(true, "Muting…"), store.display())
        // Eleven minutes after the tap, though only three after it was taken: the age counts from the tap.
        now += 2 * 60_000
        assertEquals(QuietStore.Display(false, null), store.display())
        assertEquals(QuietStore.MUTE, store.actionForTap())
    }

    @Test
    fun `a second tap while the first is being applied leaves the state matching the last tap`() {
        store.request(store.actionForTap()) // first tap: mute
        assertEquals(QuietStore.MUTE, store.take()?.action) // a sync takes it and starts applying it
        now += 1000
        assertEquals(QuietStore.END, store.actionForTap()) // the mute is on its way, so this tap ends it
        store.request(store.actionForTap())
        assertEquals(QuietStore.Display(false, null), store.display())

        // The first sync finishes with the mute in place, but the second tap is still waiting.
        store.mirror(now + 60_000, "Until 07:00")
        assertEquals(QuietStore.Display(false, null), store.display())
        // The next sync applies the end.
        assertEquals(QuietStore.Request(QuietStore.END, now), store.take())
        store.mirror(null, null)
        assertEquals(QuietStore.Display(false, null), store.display())
    }
}
