import 'package:go_router/go_router.dart';

import '../features/token_preview/token_preview_screen.dart';

GoRouter createRouter() {
  return GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const TokenPreviewScreen(),
      ),
    ],
  );
}
