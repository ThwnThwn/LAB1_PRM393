import 'dart:convert';

import 'student_csv_import_service.dart';
import 'student_xlsx_import_service.dart';

/// Selects the correct roster reader from the uploaded file extension.
class StudentRosterImportService {
  const StudentRosterImportService._();

  static StudentRosterImportResult parseFile(
    List<int> bytes, {
    required String fileName,
    required String fallbackGroup,
  }) {
    final normalizedName = fileName.trim().toLowerCase();
    if (normalizedName.endsWith('.xlsx')) {
      return StudentXlsxImportService.parse(
        bytes,
        fallbackGroup: fallbackGroup,
      );
    }
    if (normalizedName.endsWith('.csv') || normalizedName.endsWith('.txt')) {
      late final String content;
      try {
        content = utf8.decode(bytes);
      } on FormatException {
        throw const FormatException(
          'Không thể đọc file CSV bằng UTF-8. Hãy lưu lại file dưới dạng CSV UTF-8.',
        );
      }
      return StudentCsvImportService.parse(
        content,
        fallbackGroup: fallbackGroup,
      );
    }
    throw const FormatException(
      'Định dạng chưa được hỗ trợ. Hãy chọn file CSV hoặc XLSX.',
    );
  }
}
