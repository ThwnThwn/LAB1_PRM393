import 'package:csv/csv.dart';

import '../models/student.dart';

class StudentCsvImportResult {
  const StudentCsvImportResult({
    required this.students,
    this.skippedRows = 0,
    this.duplicateRows = 0,
  });

  final List<Student> students;
  final int skippedRows;
  final int duplicateRows;

  int get importedCount => students.length;
  bool get hasWarnings => skippedRows > 0 || duplicateRows > 0;
}

/// Converts common FAP and attendance CSV layouts into a student roster.
class StudentCsvImportService {
  const StudentCsvImportService._();

  static const Set<String> _rollNoHeaders = {
    'rollno',
    'rollnumber',
    'mssv',
    'studentcode',
    'studentid',
    'studentroll',
    'masinhvien',
    'mãsinhviên',
    'masv',
    'mãsv',
  };
  static const Set<String> _fullNameHeaders = {
    'fullname',
    'studentname',
    'name',
    'hoten',
    'họvàtên',
    'hovaten',
    'tensinhvien',
    'tênsinhviên',
  };
  static const Set<String> _surnameHeaders = {
    'surname',
    'lastname',
    'familyname',
    'ho',
    'họ',
  };
  static const Set<String> _middleNameHeaders = {
    'middlename',
    'middle',
    'tendem',
    'tênđệm',
  };
  static const Set<String> _givenNameHeaders = {
    'givenname',
    'firstname',
    'given',
    'ten',
    'tên',
  };
  static const Set<String> _emailHeaders = {
    'email',
    'emailaddress',
    'fptemail',
    'mail',
  };
  static const Set<String> _groupHeaders = {
    'group',
    'groupname',
    'class',
    'classname',
    'classcode',
    'lop',
    'lớp',
  };
  static const Set<String> _statusHeaders = {
    'status',
    'attendancestatus',
    'trangthai',
    'trạngthái',
  };

  static StudentCsvImportResult parse(
    String rawCsv, {
    required String fallbackGroup,
  }) {
    var content = rawCsv
        .replaceFirst('\ufeff', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    if (content.trim().isEmpty) {
      throw const FormatException('File CSV không có dữ liệu.');
    }

    final lines = content.split('\n');
    final delimiterDeclaration = RegExp(
      r'^\s*sep\s*=\s*([,;\t])\s*$',
      caseSensitive: false,
    ).firstMatch(lines.first);
    final delimiter =
        delimiterDeclaration?.group(1) ?? _detectDelimiter(content);
    if (delimiterDeclaration != null) {
      content = lines.skip(1).join('\n');
    }
    final rows = CsvToListConverter(
      fieldDelimiter: delimiter,
      eol: '\n',
      shouldParseNumbers: false,
      allowInvalid: false,
    ).convert<dynamic>(content);
    final nonEmptyRows = rows
        .where((row) => row.any((cell) => _cell(cell).isNotEmpty))
        .toList();
    if (nonEmptyRows.isEmpty) {
      throw const FormatException('File CSV không có dữ liệu.');
    }

    final columns = _CsvColumns.fromHeader(nonEmptyRows.first);
    final hasHeader = columns.looksLikeHeader;
    if (hasHeader && columns.rollNo == null) {
      throw const FormatException(
        'CSV thiếu cột mã sinh viên (StudentCode, RollNo hoặc MSSV).',
      );
    }
    if (hasHeader && !columns.hasStudentName) {
      throw const FormatException(
        'CSV thiếu cột họ tên (FullName) hoặc các cột thành phần tên.',
      );
    }

    final students = <Student>[];
    final seenRollNumbers = <String>{};
    var skippedRows = 0;
    var duplicateRows = 0;

    for (var index = hasHeader ? 1 : 0; index < nonEmptyRows.length; index++) {
      final row = nonEmptyRows[index];
      final rollNo = _cellAt(row, hasHeader ? columns.rollNo : 0).toUpperCase();
      final fullName = hasHeader
          ? _readFullName(row, columns)
          : _cellAt(row, 1);

      if (rollNo.isEmpty || fullName.isEmpty) {
        skippedRows++;
        continue;
      }
      if (!seenRollNumbers.add(rollNo)) {
        duplicateRows++;
        continue;
      }

      final email = _cellAt(row, hasHeader ? columns.email : 2);
      final group = _cellAt(row, hasHeader ? columns.group : 3);
      final status = _cellAt(row, hasHeader ? columns.status : 4);
      students.add(
        Student(
          rollNo: rollNo,
          fullName: fullName,
          email: email.isEmpty
              ? '${rollNo.toLowerCase()}@fpt.edu.vn'
              : email.toLowerCase(),
          group: group.isEmpty ? fallbackGroup : group,
          status: AttendanceStatusExtension.fromString(status),
        ),
      );
    }

    if (students.isEmpty) {
      throw const FormatException(
        'Không tìm thấy sinh viên hợp lệ trong file CSV.',
      );
    }

    return StudentCsvImportResult(
      students: students,
      skippedRows: skippedRows,
      duplicateRows: duplicateRows,
    );
  }

  static String _detectDelimiter(String content) {
    final firstLine = content
        .split('\n')
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');
    const candidates = [',', ';', '\t'];
    var selected = ',';
    var highestCount = -1;
    for (final candidate in candidates) {
      final count = _countOutsideQuotes(firstLine, candidate);
      if (count > highestCount) {
        highestCount = count;
        selected = candidate;
      }
    }
    return selected;
  }

  static int _countOutsideQuotes(String value, String character) {
    var count = 0;
    var insideQuotes = false;
    for (var index = 0; index < value.length; index++) {
      if (value[index] == '"') {
        if (insideQuotes &&
            index + 1 < value.length &&
            value[index + 1] == '"') {
          index++;
        } else {
          insideQuotes = !insideQuotes;
        }
      } else if (!insideQuotes && value[index] == character) {
        count++;
      }
    }
    return count;
  }

  static String _readFullName(List<dynamic> row, _CsvColumns columns) {
    final fullName = _cellAt(row, columns.fullName);
    if (fullName.isNotEmpty) return fullName;

    return [
      _cellAt(row, columns.surname),
      _cellAt(row, columns.middleName),
      _cellAt(row, columns.givenName),
    ].where((part) => part.isNotEmpty).join(' ');
  }

  static String _cellAt(List<dynamic> row, int? index) {
    if (index == null || index < 0 || index >= row.length) return '';
    return _cell(row[index]);
  }

  static String _cell(dynamic value) => value?.toString().trim() ?? '';

  static String _normalizeHeader(dynamic value) {
    return _cell(value)
        .replaceFirst('\ufeff', '')
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_\-./]+'), '');
  }

