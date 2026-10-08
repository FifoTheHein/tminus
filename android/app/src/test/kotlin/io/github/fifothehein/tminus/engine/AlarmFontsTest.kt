package io.github.fifothehein.tminus.engine

import android.content.Context
import androidx.compose.ui.text.font.FontFamily
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import java.io.File

@RunWith(RobolectricTestRunner::class)
class AlarmFontsTest {
    private val context: Context = RuntimeEnvironment.getApplication()

    @Test
    fun `missing font files fall back to the system families`() {
        val fonts = AlarmFonts.load(context) { false }
        assertEquals(FontFamily.SansSerif, fonts.sans)
        assertEquals(FontFamily.Monospace, fonts.mono)
    }

    @Test
    fun `one missing weight is enough to fall back for that family`() {
        val fonts = AlarmFonts.load(context) { !it.endsWith("IBMPlexMono-SemiBold.ttf") }
        assertEquals(FontFamily.Monospace, fonts.mono)
        assertNotEquals(FontFamily.SansSerif, fonts.sans)
    }

    @Test
    fun `paths point at the TTFs Flutter bundles`() {
        assertEquals(
            "flutter_assets/assets/fonts/ibm-plex-mono/IBMPlexMono-Medium.ttf",
            AlarmFonts.path("ibm-plex-mono", "IBMPlexMono", "Medium"),
        )
    }

    @Test
    fun `every path names a font that exists in the Flutter project`() {
        // Gradle runs unit tests in android/app, so the repo root is two levels up.
        AlarmFonts.allPaths().forEach { path ->
            val source = File("../../" + path.removePrefix("flutter_assets/"))
            assertTrue("$path -> ${source.canonicalPath}", source.exists())
        }
    }
}
