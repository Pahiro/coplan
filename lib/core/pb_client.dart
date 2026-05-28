import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';

/// Global PocketBase client, initialised once in main() and re-initialised
/// if the user changes the server URL on the login screen.
late PocketBase pb;

/// The key used to persist the server URL in SharedPreferences.
const _pbUrlKey = 'pb_url';

/// Reads the saved PB URL (or falls back to the build-time default) and
/// creates the global [pb] client.
Future<void> initPocketBase(SharedPreferences prefs) async {
  final store = AsyncAuthStore(
    save: (String data) async => prefs.setString('pb_auth', data),
    initial: prefs.getString('pb_auth'),
  );
  final url = prefs.getString(_pbUrlKey) ?? AppConstants.pbUrl;
  pb = PocketBase(url, authStore: store);
}

/// Re-initialise [pb] with a new server URL.  Called when the user edits the
/// URL on the login/register screen.  Persists the URL for next launch.
Future<void> setPocketBaseUrl(String url, SharedPreferences prefs) async {
  await prefs.setString(_pbUrlKey, url);
  final store = AsyncAuthStore(
    save: (String data) async => prefs.setString('pb_auth', data),
    initial: prefs.getString('pb_auth'),
  );
  pb = PocketBase(url, authStore: store);
}

/// Returns the currently configured PB URL from prefs (or the default).
String getSavedPbUrl(SharedPreferences prefs) =>
    prefs.getString(_pbUrlKey) ?? AppConstants.pbUrl;
