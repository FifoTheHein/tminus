package io.github.fifothehein.tminus.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ToneFallbackTest {
    @Test
    fun `the first tone that opens wins`() {
        assertEquals(0 to "custom", ToneFallback.firstPlayable(listOf("custom", "default")) { it })
    }

    @Test
    fun `a missing custom tone falls back to the default alarm tone`() {
        val opened = ToneFallback.firstPlayable(listOf("content://gone", "alarm-default")) { uri ->
            if (uri == "content://gone") throw java.io.FileNotFoundException(uri) else "player:$uri"
        }
        assertEquals(1 to "player:alarm-default", opened)
    }

    @Test
    fun `nothing playable gives null`() {
        assertNull(ToneFallback.firstPlayable(listOf("a", "b")) { throw IllegalStateException(it) })
        assertNull(ToneFallback.firstPlayable(emptyList<String>()) { it })
    }
}
