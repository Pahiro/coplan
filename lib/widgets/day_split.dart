import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../engine/resolution_engine.dart';
import '../models/app_colors.dart';
import '../utils/dates.dart';

/// Shared "who owns this calendar day" computation used by both the week
/// strip and the month grid. Previously duplicated in both widgets — a
/// divergence here would show different custody owners per view.
///
/// Returns the effective owner for solid rendering, plus a secondary colour
/// when the day should render as a diagonal split (window with a known
/// return time, partial window overlap, or a mid-day transfer pickup).
({String owner, Color? splitColor}) computeDaySplit(
    ResolutionEngine engine, AppColors colors, DateTime date) {
  String effectiveOwner = engine.dayOwner(date);
  Color? splitColor;

  final window = engine.custodyWindows(date).firstOrNull;
  if (window != null) {
    final windowParent = window.toParent;
    // Use solid window-recipient colour only when all events are covered AND
    // the window has no definite return time. If a return time is set the
    // base owner gets the kids back, so show a split even when all scheduled
    // events fall inside the window.
    final windowHasDefiniteReturn =
        !window.returnTimeTbd && window.returnTime != null;
    if (engine.windowCoversAllEvents(date) && !windowHasDefiniteReturn) {
      effectiveOwner = windowParent;
    } else {
      // Partial overlap OR window ends at a known time → split.
      splitColor = colors.parentColor(windowParent);
    }
  }

  // Also check for a partial-day transfer — handles both the window-only and
  // window+transfer cases (ISSUES #6.1).
  if (splitColor == null) {
    final transfer = engine.dayTransferFor(date);
    if (transfer != null) {
      final p = parseHHmm(transfer.pickupTime);
      if (p.hour * 60 + p.minute > 0) {
        effectiveOwner = transfer.fromParent;
        splitColor = colors.parentColor(transfer.toParent);
      }
    }
  }

  return (owner: effectiveOwner, splitColor: splitColor);
}

/// Paints a diagonal split: [primaryColor] top-left, [secondaryColor]
/// bottom-right.
class SplitPainter extends CustomPainter {
  final Color primaryColor;
  final Color secondaryColor;
  final double opacity;

  const SplitPainter({
    required this.primaryColor,
    required this.secondaryColor,
    this.opacity = 0.18,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final topLeft = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(0, size.height)
      ..close();
    final bottomRight = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
        topLeft, Paint()..color = primaryColor.withValues(alpha: opacity));
    canvas.drawPath(bottomRight,
        Paint()..color = secondaryColor.withValues(alpha: opacity));
  }

  @override
  bool shouldRepaint(SplitPainter old) =>
      old.primaryColor != primaryColor ||
      old.secondaryColor != secondaryColor ||
      old.opacity != opacity;
}
