/// Represents a single class slot in the lecturer's weekly timetable.
/// Models the FAP (FPT Academic Portal) schedule structure.
class FapClassSlot {
  final String id;
  final String subjectCode; // e.g. PRN232, PRM393, SWP391
  final String
  subjectName; // e.g. Building Cross-Platform Back-End Application With .NET
  final String classCode; // Student group e.g. SE1917, SE1801
  final int slot; // 1-8
  final int dayOfWeek; // 1=Mon, 2=Tue, ..., 7=Sun
  final String room; // e.g. NVH 602, Online
  final String slotTime; // e.g. 7:00-9:15
  final int sessionNumber; // Course session number e.g. 3
  final String instructor; // e.g. PhuongLHK
  final String campus; // e.g. FUHCM
  final String? meetUrl; // Google Meet / Zoom URL
  final bool isOnline;

  FapClassSlot({
    required this.id,
    required this.subjectCode,
    required this.subjectName,
    required this.classCode,
    required this.slot,
    required this.dayOfWeek,
    this.room = '',
    this.slotTime = '',
    this.sessionNumber = 1,
    this.instructor = '',
    this.campus = 'FUHCM',
    this.meetUrl,
    this.isOnline = false,
  });

  factory FapClassSlot.fromJson(Map<String, dynamic> json) {
    final slot = (json['slot'] as num?)?.toInt() ?? 1;
    return FapClassSlot(
      id: json['id']?.toString() ?? '',
      subjectCode: json['subjectCode']?.toString() ?? '',
      subjectName: json['subjectName']?.toString() ?? '',
      classCode: json['classCode']?.toString() ?? '',
      slot: slot,
      dayOfWeek: (json['dayOfWeek'] as num?)?.toInt() ?? 1,
      room: json['room']?.toString() ?? '',
      slotTime:
          json['slotTime']?.toString() ?? FapClassSlot.getSlotTimeRange(slot),
      sessionNumber: (json['sessionNumber'] as num?)?.toInt() ?? 1,
      instructor: json['instructor']?.toString() ?? '',
      campus: json['campus']?.toString() ?? 'FUHCM',
      meetUrl: json['meetUrl']?.toString(),
      isOnline: json['isOnline'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'subjectCode': subjectCode,
    'subjectName': subjectName,
    'classCode': classCode,
    'slot': slot,
    'dayOfWeek': dayOfWeek,
    'room': room,
    'slotTime': slotTime,
    'sessionNumber': sessionNumber,
    'instructor': instructor,
    'campus': campus,
    'meetUrl': meetUrl,
    'isOnline': isOnline,
  };

  /// Returns the slot time range based on slot number (FAP standard)
  static String getSlotTimeRange(int slot) {
    switch (slot) {
      case 1:
        return '7:00 - 9:15';
      case 2:
        return '9:30 - 11:45';
      case 3:
        return '12:30 - 14:45';
      case 4:
        return '15:00 - 17:15';
      case 5:
        return '17:30 - 19:45';
      case 6:
        return '20:00 - 22:15';
      case 7:
        return '17:45 - 19:15';
      case 8:
        return '19:30 - 21:00';
      default:
        return '';
    }
  }

  static String getDayName(int dayOfWeek) {
    switch (dayOfWeek) {
      case 1:
        return 'Thứ 2';
      case 2:
        return 'Thứ 3';
      case 3:
        return 'Thứ 4';
      case 4:
        return 'Thứ 5';
      case 5:
        return 'Thứ 6';
      case 6:
        return 'Thứ 7';
      case 7:
        return 'CN';
      default:
        return '';
    }
  }

  static String getDayShortName(int dayOfWeek) {
    switch (dayOfWeek) {
      case 1:
        return 'MON';
      case 2:
        return 'TUE';
      case 3:
        return 'WED';
      case 4:
        return 'THU';
      case 5:
        return 'FRI';
      case 6:
        return 'SAT';
      case 7:
        return 'SUN';
      default:
        return '';
    }
  }
}

class TimetableOcrCandidate {
  final String subjectCode;
  final String subjectName;
  final String classCode;
  final int? dayOfWeek;
  final int? slot;
  final String room;
  final double confidence;
  final List<String> warnings;

  const TimetableOcrCandidate({
    required this.subjectCode,
    required this.subjectName,
    required this.classCode,
    required this.dayOfWeek,
    required this.slot,
    required this.room,
    required this.confidence,
    required this.warnings,
  });

  factory TimetableOcrCandidate.fromJson(Map<String, dynamic> json) {
    final warnings = json['warnings'];
    return TimetableOcrCandidate(
      subjectCode: json['subjectCode']?.toString() ?? '',
      subjectName: json['subjectName']?.toString() ?? '',
      classCode: json['classCode']?.toString() ?? '',
      dayOfWeek: (json['dayOfWeek'] as num?)?.toInt(),
      slot: (json['slot'] as num?)?.toInt(),
      room: json['room']?.toString() ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      warnings: warnings is List
          ? warnings.map((warning) => warning.toString()).toList()
          : const [],
    );
  }
}

class TimetableOcrResult {
  final String fileName;
  final String rawText;
  final double confidence;
  final List<TimetableOcrCandidate> candidates;
  final List<String> warnings;

  const TimetableOcrResult({
    required this.fileName,
    required this.rawText,
    required this.confidence,
    required this.candidates,
    required this.warnings,
  });

  factory TimetableOcrResult.fromJson(Map<String, dynamic> json) {
    final candidates = json['candidates'];
    final warnings = json['warnings'];
    return TimetableOcrResult(
      fileName: json['fileName']?.toString() ?? '',
      rawText: json['rawText']?.toString() ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      candidates: candidates is List
          ? candidates
                .whereType<Map>()
                .map(
                  (candidate) => TimetableOcrCandidate.fromJson(
                    Map<String, dynamic>.from(candidate),
                  ),
                )
                .toList()
          : const [],
      warnings: warnings is List
          ? warnings.map((warning) => warning.toString()).toList()
          : const [],
    );
  }
}
