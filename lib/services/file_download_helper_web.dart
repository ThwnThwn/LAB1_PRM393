// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

Future<bool> downloadFile(String url) async {
  final anchor = html.AnchorElement(href: url)
    ..download = ''
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  return true;
}

Future<bool> saveCsvFile(String content, String fileName) async {
  final bytes = utf8.encode('\uFEFF$content');
  final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
  final objectUrl = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: objectUrl)
    ..download = fileName
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(objectUrl);
  return true;
}
