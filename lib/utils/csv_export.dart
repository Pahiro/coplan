import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import 'csv_download_stub.dart'
    if (dart.library.html) 'csv_download_web.dart';

/// Escapes a CSV field (wraps in quotes if it contains comma/newline/quote).
String csvEscape(String s) {
  if (s.contains(',') || s.contains('"') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

/// Saves [csv] as [fileName] — browser download on web, app documents
/// directory elsewhere. Returns the path (or file name on web) to show the
/// user.
Future<String> saveCsv({required String csv, required String fileName}) async {
  if (kIsWeb) {
    downloadCsvOnWeb(csv, fileName);
    return fileName;
  }
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsString(csv);
  return file.path;
}
