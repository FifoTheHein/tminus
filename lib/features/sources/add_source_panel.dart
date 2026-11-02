import 'package:flutter/widgets.dart';

import '../../core/model/source_config.dart';

/// Placeholder: the real panel replaces this file. It is part of a screen, not
/// a screen, so it shows nothing. [onAdded] gets the source once it is added.
class AddSourcePanel extends StatelessWidget {
  const AddSourcePanel({
    super.key,
    required this.onAdded,
    this.onboarding = false,
  });

  final void Function(SourceConfig) onAdded;

  /// Onboarding's wording and layout instead of the Add source screen's.
  final bool onboarding;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
