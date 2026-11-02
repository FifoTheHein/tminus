import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/common/status_tone.dart';
import '../features/health/health_report.dart';
import 'di.dart';
import 'health_monitor.dart';

/// The four tabs of the app, in the brief's order: Agenda, Alerts, Sources,
/// Health. Each tab keeps its own navigation stack, and tapping the tab that
/// is open goes back to that tab's first screen.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: 'Agenda',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_none),
            selectedIcon: Icon(Icons.notifications),
            label: 'Alerts',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Sources',
          ),
          NavigationDestination(
            icon: _HealthIcon(Icons.favorite_border),
            selectedIcon: _HealthIcon(Icons.favorite),
            label: 'Health',
          ),
        ],
      ),
    );
  }
}

/// The Health tab's icon with a status dot: green when all is good, amber for
/// a warning, red for a problem, and no dot until the monitor has a report.
/// The monitor comes from `getIt`, not from a provider, so a test that pumps
/// only the router still works.
class _HealthIcon extends StatelessWidget {
  const _HealthIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final monitor = getIt<HealthMonitor>();
    return ListenableBuilder(
      listenable: monitor,
      builder: (context, _) {
        final report = monitor.report;
        if (report == null) return Icon(icon);
        final tone = switch (report.overall) {
          HealthLevel.ok => StatusTone.ok,
          HealthLevel.warning => StatusTone.warn,
          HealthLevel.problem => StatusTone.error,
        };
        return Badge(
          key: const Key('healthDot'),
          smallSize: 8,
          backgroundColor: toneColor(context, tone),
          child: Icon(icon),
        );
      },
    );
  }
}
