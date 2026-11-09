import 'package:flutter/material.dart';

import '../../app/theme/tminus_theme.dart';

/// Where a calendar link comes from. Any ICS link works; Outlook and Google
/// Calendar get steps of their own, and a drawing of the screen that has the
/// link.
enum LinkProvider {
  outlook(
    label: 'Outlook',
    defaultName: 'Work Outlook',
    path: 'Outlook → Settings → Calendar → Shared calendars → Publish → ICS',
    steps: [
      'Open Outlook on the web and go to Settings, Calendar, Shared '
          'calendars.',
      'Under Publish a calendar, choose your calendar and Can view all '
          'details, then select Publish.',
      'Copy the ICS link (not the HTML one).',
    ],
    hint: 'https://outlook.office365.com/…/calendar.ics',
  ),
  google(
    label: 'Google',
    defaultName: 'Google Calendar',
    path:
        'Google Calendar → Settings → your calendar → Integrate calendar → '
        'Secret address in iCal format',
    steps: [
      'Open Google Calendar on the web (calendar.google.com) and go to '
          'Settings.',
      'Under Settings for my calendars, choose your calendar, then '
          'Integrate calendar.',
      'Copy the Secret address in iCal format.',
    ],
    hint: 'https://calendar.google.com/calendar/ical/…/basic.ics',
  ),
  other(
    label: 'Other',
    defaultName: 'Calendar',
    path: 'Any .ics or webcal:// link works.',
    steps: [
      "Look for your calendar's publish, share or subscribe option.",
      'Copy the link that ends in .ics or starts with webcal://.',
    ],
    hint: 'https://…/calendar.ics',
  );

  const LinkProvider({
    required this.label,
    required this.defaultName,
    required this.path,
    required this.steps,
    required this.hint,
  });

  /// The toggle's label.
  final String label;

  /// The name a new calendar from here gets unless the user types another.
  final String defaultName;

  /// The way to the link, on one line.
  final String path;

  /// The short numbered steps under the toggle.
  final List<String> steps;

  /// The link field's hint: the shape of a link from here.
  final String hint;
}

/// Outlook or Google, when [link]'s host is one of theirs; else null (the
/// link says nothing about where it came from, so the choice stays).
///
/// Takes a full link or a masked one (`host/…/calendar.ics`, no scheme). Only
/// the host is looked at, and nothing is kept or logged.
LinkProvider? providerForLink(String link) {
  var text = link.trim().toLowerCase();
  final scheme = text.indexOf('://');
  if (scheme >= 0) text = text.substring(scheme + 3);
  final end = text.indexOf(RegExp(r'[/?#]'));
  if (end >= 0) text = text.substring(0, end);
  final at = text.lastIndexOf('@');
  if (at >= 0) text = text.substring(at + 1);
  final colon = text.indexOf(':');
  if (colon >= 0) text = text.substring(0, colon);
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  return switch (text) {
    'outlook.office365.com' || 'outlook.live.com' => LinkProvider.outlook,
    'calendar.google.com' => LinkProvider.google,
    _ => null,
  };
}

/// Outlook | Google | Other, and the chosen one's steps and drawing. The add
/// panel and the **How to find it** sheet both show it.
class LinkHelp extends StatelessWidget {
  const LinkHelp({super.key, required this.provider, required this.onChanged});

  final LinkProvider provider;
  final ValueChanged<LinkProvider> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<LinkProvider>(
          key: const Key('linkProvider'),
          showSelectedIcon: false,
          segments: [
            for (final p in LinkProvider.values)
              ButtonSegment<LinkProvider>(
                value: p,
                label: Text(p.label, key: Key('linkProvider-${p.name}')),
              ),
          ],
          selected: {provider},
          onSelectionChanged: (chosen) => onChanged(chosen.single),
        ),
        const SizedBox(height: TMinusSpacing.sm),
        for (final (i, step) in provider.steps.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: TMinusSpacing.xxs),
            child: Row(
              key: Key('linkStep-${provider.name}-$i'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 20,
                  child: Text(
                    '${i + 1}.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(child: Text(step, style: textTheme.bodyMedium)),
              ],
            ),
          ),
        const SizedBox(height: TMinusSpacing.xs),
        LinkIllustration(provider: provider),
        const SizedBox(height: TMinusSpacing.xs),
        Text(
          provider.path,
          key: const Key('findLinkPath'),
          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// A drawing, made up from scratch, of the screen that has the link: no
/// screenshot, no real names or links. Drawn at a fixed width and scaled to
/// fit, so it looks the same on every phone and text size. Screen readers
/// hear one label, not the made-up text inside it.
class LinkIllustration extends StatelessWidget {
  const LinkIllustration({super.key, required this.provider});

  final LinkProvider provider;

  static const _width = 300.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, drawing) = switch (provider) {
      LinkProvider.outlook => (
        "A drawing of Outlook's Publish a calendar settings, with the ICS link "
            'marked',
        const _OutlookDrawing(),
      ),
      LinkProvider.google => (
        "A drawing of Google Calendar's Integrate calendar settings, with the "
            'secret iCal address marked',
        const _GoogleDrawing(),
      ),
      LinkProvider.other => (
        'A drawing of two calendar links, one ending in .ics and one starting '
            'with webcal://',
        const _OtherDrawing(),
      ),
    };
    return Semantics(
      key: Key('illustration-${provider.name}'),
      label: label,
      image: true,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(TMinusSpacing.sm),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(TMinusRadii.md),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: MediaQuery.withNoTextScaling(
              child: SizedBox(width: _width, child: drawing),
            ),
          ),
        ),
      ),
    );
  }
}