  static int? _findColumn(List<String> headers, Set<String> aliases) {
    final index = headers.indexWhere(aliases.contains);
    return index == -1 ? null : index;
  }
}

class _CsvColumns {
  const _CsvColumns({
    required this.rollNo,
    required this.fullName,
    required this.surname,
    required this.middleName,
    required this.givenName,
    required this.email,
    required this.group,
    required this.status,
    required this.looksLikeHeader,
  });

  factory _CsvColumns.fromHeader(List<dynamic> row) {
    final headers = row.map(StudentCsvImportService._normalizeHeader).toList();
    final rollNo = StudentCsvImportService._findColumn(
      headers,
      StudentCsvImportService._rollNoHeaders,
    );
    final fullName = StudentCsvImportService._findColumn(
      headers,
      StudentCsvImportService._fullNameHeaders,
    );
    final surname = StudentCsvImportService._findColumn(
      headers,
      StudentCsvImportService._surnameHeaders,
    );
    final middleName = StudentCsvImportService._findColumn(
      headers,
      StudentCsvImportService._middleNameHeaders,
    );
    final givenName = StudentCsvImportService._findColumn(
      headers,
      StudentCsvImportService._givenNameHeaders,
    );
    final email = StudentCsvImportService._findColumn(
      headers,
      StudentCsvImportService._emailHeaders,
    );
    final group = StudentCsvImportService._findColumn(
      headers,
      StudentCsvImportService._groupHeaders,
    );
    final status = StudentCsvImportService._findColumn(
      headers,
      StudentCsvImportService._statusHeaders,
    );

    return _CsvColumns(
      rollNo: rollNo,
      fullName: fullName,
      surname: surname,
      middleName: middleName,
      givenName: givenName,
      email: email,
      group: group,
      status: status,
      looksLikeHeader:
          rollNo != null ||
          fullName != null ||
          surname != null ||
          middleName != null ||
          givenName != null ||
          email != null ||
          group != null ||
          status != null,
    );
  }

  final int? rollNo;
  final int? fullName;
  final int? surname;
  final int? middleName;
  final int? givenName;
  final int? email;
  final int? group;
  final int? status;
  final bool looksLikeHeader;

  bool get hasStudentName =>
      fullName != null ||
      surname != null ||
      middleName != null ||
      givenName != null;
}
