import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:go_router/go_router.dart';

import '../features/agenda/agenda_screen.dart';
import '../features/alerts/alerts_screen.dart';
import '../features/alerts/profile_editor_screen.dart';
import '../features/alerts/rule_editor_screen.dart';
import '../features/health/health_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/settings/developer_tools_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/sources/add_source_screen.dart';
import '../features/sources/source_detail_screen.dart';
import '../features/sources/sources_screen.dart';
import 'home_shell.dart';
import 'onboarding_gate.dart';

/// The app's routes. The Fix action's `/sources/<id>` arrives as the
/// platform's initial route or as a pushed route; Kotlin has already checked
/// its shape, and anything this router does not know goes to the Agenda.
///
/// Routes keep go_router's default of matching case-sensitively. The profile
/// and rule editors rely on it: `.../new` makes a new one, so `.../New` is a
/// profile or rule that is named `New`.
GoRouter createRouter({
  required OnboardingGate gate,
  bool debugTools = kDebugMode,
}) {
  return GoRouter(
    initialLocation: '/agenda',
    refreshListenable: gate,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      // Until onboarding is done every location, a Fix route included, shows
      // onboarding.
      if (!gate.done) return loc == '/onboarding' ? null : '/onboarding';
      if (loc == '/onboarding' || loc == '/') return '/agenda';
      if (loc.startsWith('/settings/developer') && !debugTools) {
        return '/settings';
      }
      return null;
    },
    onException: (context, state, router) => router.go('/agenda'),
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/agenda'),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/agenda', builder: (_, _) => const AgendaScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/alerts',
                builder: (_, _) => const AlertsScreen(),
                routes: [
                  GoRoute(
                    path: 'profiles/new',
                    builder: (_, _) => const ProfileEditorScreen(),
                  ),
                  GoRoute(
                    path: 'profiles/:id',
                    builder: (_, s) =>
                        ProfileEditorScreen(profileId: s.pathParameters['id']),
                  ),
                  GoRoute(
                    path: 'rules/new',
                    builder: (_, _) => const RuleEditorScreen(),
                  ),
                  GoRoute(
                    path: 'rules/:id',
                    builder: (_, s) =>
                        RuleEditorScreen(ruleId: s.pathParameters['id']),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/sources',
                builder: (_, _) => const SourcesScreen(),
                routes: [
                  // Before ':id', so `add` is never read as a source id.
                  GoRoute(
                    path: 'add',
                    builder: (_, _) => const AddSourceScreen(),
                  ),
                  GoRoute(
                    path: ':id',
                    builder: (_, s) =>
                        SourceDetailScreen(sourceId: s.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/health', builder: (_, _) => const HealthScreen()),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const SettingsScreen(),
        routes: [
          GoRoute(
            path: 'developer',
            builder: (_, _) => const DeveloperToolsScreen(),
          ),
        ],
      ),
    ],
  );
}
