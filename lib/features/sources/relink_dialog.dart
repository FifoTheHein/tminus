import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/di.dart';
import '../../app/theme/tminus_theme.dart';
import '../../core/sources/ics_link_probe.dart';
import '../../core/sources/source_admin.dart';
import '../common/guarded.dart';
import 'link_field.dart';

/// Asks for a new link for [sourceId] (named [sourceName] in the title, so it
/// is clear whose link this is), checks it and saves it. Answers whether the
/// link was saved; the caller then syncs. The link itself never leaves the
/// dialog: it goes from the field to the probe, and the probed link to
/// `SourceAdmin`.
Future<bool> showRelinkDialog(
  BuildContext context, {
  required String sourceId,
  required String sourceName,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RelinkDialog(sourceId: sourceId, sourceName: sourceName),
    ) ??
    false;

/// The re-link dialog (mockup 4b's **Paste new link**): the link field,
/// **Check**, what the check found, and **Save**, which is on once a check
/// found the link working. Back does not close it while the link is being
/// saved: the save would finish with nobody to say so.
class RelinkDialog extends StatefulWidget {
  const RelinkDialog({
    super.key,
    required this.sourceId,
    required this.sourceName,
  });

  final String sourceId;
  final String sourceName;

  @override
  State<RelinkDialog> createState() => _RelinkDialogState();
}

class _RelinkDialogState extends State<RelinkDialog> {
  late final LinkChecker _link;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _link = LinkChecker(probe: getIt<IcsLinkProbe>());
  }

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final found = _link.found;
    if (found == null || _saving) return;
    setState(() => _saving = true);
    final saved = await guarded<bool>(context, () async {
      await getIt<SourceAdmin>().updateIcsUrl(widget.sourceId, found.url);
      return true;
    }, failure: 'Could not save the link.');
    if (!mounted) return;
    if (saved == true) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: ListenableBuilder(
        listenable: Listenable.merge([_link, _link.text]),
        builder: (context, _) => _dialog(context),
      ),
    );
  }

  Widget _dialog(BuildContext context) {
    return AlertDialog(
      title: Text('New link for ${widget.sourceName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinkField(
              controller: _link.text,
              onSubmitted: (_) => unawaited(_link.check()),
            ),
            const SizedBox(height: TMinusSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                key: const Key('checkLink'),
                onPressed: _link.canCheck && !_saving
                    ? () => unawaited(_link.check())
                    : null,
                child: const Text('Check'),
              ),
            ),
            LinkCheckResult(checker: _link),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('relinkSave'),
          onPressed: _link.state == LinkCheckState.found && !_saving
              ? _save
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
