import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/tminus_theme.dart';
import '../../app/theme/tminus_token_catalog.dart';
import '../../app/theme_mode_controller.dart';
import 'engine_debug_panel.dart';

/// Placeholder home screen: shows the design tokens so the theme can be
/// compared visually with the design-system sheet.
class TokenPreviewScreen extends StatelessWidget {
  const TokenPreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Design tokens')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          TMinusSpacing.lg,
          TMinusSpacing.xs,
          TMinusSpacing.lg,
          TMinusSpacing.xxl,
        ),
        children: [
          const _ThemeModeSelector(),
          const _SectionLabel('01 · Colour'),
          for (final group in tminusColorTokenGroups()) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: TMinusSpacing.xs),
              child: Text(group.title, style: textTheme.titleMedium),
            ),
            _ColorGroupTable(group: group),
            const SizedBox(height: TMinusSpacing.md),
          ],
          const _SectionLabel('02 · Type'),
          const _NumeralSamples(),
          const SizedBox(height: TMinusSpacing.md),
          const _TextThemeSamples(),
          const _SectionLabel('03 · Spacing & radii'),
          const _SpacingAndRadii(),
          const _SectionLabel('05 · Components'),
          const _SampleEventCard(),
          if (kDebugMode) ...[
            const _SectionLabel('06 · Engine (debug)'),
            const EngineDebugPanel(),
          ],
        ],
      ),
    );
  }
}

class _ThemeModeSelector extends StatelessWidget {
  const _ThemeModeSelector();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ThemeModeController>();
    return SegmentedButton<ThemeMode>(
      segments: const [
        ButtonSegment(value: ThemeMode.system, label: Text('System')),
        ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
        ButtonSegment(value: ThemeMode.light, label: Text('Light')),
      ],
      selected: {controller.mode},
      onSelectionChanged: (selection) => controller.mode = selection.single,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: TMinusSpacing.xl,
        bottom: TMinusSpacing.sm,
      ),
      child: Text(
        text.toUpperCase(),
        style: context.tminusType.overline.copyWith(
          color: context.tminusColors.tertiaryText,
        ),
      ),
    );
  }
}

/// Token | dark | light, like the design-system colour tables.
class _ColorGroupTable extends StatelessWidget {
  const _ColorGroupTable({required this.group});

  final ColorTokenGroup group;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mono = context.tminusType.time;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(TMinusRadii.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: TMinusSpacing.xxs),
        child: Column(
          children: [
            for (final token in group.tokens)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TMinusSpacing.sm,
                  vertical: TMinusSpacing.xxs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Text(
                        token.name,
                        style: mono.copyWith(color: scheme.onSurface),
                      ),
                    ),
                    Expanded(flex: 3, child: _Swatch(color: token.dark)),
                    Expanded(flex: 3, child: _Swatch(color: token.light)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(TMinusRadii.sm - 2),
            border: Border.all(color: scheme.outlineVariant),
          ),
        ),
        const SizedBox(width: TMinusSpacing.xs - 2),
        Flexible(
          child: Text(
            hexRgb(color),
            style: context.tminusType.time.copyWith(
              fontSize: 11,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: TMinusSpacing.xxs,
        bottom: TMinusSpacing.md,
      ),
      child: Text(
        text,
        style: context.tminusType.time.copyWith(
          color: context.tminusColors.tertiaryText,
        ),
      ),
    );
  }
}

class _NumeralSamples extends StatelessWidget {
  const _NumeralSamples();

  @override
  Widget build(BuildContext context) {
    final type = context.tminusType;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: '1',
            style: type.countdownXL,
            children: [TextSpan(text: ' min', style: type.countdownXLUnit)],
          ),
        ),
        const _Caption('countdownXL · 120/114 · w500 · −5% / countdownXLUnit'),
        Text.rich(
          TextSpan(
            text: '23',
            style: type.countdownL,
            children: [TextSpan(text: ' min', style: type.countdownLUnit)],
          ),
        ),
        const _Caption('countdownL · 64/64 · w500 · −4% / countdownLUnit'),
        Text(
          '10:00–11:00',
          style: type.timeLarge.copyWith(color: scheme.onSurfaceVariant),
        ),
        const _Caption('timeLarge · 18/24 · w400'),
        Text(
          '08:45–09:00',
          style: type.time.copyWith(color: scheme.onSurfaceVariant),
        ),
        const _Caption('time · 12/16 · w400'),
        Row(
          children: [
            Text('−10', style: type.chipNumeralFor(alarm: false)),
            const SizedBox(width: TMinusSpacing.xs),
            Text('−1', style: type.chipNumeralFor(alarm: true)),
          ],
        ),
        const _Caption('chipNumeral · 12/16 · w400 heads-up / w600 alarm'),
        Text(
          'NEXT ALARM IN',
          style: type.overline.copyWith(color: scheme.onSurfaceVariant),
        ),
        const _Caption('overline · 11/16 · w400 · +14%'),
      ],
    );
  }
}

