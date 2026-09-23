import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance_app/models/student.dart';
import 'package:fap_attendance_app/services/fap_demo_sync_service.dart';

void main() {
  Student student(String rollNo, AttendanceStatus status) => Student(
    rollNo: rollNo,
    fullName: 'Student $rollNo',
    email: '${rollNo.toLowerCase()}@fpt.edu.vn',
    group: 'SE1917',
    status: status,
  );

  test('maps the binary attendance states to FAP marks', () {
    final roster = [
      student('SE001', AttendanceStatus.absent),
      student('SE002', AttendanceStatus.absent),
    ];
    final result = FapDemoSyncService.matchClosedSession(
      roster: roster,
      attendanceRecords: [
        student('se001', AttendanceStatus.present),
        student('SE002', AttendanceStatus.absent),
      ],
    );

    expect(result.marksByRollNo['SE001'], FapDemoMark.present);
    expect(result.marksByRollNo['SE002'], FapDemoMark.absent);
    expect(result.matchedCount, 2);
    expect(result.unmatchedRollNos, isEmpty);
  });

  test('normalizes legacy late and not-checked values to binary states', () {
    expect(
      AttendanceStatusExtension.fromString('LATE'),
      AttendanceStatus.present,
    );
    expect(
      AttendanceStatusExtension.fromString('NOT CHECKED'),
      AttendanceStatus.absent,
    );
  });

  test('keeps roster student unmarked when source MSSV is missing', () {
    final result = FapDemoSyncService.matchClosedSession(
      roster: [student('SE005', AttendanceStatus.absent)],
      attendanceRecords: [student('SE999', AttendanceStatus.present)],
    );

    expect(result.marksByRollNo['SE005'], FapDemoMark.unmarked);
    expect(result.matchedCount, 0);
    expect(result.unmatchedRollNos, ['SE005']);
  });
}
