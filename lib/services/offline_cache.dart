import 'dart:convert';

import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/pb_client.dart';
import 'queue_service.dart' show isNetworkError;

/// On-device cache of the raw PocketBase records that feed the resolution
/// engine, so the schedule still renders when the server is unreachable.
///
/// Records are stored verbatim as their `RecordModel.toJson()` maps. Cache keys
/// are scoped by the logged-in user id so cached data never crosses the
/// household boundary on a shared device (see the security model in CLAUDE.md).
class OfflineCache {
  static SharedPreferences? _prefs;

  /// Must be called once during startup (see `main()`), before any provider
  /// reads. No-op if already initialised.
  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Builds a per-user cache key for [collection]. Scoping by the auth record id
  /// keeps one user's cached household data out of another's reach.
  static String keyFor(String collection) =>
      'cache:${pb.authStore.record?.id ?? 'anon'}:$collection';

  static Future<void> writeList(
      String collection, List<Map<String, dynamic>> json) async {
    await _prefs?.setString(keyFor(collection), jsonEncode(json));
  }

  static List<Map<String, dynamic>>? readList(String collection) {
    final raw = _prefs?.getString(keyFor(collection));
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeMap(
      String collection, Map<String, dynamic> json) async {
    await _prefs?.setString(keyFor(collection), jsonEncode(json));
  }

  static Map<String, dynamic>? readMap(String collection) {
    final raw = _prefs?.getString(keyFor(collection));
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeString(String collection, String value) async {
    await _prefs?.setString(keyFor(collection), value);
  }

  static String? readString(String collection) =>
      _prefs?.getString(keyFor(collection));
}

/// Fetches a list from PocketBase, caching the raw records on success and
/// transparently falling back to the cache when the server is unreachable.
///
/// Uses [isNetworkError] (the same check the offline write-queue uses) so the
/// fallback fires for socket/timeout/handshake failures, not just PocketBase's
/// `statusCode == 0`. On a 404 (collection not yet migrated) returns the cached
/// value if present, otherwise an empty list. Any other API error rethrows.
Future<List<T>> fetchCachedList<T>({
  required String collection,
  required Future<List<RecordModel>> Function() fetch,
  required T Function(Map<String, dynamic>) parse,
}) async {
  try {
    final records = await fetch();
    final json = records.map((r) => r.toJson()).toList();
    await OfflineCache.writeList(collection, json);
    return json.map(parse).toList();
  } catch (e) {
    if (isNetworkError(e)) {
      final cached = OfflineCache.readList(collection);
      if (cached != null) return cached.map(parse).toList();
    }
    if (e is ClientException && e.statusCode == 404) {
      final cached = OfflineCache.readList(collection);
      return cached?.map(parse).toList() ?? <T>[];
    }
    rethrow;
  }
}
