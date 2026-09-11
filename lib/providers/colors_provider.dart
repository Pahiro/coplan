import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/pb_client.dart';
import '../models/app_colors.dart';
import 'household_provider.dart';

class ColorsNotifier extends AsyncNotifier<AppColors> {
  @override
  Future<AppColors> build() async =>
      AppColors.forHousehold(ref.watch(householdProvider).valueOrNull);

  /// Persist the current user's preferred colour to both the user record and
  /// their household_members record (so other members can see it).
  Future<void> updateMyColor(Color color) async {
    final userId = pb.authStore.record?.id;
    if (userId == null) return;
    final hex = '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

    await pb.collection('users').update(userId, body: {'preferred_color': hex});

    final household = ref.read(householdProvider).valueOrNull;
    final member = household?.memberByUserId(userId);
    if (member != null) {
      await pb.collection('household_members').update(member.id, body: {
        'preferred_color': hex,
      });
    }

    ref.invalidate(householdProvider);
  }

  /// Update a child's colour in the children collection.
  Future<void> updateChildColor(String childId, Color color) async {
    final hex = '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
    await pb.collection('children').update(childId, body: {'color': hex});
    ref.invalidate(householdProvider);
  }
}

final colorsProvider =
    AsyncNotifierProvider<ColorsNotifier, AppColors>(ColorsNotifier.new);
