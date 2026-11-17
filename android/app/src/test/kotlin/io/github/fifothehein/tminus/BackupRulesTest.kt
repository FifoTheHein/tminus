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

    /** The requireFlags of each include in an XML resource, in file order: null for an include that has none. */
    private fun includeFlags(resId: Int): List<String?> {
        val out = mutableListOf<String?>()
        val xml = app.resources.getXml(resId)
        while (xml.next() != XmlPullParser.END_DOCUMENT) {
            if (xml.eventType == XmlPullParser.START_TAG && xml.name == "include") {
                out += xml.getAttributeValue(null, "requireFlags")
            }
        }
        return out
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

    /** The cache database and the two files that SQLite keeps beside it in WAL mode, as paths under the root domain. */
    private val cacheFiles = listOf(
        "app_flutter/tminus_cache.sqlite",
        "app_flutter/tminus_cache.sqlite-wal",
        "app_flutter/tminus_cache.sqlite-shm",
    )

    /**
     * Whether [include] backs [file] up: it names the file, or a folder above it, in the root domain. These are
     * include-only lists, so a file that no include reaches is left out.
     */
    private fun reaches(include: Triple<String, String, String>, file: String): Boolean {
        val (_, domain, path) = include
        if (domain != "root") return false
        val folder = path.replace('\\', '/').trim('/').removePrefix("./")
        return folder.isEmpty() || folder == "." || file == folder || file.startsWith("$folder/")
    }

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
     * Android 9 to 11 read backup_rules.xml and back the database up only when the backup is encrypted end to end,
     * the counterpart of disableIfNoEncryptionCapabilities on Android 12 and up. Android 8 ignores the flag, which
     * is accepted: after the cache move the backup holds no meetings and no links (Plan 6 decision 20).
     */
    @Test
    fun `backups below Android 12 need encryption`() {
        assertEquals(
            "requireFlags on each include in backup_rules.xml",
            database.map { "clientSideEncryption" },
            includeFlags(R.xml.backup_rules),
        )
    }

    /**
     * The cache database holds meeting titles, places and Teams links, and it is the file that Plan 6 moved out of
     * the backed-up database. No include in any rule set may name it, its WAL or its shared-memory file, or a folder
     * above them such as app_flutter or the whole root domain.
     */
    @Test
    fun `the cache database is never backed up`() {
        val ruleSets = mapOf(
            "data_extraction_rules.xml cloud-backup" to
                rules(R.xml.data_extraction_rules).filter { it.first == "cloud-backup/include" },
            "data_extraction_rules.xml device-transfer" to
                rules(R.xml.data_extraction_rules).filter { it.first == "device-transfer/include" },
            "backup_rules.xml" to rules(R.xml.backup_rules).filter { it.first == "/include" },
        )
        for ((name, includes) in ruleSets) {
            // The same matcher must see the database, or this test would pass for any rule set.
            for ((_, databaseFile) in database) {
                assertTrue("$name does not reach $databaseFile", includes.any { reaches(it, databaseFile) })
            }
            for (file in cacheFiles) {
                val reaching = includes.filter { reaches(it, file) }
                assertTrue("$name reaches $file through $reaching", reaching.isEmpty())
            }
        }
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
