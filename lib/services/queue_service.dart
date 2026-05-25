import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kQueueKey = 'pending_ops_v1';
const _kOtherParentKey = 'other_parent_id';

class PendingOp {
  final String id;
  final String collection;
  final String method; // 'create' | 'update'
  final Map<String, dynamic> body;
  final String? recordId; // set for 'update' ops

  const PendingOp({
    required this.id,
    required this.collection,
    required this.method,
    required this.body,
    this.recordId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'collection': collection,
        'method': method,
        'body': body,
        if (recordId != null) 'recordId': recordId,
      };

  factory PendingOp.fromJson(Map<String, dynamic> j) => PendingOp(
        id: j['id'] as String,
        collection: j['collection'] as String,
        method: j['method'] as String,
        body: Map<String, dynamic>.from(j['body'] as Map),
        recordId: j['recordId'] as String?,
      );
}

bool isNetworkError(Object e) =>
    e is SocketException ||
    (e is ClientException && e.statusCode == 0) ||
    e is HandshakeException ||
    e is TimeoutException;

class QueueService {
  QueueService._();

  static Future<List<PendingOp>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kQueueKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => PendingOp.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<void> _save(List<PendingOp> ops) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kQueueKey, jsonEncode(ops.map((o) => o.toJson()).toList()));
  }

  static Future<int> pendingCount() async => (await load()).length;

  static Future<void> enqueue(PendingOp op) async {
    final ops = await load();
    ops.add(op);
    await _save(ops);
  }

  /// Attempts to send all queued ops in order.
  /// Returns the number successfully sent.
  static Future<int> flush(PocketBase pb) async {
    final ops = await load();
    if (ops.isEmpty) return 0;

    final remaining = <PendingOp>[];
    int flushed = 0;

    for (final op in ops) {
      try {
        if (op.method == 'create') {
          await pb.collection(op.collection).create(body: op.body);
        } else {
          await pb
              .collection(op.collection)
              .update(op.recordId!, body: op.body);
        }
        flushed++;
      } catch (_) {
        remaining.add(op);
      }
    }

    await _save(remaining);
    return flushed;
  }

  static Future<void> saveOtherParentId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOtherParentKey, id);
  }

  static Future<String?> loadOtherParentId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kOtherParentKey);
  }

  static String newOpId() =>
      DateTime.now().microsecondsSinceEpoch.toString();
}
