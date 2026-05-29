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
      // ── Parent colours from household_members.preferred_color ─────────────
      // Fallback: even parent → blue, odd parent → pink (deterministic).
      final evenId = household.rotationParentEvenId;
      final oddId  = household.rotationParentOddId;

      for (final m in household.members) {
        final parsed = _parseHex(m.preferredColor ?? '');

        if (parsed != null) {
          parentColors[m.displayName] = parsed;
        } else if (m.userId == evenId) {
          parentColors[m.displayName] = _defaultParentColors[0]; // blue
        } else if (m.userId == oddId) {
          parentColors[m.displayName] = _defaultParentColors[1]; // pink
        } else {
          final usedCount = parentColors.length;
          parentColors[m.displayName] =
              _defaultParentColors[usedCount % _defaultParentColors.length];
        }
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

  /// Persist the current user's preferred colour to both the user record and
  /// their household_members record (so other members can see it).
  Future<void> updateMyColor(Color color) async {
    final userId = pb.authStore.record?.id;
    if (userId == null) return;
    final hex = '#${color.value.toRadixString(16).substring(2).toUpperCase()}';

    // Update user record (for personal reference)
    await pb.collection('users').update(userId, body: {'preferred_color': hex});

    // Update household_members record (visible to other members)
    final household = ref.read(householdProvider).valueOrNull;
    if (household != null) {
      final member = household.memberByUserId(userId);
      if (member != null) {
        await pb.collection('household_members').update(member.id, body: {
          'preferred_color': hex,
        });
      }
    }

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
