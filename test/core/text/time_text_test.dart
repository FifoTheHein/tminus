import 'package:flutter_test/flutter_test.dart';
import 'package:tminus/core/model/local_date.dart';
import 'package:tminus/core/text/time_text.dart';

import '../fixtures.dart';

void main() {
  final now = DateTime.utc(2026, 10, 6, 7, 27); // Tue 09:27 in Johannesburg

  test('hm, range and day', () {
    expect(
      TimeText.hm(DateTime.utc(2026, 10, 6, 7, 50), johannesburg),
      '09:50',
    );
    expect(
      TimeText.range(
        DateTime.utc(2026, 10, 6, 8),
        DateTime.utc(2026, 10, 6, 9),
        johannesburg,
      ),
      '10:00–11:00',
    );
    expect(TimeText.day(LocalDate(2026, 10, 6)), 'Tue 6 Oct');
    expect(TimeText.dayUpper(LocalDate(2026, 10, 6)), 'TUE 6 OCT');
  });

  test('day titles: Today, Tomorrow, then the weekday and date', () {
    final today = LocalDate(2026, 10, 6);
    expect(TimeText.dayTitle(today, today), 'Today');
    expect(TimeText.dayTitle(today.addDays(1), today), 'Tomorrow');
    expect(TimeText.dayTitle(today.addDays(2), today), 'Thu 8 Oct');
  });

  test('ago', () {
    expect(TimeText.ago(now, now), 'just now');
    expect(
      TimeText.ago(now.subtract(const Duration(seconds: 59)), now),
      'just now',
    );
    expect(
      TimeText.ago(now.subtract(const Duration(minutes: 4)), now),
      '4 min ago',
    );
    expect(
      TimeText.ago(now.subtract(const Duration(minutes: 61)), now),
      '1 h ago',
    );
    expect(
      TimeText.ago(now.subtract(const Duration(hours: 49)), now),
      '2 days ago',
    );
    expect(
      TimeText.ago(now.subtract(const Duration(hours: 25)), now),
      '1 day ago',
    );
  });

  test('countdown: minutes, hours and minutes, then day and time', () {
    String c(Duration d) => TimeText.countdown(now.add(d), now, johannesburg);
    expect(c(const Duration(minutes: 23)), '23 min');
    expect(c(const Duration(seconds: 30)), '1 min'); // rounds up: never "0 min"
    expect(c(const Duration(minutes: 65)), '1 h 05');
    expect(c(const Duration(hours: 23, minutes: 59)), '23 h 59');
    expect(c(const Duration(hours: 26)), 'Wed 11:27');
  });
}
