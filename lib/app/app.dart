import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'di.dart';
import 'router.dart';
import 'theme/tminus_theme.dart';
import 'theme_mode_controller.dart';

class TMinusApp extends StatefulWidget {
  const TMinusApp({super.key});

  @override
  State<TMinusApp> createState() => _TMinusAppState();
}

class _TMinusAppState extends State<TMinusApp> {
  late final GoRouter _router = createRouter();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ThemeModeController>.value(
      value: getIt<ThemeModeController>(),
      child: Consumer<ThemeModeController>(
        builder: (context, themeMode, _) => MaterialApp.router(
          title: 'T-Minus',
          debugShowCheckedModeBanner: false,
          theme: TMinusTheme.light(),
          darkTheme: TMinusTheme.dark(),
          themeMode: themeMode.mode,
          routerConfig: _router,
        ),
      ),
    );
  }
}
