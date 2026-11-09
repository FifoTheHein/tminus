import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/quiet_state.dart';
import 'package:tminus/core/storage/app_database.dart';
import 'package:tminus/core/storage/settings_repository.dart';

import '../fixtures.dart';
import 'test_database.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository settings;

  setUp(() {
    initZones();
    db = openTestDatabase();
    settings = SettingsRepository(db);
  });

  tearDown(() => db.close());

  test('setQuietStateAt stores the state and its time', () async {
    final at = DateTime.utc(2026, 10, 6, 6);
    final mute = QuietState.muteToday(nowUtc: at, zone: johannesburg);

    await settings.setQuietStateAt(mute, changedAtUtc: at);

    expect(await settings.quietState(), mute);
    expect(await settings.quietChangedAt(), at);
  });

  test('no change recorded reads as null', () async {
    expect(await settings.quietChangedAt(), isNull);

    // The plain setter records no time either.
    await settings.setQuietState(const QuietNone());
    expect(await settings.quietChangedAt(), isNull);
  });
}
