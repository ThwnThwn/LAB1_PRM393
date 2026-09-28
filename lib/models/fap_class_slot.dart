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
  final int totalSessions; // Planned number of course meetings e.g. 20
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
    this.totalSessions = 20,
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
      totalSessions: (json['totalSessions'] as num?)?.toInt() ?? 20,
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
    'totalSessions': totalSessions,
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
  final String instructor;
  final double confidence;
  final List<String> warnings;

  const TimetableOcrCandidate({
    required this.subjectCode,
    required this.subjectName,
    required this.classCode,
    required this.dayOfWeek,
    required this.slot,
    required this.room,
    required this.instructor,
    required this.confidence,
    required this.warnings,
  });

  factory TimetableOcrCandidate.fromJson(Map<String, dynamic> json) {
    final rawSubjectCode = json['subjectCode']?.toString() ?? '';
    final rawClassCode = json['classCode']?.toString() ?? '';
    final rawSubjectName = json['subjectName']?.toString() ?? '';
    final rawInstructor = json['instructor']?.toString() ?? '';
    final subjectCode = _normalizeOcrSubjectCode(rawSubjectCode);
    final classCode = _normalizeOcrClassCode(rawClassCode);
    final instructor = _normalizeOcrInstructor(
      rawInstructor.isEmpty ? rawSubjectName : rawInstructor,
    );
    final apiWarnings = json['warnings'];
    final warnings = apiWarnings is List
        ? apiWarnings.map((warning) => warning.toString()).toList()
        : <String>[];
    final apiSlot = (json['slot'] as num?)?.toInt();
    final inferredSlot = apiSlot ?? _inferSlotFromOcrText(rawSubjectName);

    if (subjectCode != rawSubjectCode.trim().toUpperCase()) {
      _addUniqueOcrWarning(
        warnings,
        'Đã tự sửa mã môn ${rawSubjectCode.trim()} → $subjectCode',
      );
    }
    if (classCode != rawClassCode.trim().toUpperCase()) {
      _addUniqueOcrWarning(
        warnings,
        'Đã tự sửa mã lớp ${rawClassCode.trim()} → $classCode',
      );
    }
    if (apiSlot == null && inferredSlot != null) {
      warnings.removeWhere(
        (warning) => warning.toLowerCase().contains('chưa xác định được slot'),
      );
      _addUniqueOcrWarning(
        warnings,
        'Đã tự điền Slot $inferredSlot từ giờ học',
      );
    }
    if (rawInstructor.trim().isEmpty && instructor.isNotEmpty) {
      _addUniqueOcrWarning(
        warnings,
        'Đã tách giảng viên $instructor khỏi tên môn',
      );
    }

    return TimetableOcrCandidate(
      subjectCode: subjectCode,
      subjectName: _normalizeOcrSubjectName(
        rawSubjectName,
        subjectCode,
        instructor,
      ),
      classCode: classCode,
      dayOfWeek: (json['dayOfWeek'] as num?)?.toInt(),
      slot: inferredSlot,
      room: json['room']?.toString() ?? '',
      instructor: instructor,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      warnings: warnings,
    );
  }
}

final RegExp _ocrSubjectCodePattern = RegExp(
  r'^([A-Z]{2,5})[-\s]*([0-9ILOSBZG]{3})([A-Z]?)$',
);
final RegExp _ocrClassCodePattern = RegExp(
  r'^([A-Z]{2})[-\s]*([0-9ILOSBZG]{4,6})$',
);
final RegExp _ocrTimePattern = RegExp(
  r'(?<!\d)(0?7|0?9|12|15|17|19|20)\s*[:.hH]\s*(00|30|45)(?!\d)',
);
final RegExp _ocrInstructorPattern = RegExp(
  r'(?<![A-Za-z])([A-Z][a-z]{2,}[A-Z]{2,5})(?![A-Za-z])',
);

String _normalizeOcrSubjectCode(String value) {
  final compact = value.trim().toUpperCase();
  final match = _ocrSubjectCodePattern.firstMatch(compact);
  if (match == null) return compact;

  var prefix = match.group(1)!;
  if (prefix.length == 5 && prefix.startsWith('TI')) {
    // The blue book icon next to a course is sometimes read as "TI".
    prefix = prefix.substring(2);
  } else if (prefix.length == 4 &&
      (prefix.startsWith('I') || prefix.startsWith('L'))) {
    prefix = prefix.substring(1);
  }
  return '$prefix${_normalizeOcrDigits(match.group(2)!)}${match.group(3)!}';
}

String _normalizeOcrClassCode(String value) {
  final compact = value.trim().toUpperCase();
  final match = _ocrClassCodePattern.firstMatch(compact);
  if (match == null) return compact;
  return '${match.group(1)!}${_normalizeOcrDigits(match.group(2)!)}';
}

String _normalizeOcrDigits(String value) => value
    .replaceAll(RegExp('[IL]'), '1')
    .replaceAll('O', '0')
    .replaceAll('S', '5')
    .replaceAll('B', '8')
    .replaceAll('Z', '2')
    .replaceAll('G', '6');

int? _inferSlotFromOcrText(String value) {
  final match = _ocrTimePattern.firstMatch(value);
  if (match == null) return null;
  final time = '${int.parse(match.group(1)!)}:${match.group(2)!}';
  return const {
    '7:00': 1,
    '9:30': 2,
    '12:30': 3,
    '15:00': 4,
    '17:30': 5,
    '20:00': 6,
    '17:45': 7,
    '19:30': 8,
  }[time];
}

String _normalizeOcrInstructor(String value) =>
    _ocrInstructorPattern.firstMatch(value)?.group(1) ?? '';

String _normalizeOcrSubjectName(
  String value,
  String subjectCode,
  String instructor,
) {
  final containsScheduleNoise = _ocrTimePattern.hasMatch(value);
  final containsInstructor =
      instructor.isNotEmpty && value.contains(instructor);
  if (!containsScheduleNoise && !containsInstructor) return value.trim();

  var withoutScheduleNoise = value
      .replaceAll(
        RegExp(r'\d{1,2}\s*[:.hH]\s*\d{2}\s*[-–—]\s*\d{1,2}\s*[:.hH]\s*\d{2}'),
        ' ',
      )
      .replaceAll(
        RegExp(r'\b(?:online|offline|trực\s*tuyến)\b', caseSensitive: false),
        ' ',
      );
  if (instructor.isNotEmpty) {
    withoutScheduleNoise = withoutScheduleNoise.replaceAll(instructor, ' ');
  }
  withoutScheduleNoise = withoutScheduleNoise
      .replaceAll(RegExp(r'[^A-Za-zÀ-ỹ]+'), ' ')
      .trim();
  return withoutScheduleNoise.length >= 4 ? withoutScheduleNoise : subjectCode;
}

void _addUniqueOcrWarning(List<String> warnings, String message) {
  if (!warnings.contains(message)) warnings.add(message);
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
