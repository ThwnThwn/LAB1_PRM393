// ignore_for_file: deprecated_member_use

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
