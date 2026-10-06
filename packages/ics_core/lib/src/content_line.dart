/// One unfolded iCalendar content line: `NAME;PARAM=VALUE:value`.
class ContentLine {
  const ContentLine(this.name, this.params, this.value, this.line);

  /// Property name, upper-case.
  final String name;

  /// Parameter names upper-case; values with their double quotes removed.
  final Map<String, String> params;

  /// Raw value after the first unquoted colon (not unescaped).
  final String value;

  /// 1-based line number in the unfolded text.
  final int line;
}

/// Splits [text] into unfolded lines (RFC 5545 §3.1).
///
/// Accepts CRLF, LF or CR line breaks. A line starting with a space or tab
/// continues the previous line (that one whitespace character is removed).
/// A leading byte-order mark is dropped. Blank lines are kept so line
/// numbers stay stable.
List<String> unfoldLines(String text) {
  var normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (normalized.startsWith('﻿')) {
    normalized = normalized.substring(1);
  }
  final lines = <String>[];
  for (final raw in normalized.split('\n')) {
    if (lines.isNotEmpty && (raw.startsWith(' ') || raw.startsWith('\t'))) {
      lines[lines.length - 1] = lines.last + raw.substring(1);
    } else {
      lines.add(raw);
    }
  }
  return lines;
}

/// Parses one unfolded line. Returns null for blank or malformed lines
/// (no name, or no unquoted colon).
ContentLine? parseContentLine(String raw, int line) {
  final n = raw.length;
  var i = 0;
  while (i < n && raw[i] != ';' && raw[i] != ':') {
    i++;
  }
  if (i == 0 || i >= n) {
    return null;
  }
  final name = raw.substring(0, i).trim().toUpperCase();
  final params = <String, String>{};
  while (i < n && raw[i] == ';') {
    i++;
    final keyStart = i;
    while (i < n && raw[i] != '=' && raw[i] != ';' && raw[i] != ':') {
      i++;
    }
    final key = raw.substring(keyStart, i).trim().toUpperCase();
    final value = StringBuffer();
    if (i < n && raw[i] == '=') {
      i++;
      var inQuotes = false;
      while (i < n) {
        final c = raw[i];
        if (c == '"') {
          inQuotes = !inQuotes;
        } else if (!inQuotes && (c == ';' || c == ':')) {
          break;
        } else {
          value.write(c);
        }
        i++;
      }
    }
    if (key.isNotEmpty) {
      params[key] = value.toString();
    }
  }
  if (i >= n || raw[i] != ':' || name.isEmpty) {
    return null;
  }
  return ContentLine(name, params, raw.substring(i + 1), line);
}

/// Unescapes a TEXT value: `\\` `\;` `\,` `\n` `\N`.
String unescapeText(String value) {
  final out = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    final c = value[i];
    if (c == r'\' && i + 1 < value.length) {
      final next = value[i + 1];
      switch (next) {
        case 'n' || 'N':
          out.write('\n');
          i++;
        case r'\' || ';' || ',':
          out.write(next);
          i++;
        default:
          out.write(c);
      }
    } else {
      out.write(c);
    }
  }
  return out.toString();
}
