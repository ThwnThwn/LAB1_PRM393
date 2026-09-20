import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

Future<bool> downloadFile(String url) async {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('Không thể tải CSV (HTTP ${response.statusCode}).');
  }

  final fileName =
      _fileNameFromHeader(response.headers['content-disposition']) ??
      'attendance.csv';

  final savedPath = await FilePicker.platform.saveFile(
    dialogTitle: 'Lưu kết quả điểm danh',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: const ['csv'],
    bytes: response.bodyBytes,
    lockParentWindow: true,
  );

  return savedPath != null;
}

String? _fileNameFromHeader(String? contentDisposition) {
  if (contentDisposition == null || contentDisposition.isEmpty) return null;

  final encodedMatch = RegExp(
    r"filename\*=UTF-8''([^;]+)",
    caseSensitive: false,
  ).firstMatch(contentDisposition);
  if (encodedMatch != null) {
    return Uri.decodeComponent(encodedMatch.group(1)!);
  }

  final plainMatch = RegExp(
    r'filename="?([^";]+)"?',
    caseSensitive: false,
  ).firstMatch(contentDisposition);
  return plainMatch?.group(1)?.trim();
}
