package io.github.fifothehein.tminus.sync

import android.content.Context
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.channels.FileChannel
import java.nio.file.Files
import java.nio.file.NoSuchFileException
import java.nio.file.StandardCopyOption
import java.nio.file.StandardOpenOption
import java.util.UUID

/**
 * A random id for this installation, kept in `noBackupFilesDir`, which Android never backs up or
 * transfers (Plan 5 decision 4). Dart compares it with the id stored in the database to tell a
 * restored backup from an upgrade.
 *
 * The UI engine and every headless sync engine build their own [InstallId] inside one process, so the
 * lock is shared by all instances: with one lock each, two first starts could both mint an id, one
 * would be overwritten, and the next start would take this phone for a restored one and wipe it. A new
 * id is written to a temporary file and renamed into place, so nobody ever reads half an id, and the
 * directory is flushed afterwards where the platform allows it, so the rename survives a power cut. A
 * file that is there but cannot be read, or holds no id, is an error and is never replaced: Dart's
 * guard logs the error and starts normally.
 *
 * [readBytes] reads the file and must throw [NoSuchFileException], and nothing else, when there is no
 * file; tests replace it to make a file unreadable. [newId] is last, so a test can pass it as a
 * trailing lambda.
 */
class InstallId(
    context: Context,
    private val readBytes: (File) -> ByteArray = { Files.readAllBytes(it.toPath()) },
    private val newId: () -> String = { UUID.randomUUID().toString() },
) {
    private val dir = context.noBackupFilesDir
    private val file = File(dir, FILE_NAME)
    private val temp = File(dir, TEMP_NAME)

    fun get(): String = synchronized(LOCK) {
        read() ?: newId().also { write(it) }
    }

    /** The stored id, or null when there is no file at all. */
    private fun read(): String? {
        val bytes = try {
            readBytes(file)
        } catch (e: NoSuchFileException) {
            return null
        }
        val id = String(bytes, Charsets.UTF_8).trim()
        if (id.isEmpty()) throw IOException("The install id file holds no id")
        return id
    }

    private fun write(id: String) {
        try {
            FileOutputStream(temp).use { out ->
                out.write(id.toByteArray(Charsets.UTF_8))
                out.fd.sync()
            }
            Files.move(temp.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE)
            flushDir()
        } finally {
            temp.delete() // a no-op once the rename has happened
        }
    }

    /**
     * Makes the rename durable. Until the directory itself is flushed, a power cut can undo it, and the
     * next start would mint a second id and take this phone for a restored one. Opening a directory for
     * reading is refused on some hosts (Windows, where the unit tests may run).
     */
    private fun flushDir() {
        try {
            FileChannel.open(dir.toPath(), StandardOpenOption.READ).use { it.force(true) }
        } catch (e: IOException) {
            // Best effort: the id is already in place and readable, so a refused flush must not turn a
            // good write into an error. Not logged: the message holds a path.
        }
    }

    companion object {
        const val FILE_NAME = "install_id"
        const val TEMP_NAME = "install_id.tmp"

        /** One lock for every instance in the process. */
        private val LOCK = Any()
    }
}
