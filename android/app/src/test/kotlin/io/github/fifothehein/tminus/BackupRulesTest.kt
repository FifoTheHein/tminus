package io.github.fifothehein.tminus

import android.util.Xml
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.xmlpull.v1.XmlPullParser
import java.io.File
import java.util.Properties

private const val ANDROID_NS = "http://schemas.android.com/apk/res/android"

@RunWith(RobolectricTestRunner::class)
class BackupRulesTest {
    private val app = RuntimeEnvironment.getApplication()

    /** (section, domain, path) for every include and exclude in an XML resource. */
    private fun rules(resId: Int): List<Triple<String, String, String>> {
        val out = mutableListOf<Triple<String, String, String>>()
        val xml = app.resources.getXml(resId)
        var section = ""
        while (xml.next() != XmlPullParser.END_DOCUMENT) {
            if (xml.eventType != XmlPullParser.START_TAG) continue
            when (xml.name) {
                "cloud-backup", "device-transfer" -> section = xml.name
                "include", "exclude" -> out += Triple(
                    "$section/${xml.name}",
                    xml.getAttributeValue(null, "domain"),
                    xml.getAttributeValue(null, "path"),
                )
            }
        }
        return out
    }

    /** The value of [name] on the first [tag] element of an XML resource, or null if either is missing. */
    private fun attribute(resId: Int, tag: String, name: String): String? {
        val xml = app.resources.getXml(resId)
        while (xml.next() != XmlPullParser.END_DOCUMENT) {
            if (xml.eventType == XmlPullParser.START_TAG && xml.name == tag) {
                return xml.getAttributeValue(null, name)
            }
        }
        return null
    }

    /**
     * The manifest this run is built from: the merged one that the Android Gradle plugin names in
     * test_config.properties (the file Robolectric loads). Only when that property is absent does it use the
     * module's own. A merged manifest that is named but missing fails the test instead of falling back,
     * because the source manifest would hide anything a plugin overrides in the merge. Gradle runs unit tests
     * in the module directory (android/app), so both paths are relative to it.
     */
    private fun manifestFile(): File {
        val config = Properties()
        javaClass.classLoader?.getResourceAsStream("com/android/tools/test_config.properties")
            ?.use { config.load(it) }
        val merged = config.getProperty("android_merged_manifest")
        val manifest = File(merged ?: "src/main/AndroidManifest.xml")
        val named = if (merged != null) "android_merged_manifest" else "the source manifest (no android_merged_manifest)"
        assertTrue("$named is not a file: ${manifest.absolutePath}", manifest.isFile)
        return manifest
    }

    /** The android: attributes on the application element of a text manifest, by local name. */
    private fun applicationAttributes(manifest: File): Map<String, String> {
        val parser = Xml.newPullParser()
        parser.setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, true)
        manifest.reader(Charsets.UTF_8).use { reader ->
            parser.setInput(reader)
            while (parser.next() != XmlPullParser.END_DOCUMENT) {
                if (parser.eventType == XmlPullParser.START_TAG && parser.name == "application") {
                    return (0 until parser.attributeCount)
                        .filter { parser.getAttributeNamespace(it) == ANDROID_NS }
                        .associate { parser.getAttributeName(it) to parser.getAttributeValue(it) }
                }
            }
        }
        throw AssertionError("No application element in $manifest")
    }

    private val database = listOf("root" to "app_flutter/tminus.sqlite", "root" to "app_flutter/tminus.sqlite-wal")

    @Test
    fun `both sections include only the database`() {
        val r = rules(R.xml.data_extraction_rules)
        for (section in listOf("cloud-backup", "device-transfer")) {
            assertEquals(database, r.filter { it.first == "$section/include" }.map { it.second to it.third })
        }
        assertTrue(r.none { it.first.endsWith("/exclude") })
        // Meeting titles and Teams links are personal data: back up to the cloud only when it is end-to-end encrypted.
        assertEquals(
            "disableIfNoEncryptionCapabilities on cloud-backup",
            "true",
            attribute(R.xml.data_extraction_rules, "cloud-backup", "disableIfNoEncryptionCapabilities"),
        )
    }

    @Test
    fun `the pre-12 rules include only the database`() {
        assertEquals(database, rules(R.xml.backup_rules).map { it.second to it.third })
        // The kind counts too: a file of excludes backs up everything else by default, secure-storage prefs included.
        assertEquals(database.map { Triple("/include", it.first, it.second) }, rules(R.xml.backup_rules))
    }

    /**
     * The two rule files only count if the manifest points at them. Without that the platform default
     * applies and backs up almost everything, including the secure-storage prefs that hold the ICS links.
     */
    @Test
    fun `the app backs up only through these rules`() {
        val manifest = manifestFile()
        val application = applicationAttributes(manifest)
        assertEquals("android:allowBackup in $manifest", "true", application["allowBackup"])
        assertEquals("android:fullBackupContent in $manifest", "@xml/backup_rules", application["fullBackupContent"])
        assertEquals(
            "android:dataExtractionRules in $manifest",
            "@xml/data_extraction_rules",
            application["dataExtractionRules"],
        )
    }
}
