import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/sources/feed_body_cache.dart';

void main() {
  late Directory dir;
  late FeedBodyCache cache;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('feeds');
    cache = FeedBodyCache(() async => dir);
  });

  tearDown(() => dir.delete(recursive: true));

  test('a body is stored per source and read back', () async {
    expect(await cache.read('work'), isNull);
    await cache.write('work', 'BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n');
    await cache.write('home', 'other');
    expect(await cache.read('work'), 'BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n');
    expect(await cache.read('home'), 'other');
  });

  test(
    'a new body replaces the old one and leaves no temporary file',
    () async {
      await cache.write('work', 'old');
      await cache.write('work', 'new');
      expect(await cache.read('work'), 'new');
      expect(dir.listSync().map((f) => f.uri.pathSegments.last), ['work.ics']);
    },
  );

  test('delete removes the body; deleting a missing one is fine', () async {
    await cache.write('work', 'x');
    await cache.delete('work');
    await cache.delete('work');
    expect(await cache.read('work'), isNull);
  });

  test('a source id cannot escape the directory', () async {
    await cache.write('../evil/id', 'x');
    expect(dir.listSync().map((f) => f.uri.pathSegments.last), [
      '___evil_id.ics',
    ]);
  });

  test('the directory is created on first write', () async {
    final nested = Directory('${dir.path}${Platform.pathSeparator}feeds');
    final c = FeedBodyCache(() async => nested);
    await c.write('work', 'x');
    expect(await c.read('work'), 'x');
  });
}
