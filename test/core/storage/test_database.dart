import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:tminus/core/storage/app_database.dart';

/// A fresh in-memory database. Close it in tearDown.
///
/// `closeStreamsSynchronously` keeps drift from leaving a timer behind when a
/// watch stream is cancelled, which Flutter's test binding reports as a
/// pending-timer failure.
AppDatabase openTestDatabase() => AppDatabase(
  DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
);

/// Yields to the event loop until [condition] holds (for watch streams).
/// Fails after [timeout] instead of hanging.
Future<void> waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}
