import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/tminus_theme.dart';
import '../../core/sources/ics_link_probe.dart';
import '../common/notice_banner.dart';
import '../common/status_tone.dart';

/// Brief §1: where Outlook keeps the link.
const outlookLinkPath =
    'Outlook → Settings → Calendar → Shared calendars → Publish → ICS';

/// The probe's good news: `Found 23 events this week`.
String foundText(int events) =>
    'Found $events ${events == 1 ? 'event' : 'events'} this week';

/// The ICS link field: a URL keyboard with autocorrect and suggestions off
/// (on the emulator the keyboard rewrote http:// to https://), no autofill,
/// no keyboard learning, one line, and a paste button. The text never leaves
/// this field except to the probe and SourceAdmin. Pasting only fills the
/// field: a request goes out when the user asks for the check.
class LinkField extends StatelessWidget {
  const LinkField({
    super.key,
    required this.controller,
    this.errorText,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? errorText;

  /// Called with the text when the user submits it from the keyboard. Not
  /// after a paste: that must not send a request (a one-time link would be
  /// used up, and an http one would go out in clear before the warning).
  final ValueChanged<String>? onSubmitted;

  Future<void> _paste(BuildContext context) async {
    String? text;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    } catch (e) {
      // Only the type: the clipboard holds whatever the user copied last.
      debugPrint('Pasting the link failed (${e.runtimeType})');
      return;
    }
    if (text == null || text.isEmpty || !context.mounted) return;
    controller.text = text;
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: const Key('icsLinkField'),
    controller: controller,
    keyboardType: TextInputType.url,
    autocorrect: false,
    enableSuggestions: false,
    // Android's incognito keyboard: nothing typed here is learned.
    enableIMEPersonalizedLearning: false,
    // Null turns autofill off; an empty list (the default) keeps the field
    // in it, and an autofill service could then offer to save the link.
    autofillHints: null,
    smartDashesType: SmartDashesType.disabled,
    smartQuotesType: SmartQuotesType.disabled,
    maxLines: 1,
    textInputAction: TextInputAction.done,
    onSubmitted: onSubmitted,
    decoration: InputDecoration(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TMinusRadii.sm),
      ),
      labelText: 'ICS link',
      hintText: 'https://outlook.office365.com/…/calendar.ics',
      errorText: errorText,
      suffixIcon: IconButton(
        tooltip: 'Paste',
        icon: const Icon(Icons.content_paste),
        onPressed: () => unawaited(_paste(context)),
      ),
    ),
  );
}

enum LinkCheckState { idle, checking, found, failed }

/// The link being typed and what the check made of it. The text sits in
/// [text] (the field's controller) and, once a check has found the link
/// working, in [found], which holds it in memory for `SourceAdmin`. Nothing
/// here stores, logs or shows it.
///
/// Editing the text forgets the result, so a link that was checked is never
/// the one that is saved after the field changed.
class LinkChecker extends ChangeNotifier {
  LinkChecker({required this.probe}) {
    text.addListener(_onText);
  }

  final IcsLinkProbe probe;
  final TextEditingController text = TextEditingController();

  LinkCheckState _state = LinkCheckState.idle;
  ProbeFound? _found;
  String? _failure;
  String _checkedText = '';
  int _generation = 0;
  bool _disposed = false;

  LinkCheckState get state => _state;

  /// Set only while [state] is [LinkCheckState.found].
  ProbeFound? get found => _found;

  /// The probe's fixed failure text; set only while [state] is
  /// [LinkCheckState.failed].
  String? get failure => _failure;

  bool get canCheck =>
      _state != LinkCheckState.checking && text.text.trim().isNotEmpty;

  /// One real fetch of the typed link (see [IcsLinkProbe]). Never throws.
  Future<void> check() async {
    final typed = text.text;
    if (!canCheck) return;
    _checkedText = typed;
    final generation = ++_generation;
    _state = LinkCheckState.checking;
    _found = null;
    _failure = null;
    notifyListeners();
    final result = await probe.check(typed);
    // Edited, cleared or closed meanwhile: this answer is for another link.
    if (_disposed || generation != _generation) return;
    switch (result) {
      case ProbeFound good:
        _state = LinkCheckState.found;
        _found = good;
      case ProbeFailed(:final message):
        _state = LinkCheckState.failed;
        _failure = message;
    }
    notifyListeners();
  }

  /// Forgets the link and its result.
  void clear() {
    _generation++;
    _state = LinkCheckState.idle;
    _found = null;
    _failure = null;
    _checkedText = '';
    text.clear();
    notifyListeners();
  }

  // A selection or focus change also notifies the controller: only a change
  // of the text itself forgets the result.
  void _onText() {
    if (_state == LinkCheckState.idle || text.text == _checkedText) return;
    _generation++;
    _state = LinkCheckState.idle;
    _found = null;
    _failure = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    text.removeListener(_onText);
    text.dispose();
    super.dispose();
  }
}

/// What the check made of the link: a spinner, `Found N events this week`
/// (`Key('probeFound')`, with the insecure warning for an http link) or the
/// failure (`Key('probeFailed')`).
class LinkCheckResult extends StatelessWidget {
  const LinkCheckResult({super.key, required this.checker});

  final LinkChecker checker;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: checker,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        switch (checker.state) {
          case LinkCheckState.idle:
            return const SizedBox.shrink();
          case LinkCheckState.checking:
            return _ResultLine(
              key: const Key('probeChecking'),
              leading: const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              text: 'Checking the link…',
              color: scheme.onSurfaceVariant,
            );
          case LinkCheckState.found:
            final ok = toneColor(context, StatusTone.ok);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ResultLine(
                  key: const Key('probeFound'),
                  leading: Icon(Icons.check_circle, size: 20, color: ok),
                  text: foundText(checker.found!.eventsThisWeek),
                  color: ok,
                ),
                if (checker.found!.insecure) const InsecureLinkWarning(),
              ],
            );
          case LinkCheckState.failed:
            final bad = toneColor(context, StatusTone.error);
            return _ResultLine(
              key: const Key('probeFailed'),
              leading: Icon(Icons.error_outline, size: 20, color: bad),
              text: checker.failure ?? 'Could not check the link.',
              color: bad,
            );
        }
      },
    );
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({
    super.key,
    required this.leading,
    required this.text,
    required this.color,
  });

  final Widget leading;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: TMinusSpacing.xs),
    child: Row(
      children: [
        leading,
        const SizedBox(width: TMinusSpacing.xs),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: color),
          ),
        ),
      ],
    ),
  );
}

/// An `http://` link sends the calendar unencrypted (decision 11). Amber, like
/// the rest of a source's sync health.
class InsecureLinkWarning extends StatelessWidget {
  const InsecureLinkWarning({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(top: TMinusSpacing.xs),
    child: NoticeBanner(
      key: Key('insecureWarning'),
      tone: StatusTone.warn,
      icon: Icons.lock_open,
      title: 'This link is not encrypted (http)',
      text:
          'Anyone on your network can read your calendar. Use the https link '
          'if Outlook offers one.',
    ),
  );
}
