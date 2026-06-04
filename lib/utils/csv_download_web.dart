// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html show AnchorElement, Blob, Url;

void downloadCsvOnWeb(String csv, String fileName) {
  final blob = html.Blob([csv], 'text/csv');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
}
