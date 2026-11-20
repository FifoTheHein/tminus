package io.github.fifothehein.tminus.engine

/**
 * The meeting service behind a join link, named from the link's host and path alone.
 *
 * Dart has already found and decoded the link (`extractJoinUrl` in ics_core) and passes it on as
 * `joinUrl`. [of] is the Kotlin twin of ics_core's `meetingServiceOf`: the two name every link the
 * same way. Pure Kotlin, so it runs in plain JUnit.
 */
enum class MeetingService(val label: String) {
    TEAMS("Teams"),
    GOOGLE_MEET("Google Meet"),
    ZOOM("Zoom"),
    WEBEX("Webex");

    companion object {
        private const val HTTPS = "https://"

        /**
         * The service [url] is a join link of, or null for null and for any other link. Never throws:
         * a malformed link is simply not a join link.
         *
         * Only `https` links count, and the scheme, the host and the fixed path words are compared
         * ignoring case:
         * - Teams: `teams.microsoft.com` with `/l/meetup-join/...` or `/meet/...`; `/meet/<digits>`
         *   on `teams.cloud.microsoft` and `teams.live.com`.
         * - Google Meet: `meet.google.com/<3 letters>-<4 letters>-<3 letters>`.
         * - Zoom: `zoom.us`, `zoom.com` or any subdomain of them, with `/j/<digits>`, `/my/<name>`
         *   or `/w/<digits>`.
         * - Webex: any subdomain of `webex.com`, with `.../j.php?MTID=<id>`, `/meet/<id>` or
         *   `/join/<id>`.
         *
         * A query may follow, and a fragment is ignored. Anything else on those hosts (a download
         * page, a home page, a Meet address without a code) is not a join link.
         */
        fun of(url: String?): MeetingService? {
            if (url == null || !url.startsWith(HTTPS, ignoreCase = true)) return null
            if (url.any { it.isWhitespace() || it.isISOControl() }) return null

            // "host/path?query#fragment": the fragment never decides anything.
            val rest = url.substring(HTTPS.length).substringBefore('#')
            val hostEnd = rest.indexOfAny(charArrayOf('/', '?')).let { if (it < 0) rest.length else it }
            val hostPart = rest.substring(0, hostEnd)
            if (!isHostName(hostPart)) return null
            val host = hostPart.lowercase()
            val tail = rest.substring(hostEnd)
            val path = tail.substringBefore('?')
            val query = if ('?' in tail) tail.substringAfter('?') else null

            return when {
                host == "teams.microsoft.com" ->
                    if (after(path, "/l/meetup-join/").isNotEmpty() || after(path, "/meet/").isNotEmpty()) TEAMS else null
                host == "teams.cloud.microsoft" || host == "teams.live.com" ->
                    if (after(path, "/meet/").isDigits()) TEAMS else null
                host == "meet.google.com" ->
                    if (after(path, "/").isMeetCode()) GOOGLE_MEET else null
                host.isDomainOrSubdomain("zoom.us") || host.isDomainOrSubdomain("zoom.com") ->
                    if (isZoomPath(path)) ZOOM else null
                host.endsWith(".webex.com") ->
                    if (isWebexPath(path, query)) WEBEX else null
                else -> null
            }
        }

        /** What follows [prefix] in [path] (the prefix compared ignoring case), or "" when [path] does not start with it. */
        private fun after(path: String, prefix: String): String =
            if (path.startsWith(prefix, ignoreCase = true)) path.substring(prefix.length) else ""

        private fun isZoomPath(path: String): Boolean =
            after(path, "/j/").isDigits() || after(path, "/w/").isDigits() || after(path, "/my/").isSegment()

        private fun isWebexPath(path: String, query: String?): Boolean =
            after(path, "/meet/").isSegment() ||
                after(path, "/join/").isSegment() ||
                (path.endsWith("/j.php", ignoreCase = true) && hasMeetingId(query))

        /** True when [query] starts with `MTID=<id>`, with or without more parameters after it. */
        private fun hasMeetingId(query: String?): Boolean =
            query != null &&
                query.startsWith("MTID=", ignoreCase = true) &&
                query.substring("MTID=".length).substringBefore('&').isNotEmpty()

        /** A plain DNS name: dot-separated, non-empty labels of ASCII letters, digits and hyphens (no port, no user info). */
        private fun isHostName(host: String): Boolean =
            host.split('.').all { label -> label.isNotEmpty() && label.all { it.isAsciiLetter() || it in '0'..'9' || it == '-' } }

        private fun String.isDomainOrSubdomain(domain: String): Boolean = this == domain || endsWith(".$domain")

        private fun String.isDigits(): Boolean = isNotEmpty() && all { it in '0'..'9' }

        /** One path segment: not empty, and no slash. */
        private fun String.isSegment(): Boolean = isNotEmpty() && '/' !in this

        /** "abc-defg-hij": three, four and three letters joined by hyphens. */
        private fun String.isMeetCode(): Boolean {
            val groups = split('-')
            return groups.size == 3 &&
                groups[0].length == 3 && groups[1].length == 4 && groups[2].length == 3 &&
                groups.all { group -> group.all { it.isAsciiLetter() } }
        }

        private fun Char.isAsciiLetter(): Boolean = this in 'a'..'z' || this in 'A'..'Z'
    }
}
