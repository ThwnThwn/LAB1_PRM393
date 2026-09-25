import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'student_csv_import_service.dart';

/// Reads student rosters from modern Excel workbooks.
class StudentXlsxImportService {
  const StudentXlsxImportService._();

  static StudentRosterImportResult parse(
    List<int> bytes, {
    required String fallbackGroup,
  }) {
    if (bytes.isEmpty) {
      throw const FormatException('File XLSX không có dữ liệu.');
    }

    late final Excel workbook;
    try {
      workbook = Excel.decodeBytes(Uint8List.fromList(bytes));
    } catch (_) {
      throw const FormatException(
        'Không thể đọc file XLSX. File có thể bị hỏng hoặc không đúng định dạng Excel.',
      );
    }

    FormatException? lastError;
    for (final entry in workbook.tables.entries) {
      final rows = entry.value.rows
          .map(
            (row) => row
                .map<dynamic>((cell) => _readCellValue(cell?.value))
                .toList(),
          )
          .toList();
      try {
        return StudentCsvImportService.parseRows(
          rows,
          fallbackGroup: fallbackGroup,
          sourceLabel: 'Sheet "${entry.key}" trong file XLSX',
          requireHeader: true,
        );
      } on FormatException catch (error) {
        lastError = error;
      }
    }

    final detail = lastError?.message.toString();
    throw FormatException(
      detail == null || detail.isEmpty
          ? 'File XLSX không có sheet chứa danh sách sinh viên.'
          : '$detail Không tìm thấy sheet danh sách sinh viên hợp lệ.',
    );
  }

  static dynamic _readCellValue(CellValue? value) {
    if (value == null) return '';
    if (value is TextCellValue) return value.value;
    if (value is IntCellValue) return value.value;
    if (value is DoubleCellValue) {
      final number = value.value;
      return number == number.truncateToDouble() ? number.toInt() : number;
    }
    if (value is BoolCellValue) return value.value;
    if (value is DateCellValue) {
      return value.asDateTimeLocal().toIso8601String();
    }
    if (value is DateTimeCellValue) {
      return value.asDateTimeLocal().toIso8601String();
    }
    if (value is TimeCellValue) return value.asDuration().toString();
    if (value is FormulaCellValue) return value.formula;
    return value.toString();
  }
}
