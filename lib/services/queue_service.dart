import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kQueueKey = 'pending_ops_v1';

class PendingOp {
  final String id;
  final String collection;
  final String method; // 'create' | 'update'
  final Map<String, dynamic> body;
  final String? recordId; // set for 'update' ops

  /// When set on a create op, a follow-up `expense_splits` record is created
  /// after the parent record, with `expense` pointing at the new record id.
  /// Used so an offline expense+split is queued as one logical operation.
  final Map<String, dynamic>? splitBody;

  const PendingOp({
    required this.id,
    required this.collection,
    required this.method,
    required this.body,
    this.recordId,
    this.splitBody,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'collection': collection,
        'method': method,
        'body': body,
        if (recordId != null) 'recordId': recordId,
        if (splitBody != null) 'splitBody': splitBody,
      };

  factory PendingOp.fromJson(Map<String, dynamic> j) => PendingOp(
        id: j['id'] as String,
        collection: j['collection'] as String,
        method: j['method'] as String,
        body: Map<String, dynamic>.from(j['body'] as Map),
        recordId: j['recordId'] as String?,
        splitBody: j['splitBody'] != null
            ? Map<String, dynamic>.from(j['splitBody'] as Map)
            : null,
      );
}

bool isNetworkError(Object e) =>
    e is SocketException ||
    (e is ClientException && e.statusCode == 0) ||
    e is HandshakeException ||
    e is TimeoutException;

/// True when a create failed because a record with the submitted id already
/// exists — i.e. an earlier attempt reached the server.
bool isDuplicateIdError(Object e) {
  if (e is! ClientException || e.statusCode != 400) return false;
  final data = e.response['data'];
  return data is Map && data['id'] is Map &&
      (data['id'] as Map)['code'] == 'validation_invalid_id';
}

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

  /// Attempts to send all queued ops in order. Ops stay queued only while the
  /// server is unreachable; anything the server rejects would fail forever
  /// and is dropped. Returns the number successfully sent.
  static Future<int> flush(PocketBase pb) async {
    final ops = await load();
    if (ops.isEmpty) return 0;

    final remaining = <PendingOp>[];
    int flushed = 0;

    for (final op in ops) {
      try {
        if (op.method == 'create') {
          final id = await createIdempotent(pb, op.collection, op.body);
          if (op.splitBody != null) {
            await createIdempotent(
                pb, 'expense_splits', {...op.splitBody!, 'expense': id});
          }
        } else {
          await pb
              .collection(op.collection)
              .update(op.recordId!, body: op.body);
        }
        flushed++;
      } catch (e) {
        if (isNetworkError(e)) remaining.add(op);
      }
    }

    await _save(remaining);
    return flushed;
  }

  /// Creates a record and returns its id, treating "id already exists" as
  /// success when [body] carries a client-generated id.
  static Future<String> createIdempotent(
      PocketBase pb, String collection, Map<String, dynamic> body) async {
    try {
      final rec = await pb.collection(collection).create(body: body);
      return rec.id;
    } catch (e) {
      final id = body['id'] as String?;
      if (id != null && isDuplicateIdError(e)) return id;
      rethrow;
    }
  }

  static String newOpId() =>
      DateTime.now().microsecondsSinceEpoch.toString();
}
