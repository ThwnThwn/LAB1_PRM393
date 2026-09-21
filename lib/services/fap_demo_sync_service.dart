import '../models/student.dart';

enum FapDemoMark { unmarked, present, absent }

class FapDemoSyncResult {
  final Map<String, FapDemoMark> marksByRollNo;
  final int matchedCount;
  final List<String> unmatchedRollNos;

  const FapDemoSyncResult({
    required this.marksByRollNo,
    required this.matchedCount,
    required this.unmatchedRollNos,
  });
}

class FapDemoSyncService {
  const FapDemoSyncService._();

  static String normalizeRollNo(String value) => value.trim().toUpperCase();

  /// Converts the attendance database records into the two choices used by
  /// FAP's attendance form. This method should only be called after a session
  /// is closed; while it is open, NOT CHECKED still means "pending".
  static FapDemoSyncResult matchClosedSession({
    required List<Student> roster,
    required List<Student> attendanceRecords,
  }) {
    final recordsByRollNo = <String, Student>{
      for (final student in attendanceRecords)
        normalizeRollNo(student.rollNo): student,
    };
    final marks = <String, FapDemoMark>{};
    final unmatched = <String>[];
    var matched = 0;

    for (final student in roster) {
      final rollNo = normalizeRollNo(student.rollNo);
      final record = recordsByRollNo[rollNo];
      if (record == null) {
        marks[rollNo] = FapDemoMark.unmarked;
        unmatched.add(rollNo);
        continue;
      }

      matched++;
      marks[rollNo] = switch (record.status) {
        AttendanceStatus.present ||
        AttendanceStatus.late => FapDemoMark.present,
        AttendanceStatus.absent ||
        AttendanceStatus.notChecked => FapDemoMark.absent,
      };
    }

    return FapDemoSyncResult(
      marksByRollNo: marks,
      matchedCount: matched,
      unmatchedRollNos: unmatched,
    );
  }
}
