package io.github.fifothehein.tminus

import org.json.JSONObject
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.robolectric.shadows.ShadowLog

/**
 * What a logged error may hold. CLAUDE.md: never log error messages, URLs or event content; log the
 * exception's class only. A test that uses this plants [SECRET] where an exception's message (or the
 * text a parser quotes) would hold a link or an event's text, calls [ShadowLog.clear], runs the failing
 * code, then calls [assertClassOnly].
 */
object LoggedErrors {
    /** Stands for a link or an event's text. No message in the app holds it by chance. */
    const val SECRET = "planted-secret-7f3a9c"

    /** The message of the parse error that [text] causes: the JSON tokenizer quotes all of its input. */
    fun jsonParseError(text: String): String = runCatching { JSONObject(text) }.exceptionOrNull()?.message.orEmpty()

    /**
     * Every log line that holds [phrase] (a call's fixed wording) names [errorClass] and carries no
     * throwable, so no trace. No line in the whole log, with or without a throwable, holds any of
     * [forbidden].
     */
    fun assertClassOnly(phrase: String, errorClass: String, forbidden: List<String> = listOf(SECRET)) {
        val logs = ShadowLog.getLogs()
        val lines = logs.filter { it.msg.orEmpty().contains(phrase) }
        assertTrue("nothing was logged with \"$phrase\"", lines.isNotEmpty())
        lines.forEach { line ->
            assertTrue("the class is logged: ${line.msg}", line.msg.contains(errorClass))
            assertNull("no trace is logged", line.throwable)
        }
        forbidden.forEach { text ->
            val leaks = logs.any { text in it.msg.orEmpty() || it.throwable?.toString()?.contains(text) == true }
            assertTrue("\"$text\" is never logged", !leaks)
        }
    }
}
