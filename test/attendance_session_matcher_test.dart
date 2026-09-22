import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance_app/services/attendance_session_matcher.dart';

void main() {
  Map<String, dynamic> session(
    String id,
    String date, {
    String classCode = 'SE1917',
    String subjectCode = 'PRN232',
    int slot = 1,
    bool isOpen = false,
    bool hasStudents = true,
  }) => {
    'sessionId': id,
    'date': date,
    'classCode': classCode,
    'subjectCode': subjectCode,
    'slot': slot,
    'isOpen': isOpen,
    'students': hasStudents
        ? [
            {'rollNo': 'SE191709'},
          ]
        : [],
  };

  test('matches the Sheet date in Vietnam and ignores unrelated sessions', () {
    final result = AttendanceSessionMatcher.forTimetableSlot(
      [
        session('wrong-day', '2026-09-20T17:00:00Z'),
        session('wrong-subject', '2026-09-23T17:00:00Z', subjectCode: 'EXE201'),
        session('empty-history', '2026-09-23T17:00:00Z', hasStudents: false),
        session('fap-demo', '2026-09-23T17:00:00Z'),
      ],
      classCode: 'SE1917',
      subjectCode: 'PRN232',
      slot: 1,
      date: DateTime(2026, 9, 24),
    );

    expect(result?['sessionId'], 'fap-demo');
  });

  test('uses the FAP demo ordering when several sessions share a slot', () {
    final result = AttendanceSessionMatcher.forTimetableSlot(
      [
        session('recent-fap-save', '2026-09-24'),
        session('older-open-session', '2026-09-24', isOpen: true),
      ],
      classCode: 'SE1917',
      subjectCode: 'PRN232',
      slot: 1,
      date: DateTime(2026, 9, 24),
    );

    expect(result?['sessionId'], 'recent-fap-save');
  });
}
