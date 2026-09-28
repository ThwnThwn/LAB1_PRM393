class AttendanceSessionMatcher {
  const AttendanceSessionMatcher._();

  static Map<String, dynamic>? forTimetableSlot(
    List<Map<String, dynamic>> sessions, {
    required String classCode,
    required String subjectCode,
    required int slot,
    required DateTime date,
  }) {
    final matches = sessions.where((session) {
      final sessionDate = calendarDate(session['date']);
      final students = session['students'];
      return session['sessionId']?.toString().isNotEmpty == true &&
          session['classCode']?.toString().toUpperCase() ==
              classCode.toUpperCase() &&
          session['subjectCode']?.toString().toUpperCase() ==
              subjectCode.toUpperCase() &&
          session['slot'] == slot &&
          sessionDate != null &&
          sessionDate.year == date.year &&
          sessionDate.month == date.month &&
          sessionDate.day == date.day &&
          students is List &&
          students.isNotEmpty;
    });

    // The API and FAP demo both list the most recently updated session first.
    // Use the same ordering so a web save selects that session on desktop.
    return matches.firstOrNull;
  }

  static DateTime? calendarDate(Object? rawDate) {
    final value = rawDate?.toString() ?? '';
    if (value.isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return parsed;

    // Google Sheets serializes its local midnight as 17:00Z on the prior day.
    // The timetable and FAP demo use Vietnam's UTC+7 calendar date.
    return parsed.toUtc().add(const Duration(hours: 7));
  }
}
