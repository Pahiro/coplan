import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/pb_client.dart';
import '../models/app_colors.dart';
import '../models/household.dart';
import 'household_provider.dart';

/// Default parent colours when we can't resolve from household data.
const _defaultParentColors = [
  Color(0xFF1565C0), // blue
  Color(0xFFD81B60), // pink
  Color(0xFF00897B), // teal
  Color(0xFFFF8F00), // amber
];

class ColorsNotifier extends AsyncNotifier<AppColors> {
  @override
  Future<AppColors> build() async {
    final household = ref.watch(householdProvider).valueOrNull;

    final parentColors = <String, Color>{};
    final childColors  = <String, Color>{};

    if (household != null) {
      // ── Parent colours from user preferred_color ──────────────────────────
      for (var i = 0; i < household.members.length; i++) {
        final m = household.members[i];
        Color? parsed;
        try {
          final user = await pb.collection('users').getOne(m.userId);
          final hex = user.data['preferred_color'] as String? ?? '';
          parsed = _parseHex(hex);
        } catch (_) {}
        parentColors[m.displayName] =
            parsed ?? _defaultParentColors[i % _defaultParentColors.length];
      }

      // ── Child colours from children collection ────────────────────────────
      for (final c in household.children) {
        childColors[c.name] = _parseHex(c.color ?? '') ?? Colors.grey;
      }
    } else {
      // Fallback: legacy behaviour for pre-migration
      parentColors['Bennet'] = const Color(0xFF1565C0);
      parentColors['Jana']   = const Color(0xFFD81B60);
      childColors['Henri']   = const Color(0xFFE65100);
      childColors['Chris']   = const Color(0xFF00695C);
    }

    return AppColors(
      parentColors: parentColors,
      childColors:  childColors,
    );
  }

  /// Persist the current user's preferred colour to PocketBase.
  Future<void> updateMyColor(Color color) async {
    final userId = pb.authStore.record?.id;
    if (userId == null) return;
    final hex = '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
    await pb.collection('users').update(userId, body: {'preferred_color': hex});
    ref.invalidateSelf();
  }

  /// Update a child's colour in the children collection.
  Future<void> updateChildColor(String childId, Color color) async {
    final hex = '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
    await pb.collection('children').update(childId, body: {'color': hex});
    ref.invalidateSelf();
  }

  static Color? _parseHex(String s) {
    if (!s.startsWith('#') || s.length != 7) return null;
    return Color(int.parse('FF${s.substring(1)}', radix: 16));
  }
}

final colorsProvider =
    AsyncNotifierProvider<ColorsNotifier, AppColors>(ColorsNotifier.new);
