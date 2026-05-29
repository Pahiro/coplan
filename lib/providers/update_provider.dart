import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/update_service.dart';

/// Resolves to an [UpdateInfo] when a newer app build is published, else null.
/// Checked once when the dashboard loads (and on manual refresh via invalidate).
final updateProvider = FutureProvider<UpdateInfo?>((ref) async {
  return UpdateService.check();
});
