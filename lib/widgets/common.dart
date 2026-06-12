import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';

import '../services/queue_service.dart' show isNetworkError;

/// Shared UI primitives that were previously copy-pasted per screen:
/// confirm dialogs, the standard bottom sheet, the busy save button, and
/// user-friendly error text.

/// Standard Cancel / action confirmation dialog. Returns true when confirmed.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  String action = 'OK',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// The app-standard modal bottom sheet: rounded top, drag handle,
/// keyboard-aware.
Future<T?> showAppSheet<T>(BuildContext context,
    {required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: builder,
  );
}

/// Standard content padding for bottom sheets (keyboard-aware). Top is small
/// because [showAppSheet] renders a drag handle above the content.
EdgeInsets sheetPadding(BuildContext context) => EdgeInsets.only(
      left: 24,
      right: 24,
      top: 8,
      bottom: MediaQuery.of(context).viewInsets.bottom + 24,
    );

/// Full-width [FilledButton] that swaps its label for a spinner while busy.
class BusyButton extends StatelessWidget {
  final bool busy;
  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;

  const BusyButton({
    super.key,
    required this.busy,
    required this.onPressed,
    required this.child,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final spinner = SizedBox(
      height: 18,
      width: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: Theme.of(context).colorScheme.onPrimary,
      ),
    );
    return SizedBox(
      width: double.infinity,
      child: icon != null
          ? FilledButton.icon(
              onPressed: busy ? null : onPressed,
              icon: busy ? spinner : icon!,
              label: child,
            )
          : FilledButton(
              onPressed: busy ? null : onPressed,
              child: busy ? spinner : child,
            ),
    );
  }
}

/// Maps raw exceptions to text a parent can act on, instead of dumping
/// `ClientException: {...}` into a snackbar.
String friendlyError(Object e) {
  if (isNetworkError(e)) {
    return 'No connection — check your network and try again.';
  }
  if (e is ClientException) {
    return switch (e.statusCode) {
      400 => 'The server rejected that — check the details and try again.',
      401 || 403 => "You don't have permission to do that.",
      404 => 'Not found — it may have been deleted.',
      _ => 'Server error (${e.statusCode}) — please try again.',
    };
  }
  final msg = e.toString().replaceFirst('Exception: ', '');
  return msg.length > 140 ? '${msg.substring(0, 140)}…' : msg;
}

/// Shows [friendlyError] for [e] in a snackbar.
void showErrorSnack(BuildContext context, Object e) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(friendlyError(e))));
}