/// The pieces the drawings are made of, in the theme's colours.
class _Ink {
  _Ink(BuildContext context)
    : scheme = Theme.of(context).colorScheme,
      text = Theme.of(context).textTheme;

  final ColorScheme scheme;
  final TextTheme text;

  TextStyle get small =>
      text.labelSmall!.copyWith(color: scheme.onSurfaceVariant, fontSize: 10);

  TextStyle get body => text.bodySmall!.copyWith(color: scheme.onSurface);

  TextStyle get heading => text.titleSmall!.copyWith(color: scheme.onSurface);

  /// A window: a bar with [title] over [children].
  Widget window(String title, IconData icon, List<Widget> children) =>
      DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(TMinusRadii.sm),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: TMinusSpacing.xs,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: TMinusSpacing.xxs),
                  Expanded(child: Text(title, style: small)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(TMinusSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ],
        ),
      );

  /// A drop-down showing [value].
  Widget dropdown(String value) => Container(
    padding: const EdgeInsets.fromLTRB(6, 4, 2, 4),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(TMinusRadii.xs),
      border: Border.all(color: scheme.outline),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: body),
        Icon(Icons.arrow_drop_down, size: 16, color: scheme.onSurfaceVariant),
      ],
    ),
  );

  /// A link row: a [label] over a box with a made-up [link]. The [marked] one
  /// is the link to copy.
  Widget link(String label, String link, {bool marked = false}) => Padding(
    padding: const EdgeInsets.only(top: TMinusSpacing.xs),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: small.copyWith(
            color: marked ? scheme.primary : scheme.onSurfaceVariant,
            fontWeight: marked ? FontWeight.w600 : null,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: marked ? scheme.primaryContainer : null,
            borderRadius: BorderRadius.circular(TMinusRadii.xs),
            border: Border.all(
              color: marked ? scheme.primary : scheme.outlineVariant,
              width: marked ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  link,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: body.copyWith(
                    color: marked
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Icon(
                Icons.content_copy,
                size: 12,
                color: marked ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ],
    ),
  );

  /// The arrow and words that point at the link to copy.
  Widget copyThis() => Padding(
    padding: const EdgeInsets.only(top: TMinusSpacing.xxs),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Icon(Icons.arrow_upward, size: 12, color: scheme.primary),
        const SizedBox(width: 2),
        Text(
          'Copy this one',
          style: small.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

/// Outlook on the web: Settings, Calendar, Shared calendars, Publish a
/// calendar.
class _OutlookDrawing extends StatelessWidget {
  const _OutlookDrawing();

  @override
  Widget build(BuildContext context) {
    final ink = _Ink(context);
    return ink.window(
      'Settings  ›  Calendar  ›  Shared calendars',
      Icons.settings,
      [
        Text('Publish a calendar', style: ink.heading),
        const SizedBox(height: TMinusSpacing.xs),
        Wrap(
          spacing: TMinusSpacing.xxs,
          runSpacing: TMinusSpacing.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ink.dropdown('Calendar'),
            ink.dropdown('Can view all details'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: ink.scheme.primary,
                borderRadius: BorderRadius.circular(TMinusRadii.xs),
              ),
              child: Text(
                'Publish',
                style: ink.body.copyWith(color: ink.scheme.onPrimary),
              ),
            ),
          ],
        ),
        ink.link('HTML', 'https://outlook.example/…/calendar.html'),
        ink.link('ICS', 'https://outlook.example/…/calendar.ics', marked: true),
        ink.copyThis(),
      ],
    );
  }
}

/// Google Calendar on the web: Settings, a calendar, Integrate calendar.
class _GoogleDrawing extends StatelessWidget {
  const _GoogleDrawing();

  @override
  Widget build(BuildContext context) {
    final ink = _Ink(context);
    return ink.window('Settings  ›  My calendar', Icons.settings, [
      Text('Integrate calendar', style: ink.heading),
      ink.link(
        'Public URL to this calendar',
        'https://calendar.example/…/embed',
      ),
      ink.link(
        'Secret address in iCal format',
        'https://calendar.example/…/private/basic.ics',
        marked: true,
      ),
      ink.copyThis(),
    ]);
  }
}

/// Any other calendar: the two shapes a link can have.
class _OtherDrawing extends StatelessWidget {
  const _OtherDrawing();

  @override
  Widget build(BuildContext context) {
    final ink = _Ink(context);
    return ink.window('Share or publish', Icons.share, [
      ink.link(
        'Ends in .ics',
        'https://calendar.example/…/calendar.ics',
        marked: true,
      ),
      ink.link(
        'Or starts with webcal://',
        'webcal://calendar.example/…/calendar.ics',
        marked: true,
      ),
    ]);
  }
}
