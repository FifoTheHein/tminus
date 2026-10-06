package io.github.fifothehein.tminus.engine

import android.content.Context
import android.content.res.AssetManager
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import java.io.IOException

/** IBM Plex read from the TTFs Flutter already bundles (pubspec `fonts:`), so nothing is copied into res/font. */
data class AlarmFonts(val sans: FontFamily, val mono: FontFamily) {
    companion object {
        private val weights = listOf(
            FontWeight.Normal to "Regular",
            FontWeight.Medium to "Medium",
            FontWeight.SemiBold to "SemiBold",
        )
        private val families = listOf("ibm-plex-sans" to "IBMPlexSans", "ibm-plex-mono" to "IBMPlexMono")

        fun path(dir: String, base: String, style: String): String = "flutter_assets/assets/fonts/$dir/$base-$style.ttf"

        fun allPaths(): List<String> = families.flatMap { (dir, base) -> weights.map { (_, style) -> path(dir, base, style) } }

        /** Falls back to the system family if any file is missing, so fonts can never crash the alarm screen. */
        fun load(context: Context, exists: (String) -> Boolean = { assetExists(context.assets, it) }): AlarmFonts {
            fun family(dir: String, base: String, fallback: FontFamily): FontFamily {
                val files = weights.map { (weight, style) -> weight to path(dir, base, style) }
                if (!files.all { exists(it.second) }) return fallback
                return FontFamily(files.map { (weight, file) -> Font(file, context.assets, weight) })
            }
            return AlarmFonts(
                sans = family("ibm-plex-sans", "IBMPlexSans", FontFamily.SansSerif),
                mono = family("ibm-plex-mono", "IBMPlexMono", FontFamily.Monospace),
            )
        }

        private fun assetExists(assets: AssetManager, path: String): Boolean = try {
            assets.open(path).close()
            true
        } catch (e: IOException) {
            false
        }
    }
}
