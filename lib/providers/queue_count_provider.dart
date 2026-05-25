import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Count of locally-queued operations waiting to sync with the server.
/// Seeded from SharedPreferences in main() and updated whenever an op
/// is enqueued or flushed.
final pendingOpsCountProvider = StateProvider<int>((ref) => 0);
