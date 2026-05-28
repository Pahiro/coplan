import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/pb_client.dart';

class AuthState {
  final bool isLoggedIn;
  final String? userId;
  final String? userName;
  final String? activeHouseholdId;

  const AuthState({
    required this.isLoggedIn,
    this.userId,
    this.userName,
    this.activeHouseholdId,
  });

  bool get needsHousehold => isLoggedIn && (activeHouseholdId == null || activeHouseholdId!.isEmpty);

  static const loggedOut = AuthState(isLoggedIn: false);
}

class AuthNotifier extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    if (pb.authStore.isValid) {
      final model = pb.authStore.record;
      return AuthState(
        isLoggedIn: true,
        userId: model?.id,
        userName: model?.data['name'] as String?,
        activeHouseholdId: model?.data['active_household'] as String?,
      );
    }
    return AuthState.loggedOut;
  }

  Future<void> login(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final result =
          await pb.collection('users').authWithPassword(email, password);
      return AuthState(
        isLoggedIn: true,
        userId: result.record?.id,
        userName: result.record?.data['name'] as String?,
        activeHouseholdId: result.record?.data['active_household'] as String?,
      );
    });
  }

  Future<void> logout() async {
    pb.authStore.clear();
    state = const AsyncData(AuthState.loggedOut);
  }

  /// Register a new user account and log in immediately.
  Future<void> register({
    required String email,
    required String password,
    required String name,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await pb.collection('users').create(body: {
        'email':           email,
        'password':        password,
        'passwordConfirm': password,
        'name':            name,
      });
      final result =
          await pb.collection('users').authWithPassword(email, password);
      return AuthState(
        isLoggedIn: true,
        userId: result.record?.id,
        userName: result.record?.data['name'] as String?,
        activeHouseholdId: result.record?.data['active_household'] as String?,
      );
    });
  }
}

final authProvider =
    AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
