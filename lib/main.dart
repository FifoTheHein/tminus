import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/di.dart';
import 'app/font_licenses.dart';
import 'app/start_services.dart';
import 'app/sync_main.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  configureDependencies();
  // The restore check first, then everything else that starts with the app:
  // see startServices for the order and for what an unsafe restore changes.
  await startServices();
  runApp(const TMinusApp());
}

/// The headless sync engine's entry point (`HeadlessFlutterRunner.ENTRYPOINT`).
/// It must stay in this library: the engine looks it up in the app's main
/// library, and `vm:entry-point` keeps release builds from tree-shaking it.
@pragma('vm:entry-point')
Future<void> syncMain(List<String> args) => runHeadlessSync(args);
