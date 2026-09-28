import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';
import '../models/student.dart';

class GoogleSheetsAttendanceResult {
  final List<Student> students;
  final bool? isOpen;
  final String source;

  const GoogleSheetsAttendanceResult({
    required this.students,
    required this.isOpen,
    required this.source,
  });
}

class GoogleSheetsService {
  String? webAppUrl;

  GoogleSheetsService({this.webAppUrl});

  bool get isConfigured => webAppUrl != null && webAppUrl!.trim().isNotEmpty;

  Uri _withQuery(String url, Map<String, String> values) {
    final uri = Uri.parse(url);
    return uri.replace(queryParameters: {...uri.queryParameters, ...values});
  }

  /// Fetch students list from a Google Sheets URL or Apps Script URL
  Future<List<Student>> fetchStudentsFromSheet(
    String inputUrl,
    String defaultClassCode,
  ) async {
    final cleanUrl = inputUrl.trim();
    if (cleanUrl.isEmpty) return [];

    try {
      String csvContent = '';

      // Case 1: Standard Google Sheets link (e.g., https://docs.google.com/spreadsheets/d/SHEET_ID/edit...)
      if (cleanUrl.contains('docs.google.com/spreadsheets/d/')) {
        final regExp = RegExp(r'/spreadsheets/d/([a-zA-Z0-9-_]+)');
        final match = regExp.firstMatch(cleanUrl);
        if (match != null && match.groupCount >= 1) {
          final sheetId = match.group(1);
          final exportUrl =
              'https://docs.google.com/spreadsheets/d/$sheetId/export?format=csv';
          final response = await http.get(Uri.parse(exportUrl));
          if (response.statusCode == 200) {
            csvContent = utf8.decode(response.bodyBytes);
          }
        }
      }
      // Case 2: Apps Script Web App URL or direct CSV endpoint
      else {
        final uri = _withQuery(cleanUrl, {
          'action': 'getRoster',
          'classCode': defaultClassCode,
        });
        final response = await http.get(uri);
        if (response.statusCode == 200) {
          final body = utf8.decode(response.bodyBytes).trim();
          if (body.startsWith('{') || body.startsWith('[')) {
            final json = jsonDecode(body);
            final List<dynamic> list = (json is Map && json['students'] != null)
                ? json['students']
                : (json is List ? json : []);
            return list
                .map((item) => Student.fromMap(Map<String, dynamic>.from(item)))
                .toList();
          } else {
            csvContent = body;
          }
        }
      }

      if (csvContent.isNotEmpty) {
        final List<List<dynamic>> rows = const CsvToListConverter().convert(
          csvContent,
        );
        if (rows.isEmpty) return [];

        final students = <Student>[];
        int startIdx = 0;
        if (rows.first.first.toString().toLowerCase().contains('roll') ||
            rows.first.first.toString().toLowerCase().contains('stt') ||
            rows.first.first.toString().toLowerCase().contains('mssv')) {
          startIdx = 1;
        }

        for (int i = startIdx; i < rows.length; i++) {
          final row = rows[i];
          if (row.length >= 2) {
            final rollNo = row[0].toString().trim();
            final fullName = row[1].toString().trim();
            final email = row.length > 2 ? row[2].toString().trim() : '';
            final group = row.length > 3
                ? row[3].toString().trim()
                : defaultClassCode;

            if (rollNo.isNotEmpty && fullName.isNotEmpty) {
              students.add(
                Student(
                  rollNo: rollNo,
                  fullName: fullName,
                  email: email.isNotEmpty
                      ? email
                      : '${rollNo.toLowerCase()}@fpt.edu.vn',
                  group: group.isNotEmpty ? group : defaultClassCode,
                ),
              );
            }
          }
        }
        return students;
      }
    } catch (e) {
      debugPrint('Error fetching students from sheet: $e');
    }
    return [];
  }

