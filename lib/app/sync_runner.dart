import '../core/sync/sync_service.dart';

/// Runs a sync that fetches: pull-to-refresh, Sync now, after adding or
/// re-linking a source. A seam, so screen tests need no real sync: the test
/// harness registers a recording fake.
typedef SyncRunner = Future<SyncReport> Function(SyncTrigger trigger);
