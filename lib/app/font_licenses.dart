import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds the bundled IBM Plex OFL licences to the app's licence page.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (package, path) in [
      ('IBM Plex Sans', 'assets/fonts/ibm-plex-sans/OFL.txt'),
      ('IBM Plex Mono', 'assets/fonts/ibm-plex-mono/OFL.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        package,
      ], await rootBundle.loadString(path));
    }
  });
}
