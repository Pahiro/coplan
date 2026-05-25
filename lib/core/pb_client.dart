import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';

/// Global PocketBase client, initialised once in main().
late final PocketBase pb;

Future<void> initPocketBase(SharedPreferences prefs) async {
  final store = AsyncAuthStore(
    save: (String data) async => prefs.setString('pb_auth', data),
    initial: prefs.getString('pb_auth'),
  );
  pb = PocketBase(AppConstants.pbUrl, authStore: store);
}
