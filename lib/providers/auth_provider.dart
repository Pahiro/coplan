import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
      if (model?.id != null) _stampClientVersion(model!.id);
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
      _stampClientVersion(result.record?.id ?? '');
      return AuthState(
        isLoggedIn: true,
        userId: result.record?.id,
        userName: result.record?.data['name'] as String?,
        activeHouseholdId: result.record?.data['active_household'] as String?,
      );
    });
  }

  void _stampClientVersion(String userId) {
    if (userId.isEmpty) return;
    PackageInfo.fromPlatform().then((pkg) {
      pb.collection('users').update(userId, body: {
        'client_version': '${pkg.version}+${pkg.buildNumber}',
      });
    }).catchError((_) {});
  }

  Future<void> logout() async {
    pb.authStore.clear();
    state = const AsyncData(AuthState.loggedOut);
  }

  Future<void> requestPasswordReset(String email) async {
    await pb.collection('users').requestPasswordReset(email);
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final userId = state.valueOrNull?.userId;
    if (userId == null) throw Exception('Not logged in');
    final email = pb.authStore.record?.data['email'] as String? ?? '';
    await pb.collection('users').update(userId, body: {
      'oldPassword':     oldPassword,
      'password':        newPassword,
      'passwordConfirm': newPassword,
    });
    // Re-authenticate so the auth token stays valid after the password change.
    if (email.isNotEmpty) await login(email, newPassword);
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
      _stampClientVersion(result.record?.id ?? '');
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
