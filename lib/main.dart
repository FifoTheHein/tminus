import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/di.dart';
import 'app/font_licenses.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  configureDependencies();
  runApp(const TMinusApp());
}
