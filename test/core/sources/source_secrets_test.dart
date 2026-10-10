import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/sources/source_secrets.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('a link is written, read back and deleted by its key', () async {
    final secrets = SourceSecrets();
    final key = SourceSecrets.keyFor('work');
    expect(key, 'ics-url.work');
    expect(await secrets.readUrl(key), isNull);
    await secrets.writeUrl(key, 'https://example.com/a.ics');
    expect(await secrets.readUrl(key), 'https://example.com/a.ics');
    await secrets.delete(key);
    expect(await secrets.readUrl(key), isNull);
  });
}
