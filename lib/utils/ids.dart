import 'dart:math';

final _rand = Random.secure();
const _chars = 'abcdefghijklmnopqrstuvwxyz0123456789';

/// A PocketBase-compatible record id (15 chars of `[a-z0-9]`) generated on
/// the device. Creates that carry their own id are safe to retry: if the first
/// attempt actually reached the server (e.g. it timed out on the way back), the
/// replay fails with "id already exists" instead of creating a duplicate.
String newRecordId() =>
    List.generate(15, (_) => _chars[_rand.nextInt(_chars.length)]).join();
