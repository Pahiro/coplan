import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/pb_client.dart';
import '../models/app_colors.dart';

class ColorsNotifier extends AsyncNotifier<AppColors> {
  @override
  Future<AppColors> build() async {
    Color bennet = const Color(0xFF1565C0);
    Color jana   = const Color(0xFFD81B60);
    Color henri  = const Color(0xFFE65100);
    Color chris  = const Color(0xFF00695C);

    // ── Fetch parent preferred colours from users collection ─────────────────
    try {
      final users = await pb.collection('users').getFullList();
      for (final u in users) {
        final name     = u.data['name'] as String? ?? '';
        final colorStr = u.data['preferred_color'] as String? ?? '';
        final parsed   = _parseHex(colorStr);
        if (parsed == null) continue;
        if (name == 'Bennet') bennet = parsed;
        if (name == 'Jana')   jana   = parsed;
      }
    } catch (_) {}

    // ── Fetch child colours from app_settings ────────────────────────────────
    try {
      final settings = await pb.collection('app_settings').getFullList();
      for (final s in settings) {
        final key    = s.data['key']   as String? ?? '';
        final parsed = _parseHex(s.data['value'] as String? ?? '');
        if (parsed == null) continue;
        if (key == 'color_henri') henri = parsed;
        if (key == 'color_chris') chris = parsed;
      }
    } catch (_) {}

    return AppColors(
      bennetColor: bennet,
      janaColor:   jana,
      henriColor:  henri,
      chrisColor:  chris,
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

  /// Update a child's colour in app_settings.
  Future<void> updateChildColor(String childName, Color color) async {
    final key = 'color_${childName.toLowerCase()}';
    final hex = '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
    // Upsert: find existing record or create
    try {
      final records = await pb
          .collection('app_settings')
          .getFullList(filter: 'key = "$key"');
      if (records.isNotEmpty) {
        await pb.collection('app_settings')
            .update(records.first.id, body: {'value': hex});
      } else {
        await pb.collection('app_settings')
            .create(body: {'key': key, 'value': hex, 'label': "$childName's colour"});
      }
    } catch (_) {}
    ref.invalidateSelf();
  }

  static Color? _parseHex(String s) {
    if (!s.startsWith('#') || s.length != 7) return null;
    return Color(int.parse('FF${s.substring(1)}', radix: 16));
  }
}

final colorsProvider =
    AsyncNotifierProvider<ColorsNotifier, AppColors>(ColorsNotifier.new);