class _TextThemeSamples extends StatelessWidget {
  const _TextThemeSamples();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final samples = <(String, TextStyle?, String)>[
      ('headlineLarge', t.headlineLarge, 'Meetings you can’t miss'),
      ('displaySmall', t.displaySmall, 'Sprint planning'),
      ('headlineMedium', t.headlineMedium, 'Let’s make sure it rings'),
      ('headlineSmall', t.headlineSmall, 'Add your calendar'),
      ('titleLarge', t.titleLarge, 'Agenda'),
      ('titleMedium', t.titleMedium, '1:1 with Pieter'),
      ('bodyLarge', t.bodyLarge, 'Turns your calendar into alarms'),
      ('bodyMedium', t.bodyMedium, 'You can add more later in Sources.'),
      ('bodySmall', t.bodySmall, 'Quick · rule: standup'),
      ('labelLarge', t.labelLarge, 'Customise for this event'),
      ('labelMedium', t.labelMedium, 'Agenda · Alerts · Sources · Health'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (name, style, sample) in samples) ...[
          Text(
            sample,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          _Caption(name),
        ],
      ],
    );
  }
}

class _SpacingAndRadii extends StatelessWidget {
  const _SpacingAndRadii();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mono = context.tminusType.time.copyWith(color: scheme.onSurface);
    const spacing = <(String, double)>[
      ('xxs', TMinusSpacing.xxs),
      ('xs', TMinusSpacing.xs),
      ('sm', TMinusSpacing.sm),
      ('md', TMinusSpacing.md),
      ('lg', TMinusSpacing.lg),
      ('xl', TMinusSpacing.xl),
      ('xxl', TMinusSpacing.xxl),
    ];
    const radii = <(String, double)>[
      ('xs', TMinusRadii.xs),
      ('sm', TMinusRadii.sm),
      ('md', TMinusRadii.md),
      ('lg', TMinusRadii.lg),
      ('xl', TMinusRadii.xl),
      ('sheet', TMinusRadii.sheet),
      ('pill', TMinusRadii.pill),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (name, value) in spacing)
          Padding(
            padding: const EdgeInsets.only(bottom: TMinusSpacing.xs),
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Text('$name ${value.toInt()}', style: mono),
                ),
                Container(
                  width: value,
                  height: 16,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: TMinusSpacing.sm),
        Wrap(
          spacing: TMinusSpacing.sm,
          runSpacing: TMinusSpacing.sm,
          children: [
            for (final (name, value) in radii)
              Column(
                children: [
                  Container(
                    width: 72,
                    height: 48,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      border: Border.all(color: scheme.outline),
                      borderRadius: name == 'sheet'
                          ? const BorderRadius.vertical(
                              top: Radius.circular(TMinusRadii.sheet),
                            )
                          : BorderRadius.circular(value),
                    ),
                  ),
                  const SizedBox(height: TMinusSpacing.xxs),
                  Text('$name ${value.toInt()}', style: mono),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// EventCard sample: surfaceContainer, radius lg, calendar bar 4, a heads-up
/// chip (outline) and an alarm chip (solid).
class _SampleEventCard extends StatefulWidget {
  const _SampleEventCard();

  @override
  State<_SampleEventCard> createState() => _SampleEventCardState();
}

class _SampleEventCardState extends State<_SampleEventCard> {
  bool _on = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.tminusColors;
    final type = context.tminusType;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      key: const Key('sampleEventCard'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(TMinusRadii.lg),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              margin: const EdgeInsets.symmetric(vertical: TMinusSpacing.sm),
              decoration: BoxDecoration(
                color: colors.calendarBlue,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(TMinusRadii.xs - 1),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '10:00–11:00',
                      style: type.time.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    Text('Sprint planning', style: textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _Badge(icon: Icons.videocam_rounded, label: 'Teams'),
                        const _AlertChip(offset: '−10', alarm: false),
                        const _AlertChip(offset: '−1', alarm: true),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Meeting · default',
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.tertiaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 6, top: 6),
              child: Align(
                alignment: Alignment.topCenter,
                child: Switch(
                  value: _on,
                  onChanged: (v) => setState(() => _on = v),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = context.tminusColors.headsUpChipFg;
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: TMinusSpacing.xs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: TMinusSpacing.xxs),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}

/// Heads-up = outline chip with a bell; alarm = solid chip with an alarm icon.
class _AlertChip extends StatelessWidget {
  const _AlertChip({required this.offset, required this.alarm});

  final String offset;
  final bool alarm;

  @override
  Widget build(BuildContext context) {
    final colors = context.tminusColors;
    final fg = alarm ? colors.alarmChipFg : colors.headsUpChipFg;
    return Container(
      key: Key(alarm ? 'alarmChip' : 'headsUpChip'),
      height: alarm ? 22 : 20,
      padding: const EdgeInsets.fromLTRB(5, 0, 7, 0),
      decoration: BoxDecoration(
        color: alarm ? colors.alarmChipBg : null,
        border: alarm ? null : Border.all(color: colors.headsUpChipBorder),
        borderRadius: BorderRadius.circular(TMinusRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            alarm ? Icons.alarm_rounded : Icons.notifications_outlined,
            size: 14,
            color: fg,
          ),
          const SizedBox(width: 3),
          Text(
            offset,
            style: context.tminusType
                .chipNumeralFor(alarm: alarm)
                .copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}