  /// Reads attendance records used by the FAP demo screen.
  ///
  /// Apps Script endpoints return session metadata as JSON. A public Google
  /// Sheet can also be used, but CSV cannot reliably expose whether a session
  /// is still open, so [isOpen] is null in that mode.
  Future<GoogleSheetsAttendanceResult> fetchAttendanceFromSheet({
    required String classCode,
    required String subjectCode,
    required int slot,
  }) async {
    if (!isConfigured) {
      return const GoogleSheetsAttendanceResult(
        students: [],
        isOpen: null,
        source: 'Chưa cấu hình',
      );
    }

    final cleanUrl = webAppUrl!.trim();
    try {
      if (cleanUrl.contains('docs.google.com/spreadsheets/d/')) {
        final match = RegExp(
          r'/spreadsheets/d/([a-zA-Z0-9-_]+)',
        ).firstMatch(cleanUrl);
        if (match == null) {
          throw const FormatException('URL Google Sheet không hợp lệ');
        }
        final sourceUri = Uri.parse(cleanUrl);
        final query = <String, String>{'format': 'csv'};
        final gid = sourceUri.queryParameters['gid'];
        if (gid != null && gid.isNotEmpty) query['gid'] = gid;
        final exportUri = Uri.https(
          'docs.google.com',
          '/spreadsheets/d/${match.group(1)}/export',
          query,
        );
        final response = await http.get(exportUri);
        if (response.statusCode != 200) {
          throw Exception('Google Sheets trả về HTTP ${response.statusCode}');
        }
        return GoogleSheetsAttendanceResult(
          students: _studentsFromCsv(
            utf8.decode(response.bodyBytes),
            classCode,
            subjectCode: subjectCode,
            slot: slot,
          ),
          isOpen: null,
          source: 'Google Sheet công khai',
        );
      }

      final response = await http.get(
        _withQuery(cleanUrl, {
          'action': 'getAttendance',
          'classCode': classCode,
          'subjectCode': subjectCode,
          'slot': '$slot',
        }),
      );
      if (response.statusCode != 200) {
        throw Exception('Apps Script trả về HTTP ${response.statusCode}');
      }
      final body = utf8.decode(response.bodyBytes).trim();
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const FormatException('Phản hồi không phải JSON object');
      }
      if (decoded['status'] == 'error') {
        throw Exception(decoded['error']?.toString() ?? 'Apps Script báo lỗi');
      }
      final rawStudents = decoded['students'];
      final students = rawStudents is List
          ? rawStudents
                .whereType<Map>()
                .map((item) => Student.fromMap(Map<String, dynamic>.from(item)))
                .where((student) => student.rollNo.trim().isNotEmpty)
                .toList()
          : <Student>[];
      return GoogleSheetsAttendanceResult(
        students: students,
        isOpen: decoded['isOpen'] is bool ? decoded['isOpen'] as bool : null,
        source: 'Google Apps Script',
      );
    } catch (error) {
      debugPrint('Google Sheets Attendance Fetch Error: $error');
      rethrow;
    }
  }

  List<Student> _studentsFromCsv(
    String csvContent,
    String defaultClassCode, {
    String? subjectCode,
    int? slot,
  }) {
    final rows = const CsvToListConverter().convert(csvContent);
    if (rows.isEmpty) return [];

    final headers = rows.first
        .map((value) => value.toString().trim().toLowerCase())
        .toList();
    int column(List<String> aliases, int fallback) {
      for (final alias in aliases) {
        final index = headers.indexOf(alias);
        if (index >= 0) return index;
      }
      return fallback;
    }

    final rollIndex = column(['rollno', 'mssv', 'studentcode'], 0);
    final nameIndex = column(['fullname', 'họ và tên', 'ho va ten'], 1);
    final emailIndex = column(['email'], 2);
    final groupIndex = column(['group', 'classcode', 'lớp', 'lop'], 3);
    final statusIndex = column(['status', 'trạng thái', 'trang thai'], 4);
    final checkinIndex = column(['checkintime', 'check-in'], 5);
    final notesIndex = column(['notes', 'ghi chú', 'ghi chu'], 6);
    final classIndex = column(['classcode'], -1);
    final subjectIndex = column(['subjectcode'], -1);
    final slotIndex = column(['slot'], -1);
    final result = <Student>[];

    String cell(List<dynamic> row, int index) =>
        index >= 0 && index < row.length ? row[index].toString().trim() : '';

    for (var index = 1; index < rows.length; index++) {
      final row = rows[index];
      final rowClass = cell(row, classIndex);
      final rowSubject = cell(row, subjectIndex);
      final rowSlot = int.tryParse(cell(row, slotIndex));
      if (rowClass.isNotEmpty &&
          rowClass.toUpperCase() != defaultClassCode.toUpperCase()) {
        continue;
      }
      if (subjectCode != null &&
          rowSubject.isNotEmpty &&
          rowSubject.toUpperCase() != subjectCode.toUpperCase()) {
        continue;
      }
      if (slot != null && rowSlot != null && rowSlot != slot) continue;

      final rollNo = cell(row, rollIndex);
      if (rollNo.isEmpty) continue;
      final email = cell(row, emailIndex);
      result.add(
        Student(
          rollNo: rollNo,
          fullName: cell(row, nameIndex).isEmpty
              ? rollNo
              : cell(row, nameIndex),
          email: email.isEmpty ? '${rollNo.toLowerCase()}@fpt.edu.vn' : email,
          group: rowClass.isEmpty
              ? (cell(row, groupIndex).isEmpty
                    ? defaultClassCode
                    : cell(row, groupIndex))
              : rowClass,
          status: AttendanceStatusExtension.fromString(cell(row, statusIndex)),
          checkinTime: DateTime.tryParse(cell(row, checkinIndex)),
          notes: cell(row, notesIndex),
        ),
      );
    }
    return result;
  }

  /// Sync student list and attendance statuses to Google Sheets
  Future<bool> pushAttendanceToSheet(
    List<Student> roster,
    String classCode,
    String subjectCode,
    int slot, {
    required bool isOpen,
  }) async {
    if (!isConfigured) return false;

    try {
      final payload = {
        'action': 'syncAttendance',
        'classCode': classCode,
        'subjectCode': subjectCode,
        'slot': slot,
        'date': DateTime.now().toIso8601String(),
        'isOpen': isOpen,
        'students': roster.map((s) => s.toMap()).toList(),
      };

      final response = await http.post(
        Uri.parse(webAppUrl!),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 302) {
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Google Sheets Sync Error: $e');
      return false;
    }
  }

  /// Single student check-in event push to Google Sheets
  Future<bool> pushSingleCheckin(
    Student student,
    String classCode,
    String subjectCode,
    int slot, {
    required bool isOpen,
  }) async {
    if (!isConfigured) return false;

    try {
      final payload = {
        'action': 'studentCheckin',
        'classCode': classCode,
        'subjectCode': subjectCode,
        'slot': slot,
        'isOpen': isOpen,
        'email': student.email,
        'rollNo': student.rollNo,
        'fullName': student.fullName,
        'status': student.status.toLabel(),
        'checkinTime':
            student.checkinTime?.toIso8601String() ??
            DateTime.now().toIso8601String(),
      };

      final response = await http.post(
        Uri.parse(webAppUrl!),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      return response.statusCode == 200 || response.statusCode == 302;
    } catch (e) {
      debugPrint('Single Checkin Push Error: $e');
      return false;
    }
  }

  /// Google Apps Script code template that user can copy & paste into Google Sheets
  static String get sampleAppsScriptCode => '''
/**
 * FAP Attendance - Google Sheets Primary Database
 * Paste this into Google Sheets -> Extensions -> Apps Script
 * Deploy as Web App (Execute as: Me, Who has access: Anyone)
 */
var SCHEMA = {
  Rosters: ["ClassCode", "RollNo", "FullName", "Email", "UpdatedAt"],
  Sessions: ["SessionId", "ClassCode", "SubjectCode", "Slot", "SessionDate", "IsOpen", "OpenedAt", "ClosedAt", "LateAfterMinutes", "OtpPaused", "UpdatedAt", "MeetingNumber", "TotalMeetings"],
  CourseMeetings: ["MeetingId", "ClassCode", "SubjectCode", "MeetingNumber", "TotalMeetings", "SessionDate", "Slot", "SessionId", "Status", "UpdatedAt"],
  Attendance: ["SessionId", "RollNo", "FullName", "Email", "ClassCode", "SubjectCode", "Slot", "Status", "CheckinTime", "Notes", "ConfirmationCode", "UpdatedAt"],
  DeviceBindings: ["SessionId", "BindingId", "DeviceCode", "RollNo", "FirstSeen", "LastSeen", "BlockedAttempts", "LastBlockedRollNo", "LastBlockedAt", "UpdatedAt", "DeviceHash", "NetworkHash", "UserAgentHash"],
  AuditLog: ["SessionId", "AuditId", "RollNo", "Action", "PreviousStatus", "NewStatus", "Actor", "Reason", "CreatedAt", "UpdatedAt"]
};

function getSheet(name, prepareForWrite) {
  var book = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = book.getSheetByName(name) || book.insertSheet(name);
  var headers = SCHEMA[name];
  if (sheet.getLastRow() === 0) {
    sheet.getRange(1, 1, 1, headers.length).setValues([headers]);
    sheet.setFrozenRows(1);
    sheet.getRange(1, 1, 1, headers.length).setFontWeight("bold").setBackground("#1B2A4A").setFontColor("#FFFFFF");
  } else if (prepareForWrite) {
    var currentHeaders = sheet.getRange(1, 1, 1, headers.length).getValues()[0];
    var needsMigration = headers.some(function(header, index) {
      return currentHeaders[index] !== header;
    });
    if (needsMigration) sheet.getRange(1, 1, 1, headers.length).setValues([headers]);
  }
  return sheet;
}

function jsonOutput(value) {
  return ContentService.createTextOutput(JSON.stringify(value))
    .setMimeType(ContentService.MimeType.JSON);
}

function readObjects(name) {
  var sheet = getSheet(name);
  var values = sheet.getDataRange().getValues();
  var headers = SCHEMA[name];
  var result = [];
  for (var i = 1; i < values.length; i++) {
    if (!values[i][0]) continue;
    var item = {};
    for (var c = 0; c < headers.length; c++) item[headers[c]] = values[i][c];
    result.push(item);
  }
  return result;
}

function replaceRows(name, shouldRemove, rows) {
  var sheet = getSheet(name, true);
  var headers = SCHEMA[name];
  var current = sheet.getDataRange().getValues();
  var output = [headers];
  for (var i = 1; i < current.length; i++) {
    var item = {};
    for (var c = 0; c < headers.length; c++) item[headers[c]] = current[i][c];
    if (current[i][0] && !shouldRemove(item)) output.push(current[i]);
  }
  for (var r = 0; r < rows.length; r++) output.push(rows[r]);
  sheet.clearContents();
  sheet.getRange(1, 1, output.length, headers.length).setValues(output);
  sheet.setFrozenRows(1);
  sheet.getRange(1, 1, 1, headers.length).setFontWeight("bold").setBackground("#1B2A4A").setFontColor("#FFFFFF");
}

function upsertSession(session, updatedAt) {
  var row = [[
    session.sessionId,
    session.classCode,
    session.subjectCode,
    session.slot,
    session.date,
    session.isOpen === true,
    session.openedAt || "",
    session.closedAt || "",
    session.lateAfterMinutes || 10,
    session.otpPaused === true,
    updatedAt,
    Number(session.sessionNumber || 0),
    Number(session.totalSessions || 20)
  ]];
  replaceRows("Sessions", function(item) {
    return String(item.SessionId) === String(session.sessionId);
  }, row);
}

function upsertCourseMeeting(session, updatedAt) {
  var meetingNumber = Number(session.sessionNumber || 0);
  if (meetingNumber < 1) return;
  var totalMeetings = Math.max(meetingNumber, Number(session.totalSessions || 20));
  var classCode = String(session.classCode || "").toUpperCase();
  var subjectCode = String(session.subjectCode || "").toUpperCase();
  var existing = {};
  readObjects("CourseMeetings").forEach(function(item) {
    if (String(item.ClassCode).toUpperCase() === classCode &&
        String(item.SubjectCode).toUpperCase() === subjectCode) {
      existing[Number(item.MeetingNumber || 0)] = item;
    }
  });
  var rows = [];
  for (var number = 1; number <= totalMeetings; number++) {
    var previous = existing[number] || {};
    var isCurrent = number === meetingNumber;
    rows.push([
      [classCode, subjectCode, number].join("|"),
      classCode,
      subjectCode,
      number,
      totalMeetings,
      isCurrent ? session.date : (previous.SessionDate || ""),
      isCurrent ? session.slot : (previous.Slot || ""),
      isCurrent ? session.sessionId : (previous.SessionId || ""),
      isCurrent
        ? (session.isOpen === true ? "OPEN" : (session.closedAt ? "CLOSED" : "PLANNED"))
        : (previous.Status || "PLANNED"),
      updatedAt
    ]);
  }
  replaceRows("CourseMeetings", function(item) {
    return String(item.ClassCode).toUpperCase() === classCode &&
      String(item.SubjectCode).toUpperCase() === subjectCode;
  }, rows);
}

function normalizeMeetingDate(value) {
  if (value instanceof Date) {
    return Utilities.formatDate(value, "Asia/Ho_Chi_Minh", "yyyy-MM-dd");
  }
  var text = String(value || "").trim();
  if (/^\\d{4}-\\d{2}-\\d{2}\$/.test(text)) return text;
  var parsed = new Date(text);
  if (!isNaN(parsed.getTime())) {
    return Utilities.formatDate(parsed, "Asia/Ho_Chi_Minh", "yyyy-MM-dd");
  }
  var match = text.match(/^(\\d{4}-\\d{2}-\\d{2})/);
  return match ? match[1] : text;
}

function sessionMeetingKey(item) {
  return [
    String(item.ClassCode || item.classCode || "").trim().toUpperCase(),
    String(item.SubjectCode || item.subjectCode || "").trim().toUpperCase(),
    normalizeMeetingDate(item.SessionDate || item.date || ""),
    Number(item.Slot || item.slot || 0)
  ].join("|");
}

function objectRow(name, item) {
  return SCHEMA[name].map(function(header) {
    return item[header] === undefined || item[header] === null ? "" : item[header];
  });
}

function syncCourseMeetingPlan(meetings, updatedAt) {
  var grouped = {};
  for (var i = 0; i < meetings.length; i++) {
    var input = meetings[i] || {};
    var classCode = String(input.classCode || "").trim().toUpperCase();
    var subjectCode = String(input.subjectCode || "").trim().toUpperCase();
    var meetingNumber = Number(input.meetingNumber || 0);
    var totalMeetings = Number(input.totalMeetings || 0);
    var slot = Number(input.slot || 0);
    var date = normalizeMeetingDate(input.date || "");
    if (!classCode || !subjectCode || meetingNumber < 1 ||
        totalMeetings < meetingNumber || slot < 1 || slot > 8 || !date) {
      throw new Error("Invalid course meeting plan");
    }
    var courseKey = classCode + "|" + subjectCode;
    if (!grouped[courseKey]) grouped[courseKey] = [];
    grouped[courseKey].push({
      classCode: classCode,
      subjectCode: subjectCode,
      meetingNumber: meetingNumber,
      totalMeetings: totalMeetings,
      date: date,
      slot: slot
    });
  }

  var existingMeetings = readObjects("CourseMeetings");
  var existingById = {};
  existingMeetings.forEach(function(item) {
    existingById[String(item.MeetingId || "")] = item;
  });
  var sessionsByKey = {};
  readObjects("Sessions").forEach(function(item) {
    var key = sessionMeetingKey(item);
    var current = sessionsByKey[key];
    var currentTime = current ? new Date(current.UpdatedAt || current.OpenedAt || 0).getTime() : 0;
    var itemTime = new Date(item.UpdatedAt || item.OpenedAt || 0).getTime();
    if (!current || itemTime >= currentTime) sessionsByKey[key] = item;
  });

  var count = 0;
  var courseCount = 0;
  Object.keys(grouped).forEach(function(courseKey) {
    var plan = grouped[courseKey];
    plan.sort(function(left, right) {
      return left.meetingNumber - right.meetingNumber;
    });
    var parts = courseKey.split("|");
    var rows = [];
    for (var p = 0; p < plan.length; p++) {
      var meeting = plan[p];
      var meetingId = [meeting.classCode, meeting.subjectCode, meeting.meetingNumber].join("|");
      var previous = existingById[meetingId] || {};
      var linkedSession = sessionsByKey[
        [meeting.classCode, meeting.subjectCode, meeting.date, meeting.slot].join("|")
      ];
      var sessionId = previous.SessionId || (linkedSession ? linkedSession.SessionId : "");
      var status = previous.Status || "PLANNED";
      if (linkedSession) {
        status = boolValue(linkedSession.IsOpen)
          ? "OPEN"
          : (linkedSession.ClosedAt ? "CLOSED" : "PLANNED");
      }
      rows.push([
        meetingId,
        meeting.classCode,
        meeting.subjectCode,
        meeting.meetingNumber,
        meeting.totalMeetings,
        meeting.date,
        meeting.slot,
        sessionId,
        status,
        updatedAt
      ]);
      count++;
    }
    replaceRows("CourseMeetings", function(item) {
      return String(item.ClassCode).toUpperCase() === parts[0] &&
        String(item.SubjectCode).toUpperCase() === parts[1];
    }, rows);
    courseCount++;
  });
  return {count: count, courseCount: courseCount};
}

function createAttendanceBackup() {
  var source = SpreadsheetApp.getActiveSpreadsheet();
  var stamp = Utilities.formatDate(new Date(), "Asia/Ho_Chi_Minh", "yyyyMMdd-HHmmss");
  var backup = SpreadsheetApp.create(source.getName() + " backup " + stamp);
  var names = ["Sessions", "CourseMeetings", "Attendance", "DeviceBindings", "AuditLog"];
  for (var i = 0; i < names.length; i++) {
    getSheet(names[i], false).copyTo(backup).setName(names[i]);
  }
  var sheets = backup.getSheets();
  for (var s = sheets.length - 1; s >= 0; s--) {
    if (names.indexOf(sheets[s].getName()) < 0 && backup.getSheets().length > 1) {
      backup.deleteSheet(sheets[s]);
    }
  }
  return backup.getUrl();
}

function normalizeDuplicateSessions(updatedAt) {
  var sessions = readObjects("Sessions");
  var attendance = readObjects("Attendance");
  var bindings = readObjects("DeviceBindings");
  var audit = readObjects("AuditLog");
  var meetings = readObjects("CourseMeetings");
  var groups = {};
  sessions.forEach(function(item) {
    var key = sessionMeetingKey(item);
    if (!groups[key]) groups[key] = [];
    groups[key].push(item);
  });
  var duplicateKeys = Object.keys(groups).filter(function(key) {
    return key && groups[key].length > 1;
  });
  var openSessionCount = sessions.filter(function(item) {
    return boolValue(item.IsOpen);
  }).length;
  if (!duplicateKeys.length && !openSessionCount) {
    return {
      duplicateGroups: 0,
      removedSessions: 0,
      closedSessions: 0,
      backupUrl: "",
      sessionCount: sessions.length
    };
  }

  var backupUrl = createAttendanceBackup();
  var replacementById = {};
  var mergedSessions = [];
  var mergedAttendance = [];
  var mergedBindings = [];
  var mergedAudit = [];
  var duplicateIds = {};
  var closedSessions = 0;

  duplicateKeys.forEach(function(key) {
    groups[key].forEach(function(item) { duplicateIds[String(item.SessionId)] = true; });
  });
  sessions.forEach(function(item) {
    if (!duplicateIds[String(item.SessionId)]) {
      if (boolValue(item.IsOpen)) {
        item.IsOpen = false;
        item.ClosedAt = updatedAt;
        item.UpdatedAt = updatedAt;
        closedSessions++;
      }
      mergedSessions.push(objectRow("Sessions", item));
    }
  });
  attendance.forEach(function(item) {
    if (!duplicateIds[String(item.SessionId)]) mergedAttendance.push(objectRow("Attendance", item));
  });
  bindings.forEach(function(item) {
    if (!duplicateIds[String(item.SessionId)]) mergedBindings.push(objectRow("DeviceBindings", item));
  });
  audit.forEach(function(item) {
    if (!duplicateIds[String(item.SessionId)]) mergedAudit.push(objectRow("AuditLog", item));
  });

  duplicateKeys.forEach(function(key) {
    var group = groups[key];
    group.sort(function(left, right) {
      function score(item) {
        var id = String(item.SessionId);
        var rows = attendance.filter(function(record) { return String(record.SessionId) === id; });
        var present = rows.filter(function(record) {
          return String(record.Status).toUpperCase() === "PRESENT" ||
            String(record.Status).toUpperCase() === "LATE";
        }).length;
        var time = new Date(item.UpdatedAt || item.OpenedAt || 0).getTime();
        return (boolValue(item.IsOpen) ? 1000000000000000 : 0) +
          present * 1000000000 + rows.length * 1000000 + (isNaN(time) ? 0 : time);
      }
      return score(right) - score(left);
    });
    var canonical = group[0];
    var canonicalId = String(canonical.SessionId);
    var anyOpen = group.some(function(item) { return boolValue(item.IsOpen); });
    closedSessions += group.filter(function(item) {
      return boolValue(item.IsOpen);
    }).length;
    canonical.IsOpen = false;
    canonical.ClosedAt = anyOpen ? updatedAt : canonical.ClosedAt;
    canonical.UpdatedAt = updatedAt;
    canonical.MeetingNumber = group.reduce(function(best, item) {
      var number = Number(item.MeetingNumber || 0);
      return number > 0 && (best === 0 || number < best) ? number : best;
    }, 0);
    canonical.TotalMeetings = group.reduce(function(best, item) {
      return Math.max(best, Number(item.TotalMeetings || 20));
    }, 20);
    mergedSessions.push(objectRow("Sessions", canonical));
    group.forEach(function(item) { replacementById[String(item.SessionId)] = canonicalId; });

    var studentByRollNo = {};
    attendance.forEach(function(item) {
      if (!replacementById[String(item.SessionId)] || replacementById[String(item.SessionId)] !== canonicalId) return;
      var rollNo = String(item.RollNo || "").trim().toUpperCase();
      if (!rollNo) return;
      var current = studentByRollNo[rollNo];
      var candidatePresent = String(item.Status).toUpperCase() === "PRESENT" ||
        String(item.Status).toUpperCase() === "LATE";
      var currentPresent = current && String(current.Status).toUpperCase() === "PRESENT";
      if (!current || (candidatePresent && !currentPresent) ||
          (candidatePresent === currentPresent && item.CheckinTime && !current.CheckinTime)) {
        var copy = {};
        Object.keys(item).forEach(function(name) { copy[name] = item[name]; });
        copy.SessionId = canonicalId;
        copy.Status = candidatePresent ? "PRESENT" : "ABSENT";
        copy.ClassCode = canonical.ClassCode;
        copy.SubjectCode = canonical.SubjectCode;
        copy.Slot = canonical.Slot;
        copy.UpdatedAt = updatedAt;
        studentByRollNo[rollNo] = copy;
      }
    });
    Object.keys(studentByRollNo).sort().forEach(function(rollNo) {
      mergedAttendance.push(objectRow("Attendance", studentByRollNo[rollNo]));
    });

    var bindingKeys = {};
    bindings.forEach(function(item) {
      if (!replacementById[String(item.SessionId)] || replacementById[String(item.SessionId)] !== canonicalId) return;
      var bindingKey = String(item.BindingId || "") + "|" + String(item.DeviceHash || "") + "|" + String(item.RollNo || "");
      if (bindingKeys[bindingKey]) return;
      bindingKeys[bindingKey] = true;
      item.SessionId = canonicalId;
      item.UpdatedAt = updatedAt;
      mergedBindings.push(objectRow("DeviceBindings", item));
    });

    var auditKeys = {};
    audit.forEach(function(item) {
      if (!replacementById[String(item.SessionId)] || replacementById[String(item.SessionId)] !== canonicalId) return;
      var auditKey = [item.AuditId, item.Action, item.RollNo, item.CreatedAt].join("|");
      if (auditKeys[auditKey]) return;
      auditKeys[auditKey] = true;
      item.SessionId = canonicalId;
      item.UpdatedAt = updatedAt;
      mergedAudit.push(objectRow("AuditLog", item));
    });
  });

  for (var m = 0; m < meetings.length; m++) {
    var linkedId = String(meetings[m].SessionId || "");
    if (replacementById[linkedId]) {
      meetings[m].SessionId = replacementById[linkedId];
      linkedId = meetings[m].SessionId;
    }
    if (linkedId) {
      meetings[m].Status = "CLOSED";
      meetings[m].UpdatedAt = updatedAt;
    }
  }
  replaceRows("Sessions", function() { return true; }, mergedSessions);
  replaceRows("Attendance", function() { return true; }, mergedAttendance);
  replaceRows("DeviceBindings", function() { return true; }, mergedBindings);
  replaceRows("AuditLog", function() { return true; }, mergedAudit);
  replaceRows("CourseMeetings", function() { return true; }, meetings.map(function(item) {
    return objectRow("CourseMeetings", item);
  }));

  return {
    duplicateGroups: duplicateKeys.length,
    removedSessions: Object.keys(duplicateIds).length - duplicateKeys.length,
    closedSessions: closedSessions,
    backupUrl: backupUrl,
    sessionCount: mergedSessions.length
  };
}

function boolValue(value) {
  return value === true || String(value).toLowerCase() === "true";
}

function buildSessionPayload(session, allAttendance, allBindings, allAudit) {
  if (!session) {
    return {status: "success", sessionId: null, count: 0, students: [], deviceBindings: [], auditLogs: []};
  }
  var sessionId = String(session.SessionId);
  var students = allAttendance.filter(function(item) {
    return String(item.SessionId) === sessionId;
  }).map(function(item) {
    return {
      sessionId: sessionId,
      rollNo: item.RollNo,
      fullName: item.FullName,
      email: item.Email,
      classCode: item.ClassCode,
      subjectCode: item.SubjectCode,
      slot: Number(item.Slot || session.Slot || 0),
      status: item.Status || "ABSENT",
      checkinTime: item.CheckinTime || null,
      notes: item.Notes || "",
      confirmationCode: item.ConfirmationCode || ""
    };
  });
  var deviceBindings = allBindings.filter(function(item) {
    return String(item.SessionId) === sessionId;
  }).map(function(item) {
    return {
      id: Number(item.BindingId || 0),
      deviceCode: item.DeviceCode || "",
      rollNo: item.RollNo || "",
      firstSeen: item.FirstSeen || null,
      lastSeen: item.LastSeen || null,
      blockedAttempts: Number(item.BlockedAttempts || 0),
      lastBlockedRollNo: item.LastBlockedRollNo || "",
      lastBlockedAt: item.LastBlockedAt || null,
      deviceHash: item.DeviceHash || "",
      networkHash: item.NetworkHash || "",
      userAgentHash: item.UserAgentHash || ""
    };
  });
  var auditLogs = allAudit.filter(function(item) {
    return String(item.SessionId) === sessionId;
  }).map(function(item) {
    return {
      id: Number(item.AuditId || 0),
      rollNo: item.RollNo || "",
      action: item.Action || "",
      previousStatus: item.PreviousStatus || "",
      newStatus: item.NewStatus || "",
      actor: item.Actor || "",
      reason: item.Reason || "",
      createdAt: item.CreatedAt || null
    };
  });
  return {
    status: "success",
    sessionId: sessionId,
    classCode: session.ClassCode || "",
    subjectCode: session.SubjectCode || "",
    slot: Number(session.Slot || 0),
    sessionNumber: Number(session.MeetingNumber || 0),
    totalSessions: Number(session.TotalMeetings || 20),
    date: session.SessionDate || "",
    isOpen: boolValue(session.IsOpen),
    openedAt: session.OpenedAt || null,
    closedAt: session.ClosedAt || null,
    lateAfterMinutes: Number(session.LateAfterMinutes || 10),
    otpPaused: boolValue(session.OtpPaused),
    count: students.length,
    students: students,
    deviceBindings: deviceBindings,
    auditLogs: auditLogs
  };
}

function doGet(e) {
  try {
    var params = (e && e.parameter) || {};
    var action = String(params.action || "health");

    if (action === "health") {
      return jsonOutput({status: "success", database: "Google Sheets", version: 7});
    }

    if (action === "getRoster" || action === "getStudents") {
      var wantedClass = String(params.classCode || "").toUpperCase();
      var roster = readObjects("Rosters").filter(function(item) {
        return !wantedClass || String(item.ClassCode).toUpperCase() === wantedClass;
      }).map(function(item) {
        return {rollNo: item.RollNo, fullName: item.FullName, email: item.Email, group: item.ClassCode};
      });
      return jsonOutput({status: "success", count: roster.length, students: roster});
    }

    if (action === "getAttendance" || action === "getSessions") {
      var wantedSession = String(params.sessionId || "");
      var wantedClass = String(params.classCode || "").toUpperCase();
      var wantedSubject = String(params.subjectCode || "").toUpperCase();
      var wantedSlot = String(params.slot || "");
      var sessions = readObjects("Sessions").filter(function(item) {
        return (!wantedSession || String(item.SessionId) === wantedSession) &&
          (!wantedClass || String(item.ClassCode).toUpperCase() === wantedClass) &&
          (!wantedSubject || String(item.SubjectCode).toUpperCase() === wantedSubject) &&
          (!wantedSlot || String(item.Slot) === wantedSlot);
      });
      sessions.sort(function(a, b) {
        return new Date(b.UpdatedAt || b.OpenedAt).getTime() - new Date(a.UpdatedAt || a.OpenedAt).getTime();
      });
      var attendance = readObjects("Attendance");
      var bindings = readObjects("DeviceBindings");
      var audit = readObjects("AuditLog");
      if (action === "getSessions") {
        var limit = Math.max(1, Math.min(100, Number(params.limit || 20)));
        return jsonOutput({
          status: "success",
          count: Math.min(limit, sessions.length),
          sessions: sessions.slice(0, limit).map(function(session) {
            return buildSessionPayload(session, attendance, bindings, audit);
          })
        });
      }
      return jsonOutput(buildSessionPayload(sessions.length ? sessions[0] : null, attendance, bindings, audit));
    }

    if (action === "getCourseMeetings") {
      var meetingClass = String(params.classCode || "").toUpperCase();
      var meetingSubject = String(params.subjectCode || "").toUpperCase();
      var courseMeetings = readObjects("CourseMeetings").filter(function(item) {
        return (!meetingClass || String(item.ClassCode).toUpperCase() === meetingClass) &&
          (!meetingSubject || String(item.SubjectCode).toUpperCase() === meetingSubject);
      });
      courseMeetings.sort(function(left, right) {
        return Number(left.MeetingNumber || 0) - Number(right.MeetingNumber || 0);
      });
      return jsonOutput({status: "success", count: courseMeetings.length, meetings: courseMeetings});
    }

    return jsonOutput({status: "error", error: "Unsupported action"});
  } catch (err) {
    return jsonOutput({status: "error", error: err.toString()});
  }
}

function doPost(e) {
  var lock = LockService.getScriptLock();
  try {
    lock.waitLock(15000);
    var data = JSON.parse(e.postData.contents);
    var now = data.syncedAt || data.updatedAt || new Date().toISOString();

    if (data.action === "syncCourseMeetings") {
      var syncResult = syncCourseMeetingPlan(data.meetings || [], now);
      return jsonOutput({
        status: "success",
        message: "Đã đồng bộ kế hoạch buổi học.",
        count: syncResult.count,
        courseCount: syncResult.courseCount
      });
    }

    if (data.action === "normalizeDuplicateSessions") {
      var normalizeResult = normalizeDuplicateSessions(now);
      return jsonOutput({
        status: "success",
        message: normalizeResult.duplicateGroups
          ? "Đã gộp session trùng, đóng phiên còn mở và tạo bản sao lưu."
          : (normalizeResult.closedSessions
            ? "Đã đóng các session còn mở và tạo bản sao lưu."
            : "Không còn session trùng hoặc đang mở."),
        duplicateGroups: normalizeResult.duplicateGroups,
        removedSessions: normalizeResult.removedSessions,
        closedSessions: normalizeResult.closedSessions,
        sessionCount: normalizeResult.sessionCount,
        backupUrl: normalizeResult.backupUrl
      });
    }

    if (data.action === "seedDemo") {
      var demoClasses = [
        {classCode: "SE1917", subjectCode: "PRN232"},
        {classCode: "SE1918", subjectCode: "PRM393"},
        {classCode: "SE1919", subjectCode: "EXE201"},
        {classCode: "SE1920", subjectCode: "HCM202"}
      ];
      var demoSchedule = [
        {sessionId: "DEMO-20260914-SE1918-PRM393-S2", classCode: "SE1918", subjectCode: "PRM393", slot: 2, sessionNumber: 1, totalSessions: 20, date: "2026-09-14", openedAt: "2026-09-14T02:30:00.000Z", closedAt: "2026-09-14T04:45:00.000Z", completed: true},
        {sessionId: "DEMO-20260917-SE1918-PRM393-S2", classCode: "SE1918", subjectCode: "PRM393", slot: 2, sessionNumber: 2, totalSessions: 20, date: "2026-09-17", openedAt: "2026-09-17T02:30:00.000Z", closedAt: "2026-09-17T04:45:00.000Z", completed: true},
        {sessionId: "DEMO-SE1917-PRN232", classCode: "SE1917", subjectCode: "PRN232", slot: 1, sessionNumber: 3, totalSessions: 20, date: "2026-09-21", openedAt: "2026-09-21T00:00:00.000Z", closedAt: "2026-09-21T02:15:00.000Z", completed: true},
        {sessionId: "DEMO-SE1918-PRM393", classCode: "SE1918", subjectCode: "PRM393", slot: 2, sessionNumber: 3, totalSessions: 20, date: "2026-09-21", openedAt: "2026-09-21T02:30:00.000Z", closedAt: "2026-09-21T04:45:00.000Z", completed: true},
        {sessionId: "DEMO-SE1920-HCM202", classCode: "SE1920", subjectCode: "HCM202", slot: 1, sessionNumber: 5, totalSessions: 20, date: "2026-09-22", openedAt: "2026-09-22T00:00:00.000Z", closedAt: "2026-09-22T02:15:00.000Z", completed: true},
        {sessionId: "DEMO-SE1919-EXE201", classCode: "SE1919", subjectCode: "EXE201", slot: 2, sessionNumber: 5, totalSessions: 20, date: "2026-09-23", openedAt: "2026-09-23T02:30:00.000Z", closedAt: "", completed: false},
        {sessionId: "DEMO-20260924-SE1917-PRN232-S1", classCode: "SE1917", subjectCode: "PRN232", slot: 1, sessionNumber: 4, totalSessions: 20, date: "2026-09-24", openedAt: "2026-09-24T00:00:00.000Z", closedAt: "", completed: false},
        {sessionId: "DEMO-20260924-SE1918-PRM393-S2", classCode: "SE1918", subjectCode: "PRM393", slot: 2, sessionNumber: 4, totalSessions: 20, date: "2026-09-24", openedAt: "2026-09-24T02:30:00.000Z", closedAt: "2026-09-24T04:45:00.000Z", completed: true},
        {sessionId: "DEMO-20260924-SE1920-HCM202-S4", classCode: "SE1920", subjectCode: "HCM202", slot: 1, sessionNumber: 6, totalSessions: 20, date: "2026-09-25", openedAt: "2026-09-25T00:00:00.000Z", closedAt: "", completed: false}
      ];
      var names = [
        "Nguyễn Minh Anh", "Trần Gia Huy", "Lê Hoàng Yến", "Phạm Khánh Linh",
        "Võ Quốc Bảo", "Đỗ Thu Trang", "Bùi Nhật Minh", "Nguyễn Mai Hào Tiến",
        "Phan Thị Thảo Vy", "Chu Vương Mạnh", "Nguyễn Hoàng Nam", "Trương Quỳnh Như",
        "Lý Gia Bảo", "Huỳnh Ngọc Hân", "Đặng Minh Quân", "Hồ Nhật Linh",
        "Phan Tuấn Kiệt", "Vũ Thảo Nguyên", "Nguyễn Đức Anh", "Trần Khánh Vy",
        "Lê Quốc Trung", "Phạm Ngọc Mai", "Võ Minh Khang", "Đỗ Hà My",
        "Bùi Anh Tuấn", "Nguyễn Thanh Trúc", "Trần Gia Minh", "Lê Thu Hương",
        "Phạm Đức Long", "Võ Hoài An", "Đặng Quốc Khánh", "Hồ Ngọc Diệp",
        "Phan Minh Triết", "Vũ Khánh An", "Nguyễn Hải Đăng"
      ];
      var sessionRows = [];
      var meetingRows = [];
      var attendanceRows = [];
      var auditRows = [];

      for (var c = 0; c < demoClasses.length; c++) {
        var demoClass = demoClasses[c];
        var rosterRows = [];
        for (var s = 0; s < names.length; s++) {
          var rollNo = "SE" + String(191701 + s);
          var email = rollNo.toLowerCase() + "@fpt.edu.vn";
          rosterRows.push([demoClass.classCode, rollNo, names[s], email, now]);
        }

        replaceRows("Rosters", function(item) {
          return String(item.ClassCode).toUpperCase() === demoClass.classCode;
        }, rosterRows);
      }

      for (var d = 0; d < demoSchedule.length; d++) {
        var demoClassSession = demoSchedule[d];
        sessionRows.push([
          demoClassSession.sessionId, demoClassSession.classCode, demoClassSession.subjectCode,
          demoClassSession.slot, demoClassSession.date, false, demoClassSession.openedAt,
          demoClassSession.closedAt, 10, false, now,
          demoClassSession.sessionNumber, demoClassSession.totalSessions
        ]);
        meetingRows.push([
          [demoClassSession.classCode, demoClassSession.subjectCode, demoClassSession.sessionNumber].join("|"),
          demoClassSession.classCode, demoClassSession.subjectCode,
          demoClassSession.sessionNumber, demoClassSession.totalSessions,
          demoClassSession.date, demoClassSession.slot, demoClassSession.sessionId,
          demoClassSession.closedAt ? "CLOSED" : "PLANNED", now
        ]);

        for (var a = 0; a < names.length; a++) {
          var studentRollNo = "SE" + String(191701 + a);
          var studentEmail = studentRollNo.toLowerCase() + "@fpt.edu.vn";
          var status = "ABSENT";
          if (demoClassSession.completed) {
            var isAttendanceRiskDemo =
              demoClassSession.classCode === "SE1918" &&
              demoClassSession.subjectCode === "PRM393" &&
              demoClassSession.sessionNumber <= 4 && a === 0;
            var isSingleSessionDemoAbsence = demoClassSession.classCode === "SE1918"
              ? (demoClassSession.sessionNumber === 3 && a === 6) ||
                (demoClassSession.sessionNumber === 4 && a === 18)
              : a === 6 || a === 18;
            status = isAttendanceRiskDemo || isSingleSessionDemoAbsence
              ? "ABSENT"
              : "PRESENT";
          }
          var checkinTime = status === "PRESENT"
            ? demoClassSession.openedAt
            : "";
          attendanceRows.push([
            demoClassSession.sessionId, studentRollNo, names[a], studentEmail,
            demoClassSession.classCode, demoClassSession.subjectCode, demoClassSession.slot,
            status, checkinTime, status === "ABSENT" ? "Vắng có phép (demo)" : "",
            "DEMO" + String(a + 1), now
          ]);
        }

        auditRows.push([
          demoClassSession.sessionId, 1000 + d, "", "DEMO_SEEDED", "", "",
          "Giảng viên demo", "Seed lịch tuần 21/09–27/09/2026", now, now
        ]);
      }

      replaceRows("Sessions", function(item) {
        return String(item.SessionId).indexOf("DEMO-") === 0;
      }, sessionRows);
      replaceRows("CourseMeetings", function(item) {
        return String(item.SessionId).indexOf("DEMO-") === 0;
      }, meetingRows);
      replaceRows("Attendance", function(item) {
        return String(item.SessionId).indexOf("DEMO-") === 0;
      }, attendanceRows);
      replaceRows("AuditLog", function(item) {
        return String(item.SessionId).indexOf("DEMO-") === 0;
      }, auditRows);
      replaceRows("DeviceBindings", function(item) {
        return String(item.SessionId).indexOf("DEMO-") === 0;
      }, []);

      return jsonOutput({
        status: "success",
        classCount: demoClasses.length,
        studentCount: names.length,
        rosterRowCount: demoClasses.length * names.length,
        sessionCount: demoSchedule.length,
        attendanceCount: demoSchedule.length * names.length
      });
    }

    if (data.action === "syncRoster") {
      var classCode = String(data.classCode || "").toUpperCase();
      var students = data.students || [];
      var rows = [];
      for (var i = 0; i < students.length; i++) {
        var s = students[i];
        rows.push([classCode, String(s.rollNo || "").toUpperCase(), s.fullName || s.rollNo, s.email || "", now]);
      }
      replaceRows("Rosters", function(item) {
        return String(item.ClassCode).toUpperCase() === classCode;
      }, rows);
      return jsonOutput({status: "success", count: students.length});
    }

    if (data.action === "syncSession") {
      var session = data.session || {};
      var sessionId = String(session.sessionId || "");
      if (!sessionId) throw new Error("Missing sessionId");
      var meetingKey = sessionMeetingKey(session);
      var conflictingSession = readObjects("Sessions").filter(function(item) {
        return sessionMeetingKey(item) === meetingKey &&
          String(item.SessionId) !== sessionId;
      })[0];
      if (conflictingSession) {
        throw new Error(
          "DUPLICATE_MEETING: ca học đã thuộc session " + conflictingSession.SessionId
        );
      }
      upsertSession(session, now);
      upsertCourseMeeting(session, now);

      var attendanceRows = [];
      var attendance = session.students || [];
      for (var i = 0; i < attendance.length; i++) {
        var s = attendance[i];
        attendanceRows.push([
          sessionId, s.rollNo, s.fullName, s.email, session.classCode, session.subjectCode,
          session.slot, s.status, s.checkinTime || "", s.notes || "", s.confirmationCode || "", now
        ]);
      }
      replaceRows("Attendance", function(item) {
        return String(item.SessionId) === sessionId;
      }, attendanceRows);

      var deviceRows = [];
      var bindings = session.deviceBindings || [];
      for (var d = 0; d < bindings.length; d++) {
        var binding = bindings[d];
        deviceRows.push([
          sessionId, binding.id, binding.deviceCode, binding.rollNo, binding.firstSeen,
          binding.lastSeen, binding.blockedAttempts, binding.lastBlockedRollNo || "",
          binding.lastBlockedAt || "", now, binding.deviceHash || "",
          binding.networkHash || "", binding.userAgentHash || ""
        ]);
      }
      replaceRows("DeviceBindings", function(item) {
        return String(item.SessionId) === sessionId;
      }, deviceRows);

      var auditRows = [];
      var audit = data.auditLogs || [];
      for (var a = 0; a < audit.length; a++) {
        var log = audit[a];
        auditRows.push([
          sessionId, log.id, log.rollNo || "", log.action, log.previousStatus || "",
          log.newStatus || "", log.actor || "", log.reason || "", log.createdAt, now
        ]);
      }
      replaceRows("AuditLog", function(item) {
        return String(item.SessionId) === sessionId;
      }, auditRows);

      return jsonOutput({status: "success", sessionId: sessionId, count: attendance.length});
    }

    if (data.action === "syncAttendance") {
      var legacySessionId = [data.classCode, data.subjectCode, data.slot, String(data.date || "").substring(0, 10)].join("-");
      var legacySession = {
        sessionId: legacySessionId,
        classCode: data.classCode,
        subjectCode: data.subjectCode,
        slot: data.slot,
        date: String(data.date || "").substring(0, 10),
        isOpen: data.isOpen === true,
        openedAt: data.date,
        closedAt: data.isOpen === true ? "" : now,
        lateAfterMinutes: 10,
        otpPaused: false,
        sessionNumber: Number(data.sessionNumber || 0),
        totalSessions: Number(data.totalSessions || 20),
        students: (data.students || []).map(function(s) {
          return {
            rollNo: s.rollNo, fullName: s.fullName, email: s.email,
            status: s.status, checkinTime: s.checkinTime, notes: s.notes,
            confirmationCode: ""
          };
        }),
        deviceBindings: []
      };
      lock.releaseLock();
      return doPost({postData: {contents: JSON.stringify({
        action: "syncSession", session: legacySession, auditLogs: [], syncedAt: now
      })}});
    }
  } catch (err) {
    return jsonOutput({status: "error", error: err.toString()});
  } finally {
    try { lock.releaseLock(); } catch (ignored) {}
  }
  return jsonOutput({status: "error", error: "Unsupported action"});
}
''';
}
