import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds an invite code that arrived via deep link or URL query param before
/// the user authenticated. The login / register / household-setup screens read
/// this to pre-fill or auto-accept the invite after auth.
final pendingInviteProvider = StateProvider<String?>((ref) => null);
