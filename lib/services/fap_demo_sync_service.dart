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

  /// Converts the two attendance states into FAP's Present/Absent choices.
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
        AttendanceStatus.present => FapDemoMark.present,
        AttendanceStatus.absent => FapDemoMark.absent,
      };
    }

    return FapDemoSyncResult(
      marksByRollNo: marks,
      matchedCount: matched,
      unmatchedRollNos: unmatched,
    );
  }
}
