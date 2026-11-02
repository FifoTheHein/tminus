import 'package:flutter/widgets.dart';

import '../token_preview/token_preview_screen.dart';

/// Settings → Developer tools (`/settings/developer`): the design-token
/// preview with the engine and sync debug panels. The router opens it in debug
/// builds only.
class DeveloperToolsScreen extends StatelessWidget {
  const DeveloperToolsScreen({super.key});

  @override
  Widget build(BuildContext context) => const TokenPreviewScreen();
}
