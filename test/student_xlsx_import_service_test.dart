import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance_app/models/student.dart';
import 'package:fap_attendance_app/services/student_roster_import_service.dart';

void main() {
  group('StudentRosterImportService XLSX', () {
    test('keeps the existing CSV path compatible', () {
      const csv =
          'RollNo,FullName,Email\nSE190010,Lê Minh Khoa,khoa@fpt.edu.vn';

      final result = StudentRosterImportService.parseFile(
        utf8.encode(csv),
        fileName: 'students.csv',
        fallbackGroup: 'SE1917',
      );

      expect(result.importedCount, 1);
      expect(result.students.single.rollNo, 'SE190010');
      expect(result.students.single.group, 'SE1917');
    });

    test('finds a roster sheet and imports rows after a title row', () {
      final workbook = Excel.createExcel();
      final defaultSheet = workbook.getDefaultSheet()!;
      workbook[defaultSheet].appendRow([
        TextCellValue('Hướng dẫn sử dụng'),
        TextCellValue('Không phải danh sách sinh viên'),
      ]);

      final roster = workbook['Students'];
      roster.appendRow([TextCellValue('Danh sách lớp SE1917')]);
      roster.appendRow([
        TextCellValue('Index'),
        TextCellValue('StudentCode'),
        TextCellValue('FullName'),
        TextCellValue('Email'),
        TextCellValue('Status'),
      ]);
      roster.appendRow([
        IntCellValue(1),
        TextCellValue('se190001'),
        TextCellValue('Nguyễn Văn An'),
        TextCellValue('AN@FPT.EDU.VN'),
        TextCellValue('PRESENT'),
      ]);
      roster.appendRow([
        IntCellValue(2),
        TextCellValue('SE190001'),
        TextCellValue('Dòng trùng'),
        TextCellValue('duplicate@fpt.edu.vn'),
        TextCellValue('ABSENT'),
      ]);
      roster.appendRow([
        IntCellValue(3),
        TextCellValue('SE190002'),
        TextCellValue('Trần Thị Bình'),
        TextCellValue(''),
        TextCellValue('ABSENT'),
      ]);
      roster.appendRow([
        IntCellValue(4),
        TextCellValue(''),
        TextCellValue('Thiếu MSSV'),
      ]);

      final result = StudentRosterImportService.parseFile(
        _save(workbook),
        fileName: 'DANH_SACH.XLSX',
        fallbackGroup: 'SE1917',
      );

      expect(result.importedCount, 2);
      expect(result.duplicateRows, 1);
      expect(result.skippedRows, 1);
      expect(result.students.first.rollNo, 'SE190001');
      expect(result.students.first.fullName, 'Nguyễn Văn An');
      expect(result.students.first.email, 'an@fpt.edu.vn');
      expect(result.students.first.group, 'SE1917');
      expect(result.students.first.status, AttendanceStatus.present);
      expect(result.students.last.email, 'se190002@fpt.edu.vn');
    });

    test('rejects a workbook without a valid student header', () {
      final workbook = Excel.createExcel();
      final sheet = workbook[workbook.getDefaultSheet()!];
      sheet.appendRow([TextCellValue('FullName'), TextCellValue('Email')]);
      sheet.appendRow([
        TextCellValue('Nguyễn Văn An'),
        TextCellValue('an@fpt.edu.vn'),
      ]);

      expect(
        () => StudentRosterImportService.parseFile(
          _save(workbook),
          fileName: 'students.xlsx',
          fallbackGroup: 'SE1917',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('mã sinh viên'),
          ),
        ),
      );
    });

    test('rejects a corrupt XLSX file with a readable message', () {
      expect(
        () => StudentRosterImportService.parseFile(
          Uint8List.fromList([1, 2, 3, 4]),
          fileName: 'students.xlsx',
          fallbackGroup: 'SE1917',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Không thể đọc file XLSX'),
          ),
        ),
      );
    });
  });
}

Uint8List _save(Excel workbook) {
  final bytes = workbook.save();
  if (bytes == null) throw StateError('Không tạo được workbook test.');
  return Uint8List.fromList(bytes);
}
