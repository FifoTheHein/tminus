import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Runs a screen action. A failure shows [failure] in a snackbar and is
/// logged by type (or by a platform error's code), never by message: a message
/// can carry a feed link or a row's values. Returns null on failure.
Future<T?> guarded<T>(
  BuildContext context,
  Future<T> Function() action, {
  required String failure,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    return await action();
  } on PlatformException catch (e) {
    debugPrint('$failure (${e.code})');
  } catch (e) {
    debugPrint('$failure (${e.runtimeType})');
  }
  messenger?.showSnackBar(SnackBar(content: Text(failure)));
  return null;
}
