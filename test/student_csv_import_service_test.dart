import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance_app/models/student.dart';
import 'package:fap_attendance_app/services/student_csv_import_service.dart';

void main() {
  group('StudentCsvImportService', () {
    test('imports the FAP StudentCode and FullName layout', () {
      const csv = '''Index,StudentCode,Surname,MiddleName,GivenName,FullName
1,SA194282,Phan,Thị Thảo,Vy,Phan Thị Thảo Vy
2,SE172145,Nguyễn,Mai Hào,Thiên,Nguyễn Mai Hào Thiên''';

      final result = StudentCsvImportService.parse(
        csv,
        fallbackGroup: 'SE1917',
      );

      expect(result.importedCount, 2);
      expect(result.students.first.rollNo, 'SA194282');
      expect(result.students.first.fullName, 'Phan Thị Thảo Vy');
      expect(result.students.first.email, 'sa194282@fpt.edu.vn');
      expect(result.students.first.group, 'SE1917');
    });

    test('keeps status and reports duplicate or incomplete rows', () {
      const csv = '''\ufeffRollNo,FullName,Email,Group,Status
SE182173,"Bùi, Nhật Minh",minh@fpt.edu.vn,SE1917,PRESENT
SE182173,Duplicate,d@fpt.edu.vn,SE1917,ABSENT
,Missing code,,SE1917,ABSENT''';

      final result = StudentCsvImportService.parse(
        csv,
        fallbackGroup: 'DEFAULT',
      );

      expect(result.importedCount, 1);
      expect(result.duplicateRows, 1);
      expect(result.skippedRows, 1);
      expect(result.students.single.fullName, 'Bùi, Nhật Minh');
      expect(result.students.single.status, AttendanceStatus.present);
    });

    test('supports semicolon-separated CSV and composed name columns', () {
      const csv = '''sep=;
MSSV;Họ;Tên đệm;Tên
SE190001;Nguyễn;Văn;An''';

      final result = StudentCsvImportService.parse(
        csv,
        fallbackGroup: 'SE1900',
      );

      expect(result.students.single.fullName, 'Nguyễn Văn An');
    });

    test('rejects a header without a student code column', () {
      const csv = '''FullName,Email
Nguyen Van An,an@fpt.edu.vn''';

      expect(
        () => StudentCsvImportService.parse(csv, fallbackGroup: 'SE1917'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('mã sinh viên'),
          ),
        ),
      );
    });
  });
}
