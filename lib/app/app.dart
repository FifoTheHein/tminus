import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'di.dart';
import 'onboarding_gate.dart';
import 'router.dart';
import 'theme/tminus_theme.dart';
import 'theme_mode_controller.dart';

class TMinusApp extends StatefulWidget {
  /// [router] belongs to the caller (the test harness passes its own). Without
  /// one the app builds its router from the registered [OnboardingGate] and
  /// disposes it with the app.
  const TMinusApp({super.key, this.router});

  final GoRouter? router;

  @override
  State<TMinusApp> createState() => _TMinusAppState();
}

class _TMinusAppState extends State<TMinusApp> {
  late final GoRouter _router;
  late final bool _ownsRouter;

  @override
  void initState() {
    super.initState();
    final given = widget.router;
    _ownsRouter = given == null;
    _router = given ?? createRouter(gate: getIt<OnboardingGate>());
  }

  @override
  void dispose() {
    if (_ownsRouter) _router.dispose();
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
