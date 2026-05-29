import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../core/pb_client.dart';

/// Describes an available app update, read from the server's app_settings.
class UpdateInfo {
  final int latestBuild;
  final String latestVersion;
  final String apkUrl;
  final String? notes;

  const UpdateInfo({
    required this.latestBuild,
    required this.latestVersion,
    required this.apkUrl,
    this.notes,
  });
}

/// In-app update: compares the installed build number against the latest
/// published build (stored in app_settings on the server), and can download
/// and launch the installer for a newer APK.
///
/// Server-side keys (app_settings, readable by any authed user):
///   - latest_build    e.g. "3"            (integer build number)
///   - latest_version  e.g. "1.1.0"        (display version)
///   - apk_url         e.g. https://coplan.vdgryp.co.za/coplan-latest.apk
///   - update_notes    optional release notes
class UpdateService {
  UpdateService._();

  /// Returns an [UpdateInfo] when a newer build is published, else null.
  static Future<UpdateInfo?> check() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(pkg.buildNumber) ?? 0;

      final settings = await pb.collection('app_settings').getFullList();
      final map = <String, String>{};
      for (final s in settings) {
        final k = s.data['key'] as String?;
        final v = s.data['value'] as String?;
        if (k != null && v != null) map[k] = v;
      }

      final latestBuild = int.tryParse(map['latest_build'] ?? '') ?? 0;
      final apkUrl = map['apk_url'] ?? '';
      if (latestBuild <= currentBuild || apkUrl.isEmpty) return null;

      final notes = map['update_notes'] ?? '';
      return UpdateInfo(
        latestBuild: latestBuild,
        latestVersion: map['latest_version'] ?? '',
        apkUrl: apkUrl,
        notes: notes.isEmpty ? null : notes,
      );
    } catch (_) {
      return null;
    }
  }

  /// Downloads the APK to app-specific external storage, reporting progress
  /// (0.0–1.0). Returns the downloaded file.
  static Future<File> download(
      String url, void Function(double) onProgress) async {
    final dir = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/coplan-update.apk');
    if (await file.exists()) await file.delete();

    // Cache-bust: a CDN (e.g. Cloudflare) may otherwise serve a stale APK for a
    // reused URL like coplan-latest.apk. A unique query makes a fresh request.
    final sep = url.contains('?') ? '&' : '?';
    final bustedUrl = '$url${sep}cb=${DateTime.now().millisecondsSinceEpoch}';

    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(bustedUrl));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw Exception('Download failed (HTTP ${resp.statusCode})');
      }
      final total = resp.contentLength;
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in resp) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress(received / total);
      }
      await sink.flush();
      await sink.close();
      return file;
    } finally {
      client.close();
    }
  }

  /// Launches the Android package installer for the downloaded APK.
  /// Requires the REQUEST_INSTALL_PACKAGES permission; the OS prompts the user
  /// to allow installing from CoPlan the first time.
  static Future<void> install(File file) async {
    final res = await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
    if (res.type != ResultType.done) {
      throw Exception(res.message);
    }
  }
}
