class AttendanceSession {
  final String classCode; // e.g. SE1801
  final String subjectCode; // e.g. PRN231 / PRN211
  final int slot; // e.g. 1, 2, 3, 4, 5
  final DateTime date;
  String activeOtp; // 6-digit OTP currently valid
  int otpRemainingSeconds; // 10s down to 0
  String? serverSessionId;
  bool isOpen;
  DateTime? openedAt;
  DateTime? closedAt;

  AttendanceSession({
    required this.classCode,
    required this.subjectCode,
    required this.slot,
    required this.date,
    this.activeOtp = '000000',
    this.otpRemainingSeconds = 10,
    this.serverSessionId,
    this.isOpen = false,
    this.openedAt,
    this.closedAt,
  });

  String get sessionTitle => '$subjectCode - $classCode (Slot $slot)';
}
