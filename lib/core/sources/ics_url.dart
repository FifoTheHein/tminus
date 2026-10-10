/// What [IcsUrl.check] makes of a pasted link.
sealed class IcsUrlCheck {
  const IcsUrlCheck();
}

class IcsUrlAccepted extends IcsUrlCheck {
  const IcsUrlAccepted(this.url, {required this.insecure});

  /// The link to store and fetch: trimmed, `webcal://` rewritten to `https://`.
  final String url;

  /// Plain `http://`: the secret link travels unencrypted. Plan 5 shows a
  /// warning when this is true.
  final bool insecure;
}

class IcsUrlRejected extends IcsUrlCheck {
  const IcsUrlRejected(this.message);
  final String message;
}

/// Rules for published-calendar links (spec §5, §10).
abstract final class IcsUrl {
  static IcsUrlCheck check(String input) {
    var text = input.trim();
    if (text.isEmpty) return const IcsUrlRejected('Paste the calendar link.');
    final lower = text.toLowerCase();
    if (lower.startsWith('webcal://')) {
      text = 'https://${text.substring('webcal://'.length)}';
    }
    final uri = Uri.tryParse(text);
    final scheme = uri?.scheme.toLowerCase();
    if (uri == null ||
        (scheme != 'https' && scheme != 'http') ||
        uri.host.isEmpty) {
      return const IcsUrlRejected(
        'That is not a calendar link. It should start with https://.',
      );
    }
    if (uri.path.toLowerCase().endsWith('.html')) {
      return const IcsUrlRejected(
        'That is the web page link. Copy the link that ends in .ics instead.',
      );
    }
    return IcsUrlAccepted(text, insecure: scheme == 'http');
  }

  /// `outlook.office365.com/…/calendar.ics`: the host, and the last path
  /// segment only when it is an `.ics` file name (brief §5). Any other last
  /// segment shows as `host/…`, because some providers (iCloud) put the secret
  /// token there. The secret parts never reach the screen.
  static String mask(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return '…';
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return uri.host;
    final last = segments.last;
    if (!last.toLowerCase().endsWith('.ics')) return '${uri.host}/…';
    if (segments.length == 1) return '${uri.host}/$last';
    return '${uri.host}/…/$last';
  }
}
