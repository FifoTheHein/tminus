import 'content_line.dart';
import 'model.dart';

/// A BEGIN/END block such as VCALENDAR, VEVENT, VTIMEZONE or STANDARD.
class Component {
  Component(this.name, this.line);

  /// Upper-case component name, e.g. `VEVENT`.
  final String name;

  /// 1-based line in the unfolded text where `BEGIN:` appeared.
  final int line;
  final List<ContentLine> properties = [];
  final List<Component> children = [];

  /// False when the text ended (or an outer END came) before this block's END.
  bool terminated = false;

  /// The first property called [name], or null.
  ContentLine? first(String name) {
    for (final p in properties) {
      if (p.name == name) {
        return p;
      }
    }
    return null;
  }

  /// Every property called [name], in order.
  Iterable<ContentLine> all(String name) =>
      properties.where((p) => p.name == name);
}

/// Unfolds [icsText] and builds the component tree of its first VCALENDAR.
///
/// Throws [IcsFormatException] if there is no `BEGIN:VCALENDAR`.
/// Unterminated blocks are kept with [Component.terminated] false so the
/// caller can report them; lines outside the calendar are ignored.
Component parseCalendar(String icsText) {
  final lines = unfoldLines(icsText);
  Component? root;
  final stack = <Component>[];
  for (var index = 0; index < lines.length; index++) {
    final cl = parseContentLine(lines[index], index + 1);
    if (cl == null) {
      continue;
    }
    if (cl.name == 'BEGIN') {
      final component = Component(cl.value.trim().toUpperCase(), cl.line);
      if (stack.isEmpty) {
        if (root != null || component.name != 'VCALENDAR') {
          continue;
        }
        root = component;
      } else {
        stack.last.children.add(component);
      }
      stack.add(component);
    } else if (cl.name == 'END') {
      final name = cl.value.trim().toUpperCase();
      final at = stack.lastIndexWhere((c) => c.name == name);
      if (at < 0) {
        continue;
      }
      stack[at].terminated = true;
      stack.removeRange(at, stack.length);
      if (stack.isEmpty) {
        break;
      }
    } else if (stack.isNotEmpty) {
      stack.last.properties.add(cl);
    }
  }
  if (root == null) {
    throw const IcsFormatException('Not an iCalendar feed: no BEGIN:VCALENDAR');
  }
  return root;
}
