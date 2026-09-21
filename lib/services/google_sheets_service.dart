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
  Sessions: ["SessionId", "ClassCode", "SubjectCode", "Slot", "SessionDate", "IsOpen", "OpenedAt", "ClosedAt", "LateAfterMinutes", "OtpPaused", "UpdatedAt"],
  Attendance: ["SessionId", "RollNo", "FullName", "Email", "ClassCode", "SubjectCode", "Slot", "Status", "CheckinTime", "Notes", "ConfirmationCode", "UpdatedAt"],
  DeviceBindings: ["SessionId", "BindingId", "DeviceCode", "RollNo", "FirstSeen", "LastSeen", "BlockedAttempts", "LastBlockedRollNo", "LastBlockedAt", "UpdatedAt"],
  AuditLog: ["SessionId", "AuditId", "RollNo", "Action", "PreviousStatus", "NewStatus", "Actor", "Reason", "CreatedAt", "UpdatedAt"]
};

function getSheet(name) {
  var book = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = book.getSheetByName(name) || book.insertSheet(name);
  var headers = SCHEMA[name];
  if (sheet.getLastRow() === 0) {
    sheet.getRange(1, 1, 1, headers.length).setValues([headers]);
    sheet.setFrozenRows(1);
    sheet.getRange(1, 1, 1, headers.length).setFontWeight("bold").setBackground("#1B2A4A").setFontColor("#FFFFFF");
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
  var sheet = getSheet(name);
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
    updatedAt
  ]];
  replaceRows("Sessions", function(item) {
    return String(item.SessionId) === String(session.sessionId);
  }, row);
}

function doGet(e) {
  try {
    var params = (e && e.parameter) || {};
    var action = String(params.action || "health");
    for (var name in SCHEMA) getSheet(name);

    if (action === "health") {
      return jsonOutput({status: "success", database: "Google Sheets", version: 3});
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

    if (action === "getAttendance") {
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
      var session = sessions.length ? sessions[0] : null;
      var students = session ? readObjects("Attendance").filter(function(item) {
        return String(item.SessionId) === String(session.SessionId);
      }).map(function(item) {
        return {
          rollNo: item.RollNo,
          fullName: item.FullName,
          email: item.Email,
          group: item.ClassCode,
          status: item.Status || "NOT CHECKED",
          checkinTime: item.CheckinTime || "",
          notes: item.Notes || ""
        };
      }) : [];
      return jsonOutput({
        status: "success",
        sessionId: session ? session.SessionId : null,
        isOpen: session ? (session.IsOpen === true || String(session.IsOpen).toLowerCase() === "true") : null,
        count: students.length,
        students: students
      });
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

    if (data.action === "seedDemo") {
      var demoClasses = [
        {classCode: "SE1917", subjectCode: "PRN232", slot: 1},
        {classCode: "SE1918", subjectCode: "PRM393", slot: 2},
        {classCode: "SE1919", subjectCode: "EXE201", slot: 1},
        {classCode: "SE1920", subjectCode: "HCM202", slot: 4}
      ];
      var names = [
        "Nguyễn Minh Anh", "Trần Gia Huy", "Lê Hoàng Yến", "Phạm Khánh Linh",
        "Võ Quốc Bảo", "Đỗ Thu Trang", "Bùi Nhật Minh", "Nguyễn Mai Hào Tiến"
      ];
      var demoDate = Utilities.formatDate(new Date(), Session.getScriptTimeZone(), "yyyy-MM-dd");
      var sessionRows = [];
      var attendanceRows = [];
      var auditRows = [];

      for (var c = 0; c < demoClasses.length; c++) {
        var demoClass = demoClasses[c];
        var rosterRows = [];
        var demoSessionId = ["DEMO", demoClass.classCode, demoClass.subjectCode].join("-");
        sessionRows.push([
          demoSessionId, demoClass.classCode, demoClass.subjectCode, demoClass.slot,
          demoDate, false, now, now, 10, false, now
        ]);

        for (var s = 0; s < names.length; s++) {
          var rollNo = demoClass.classCode.substring(0, 2) +
            String(191701 + c * 100 + s);
          var email = rollNo.toLowerCase() + "@fpt.edu.vn";
          rosterRows.push([demoClass.classCode, rollNo, names[s], email, now]);

          var status = ["PRESENT", "PRESENT", "LATE", "ABSENT", "NOT CHECKED"][s % 5];
          var checkinTime = status === "PRESENT" || status === "LATE" ? now : "";
          attendanceRows.push([
            demoSessionId, rollNo, names[s], email, demoClass.classCode,
            demoClass.subjectCode, demoClass.slot, status, checkinTime,
            status === "ABSENT" ? "Vắng có phép (demo)" : "", "DEMO" + (s + 1), now
          ]);
        }

        replaceRows("Rosters", function(item) {
          return String(item.ClassCode).toUpperCase() === demoClass.classCode;
        }, rosterRows);
        auditRows.push([
          demoSessionId, "DEMO-AUDIT-" + (c + 1), "", "DEMO_SEEDED", "", "",
          "Giảng viên demo", "Tạo dữ liệu minh họa", now, now
        ]);
      }

      replaceRows("Sessions", function(item) {
        return String(item.SessionId).indexOf("DEMO-") === 0;
      }, sessionRows);
      replaceRows("Attendance", function(item) {
        return String(item.SessionId).indexOf("DEMO-") === 0;
      }, attendanceRows);
      replaceRows("AuditLog", function(item) {
        return String(item.SessionId).indexOf("DEMO-") === 0;
      }, auditRows);
      replaceRows("DeviceBindings", function(item) {
        return String(item.SessionId).indexOf("DEMO-") === 0;
      }, [[
        "DEMO-SE1917-PRN232", "DEMO-DEVICE-1", "DV-DEMO-01", "SE191701",
        now, now, 1, "SE191702", now, now
      ]]);

      return jsonOutput({
        status: "success",
        classCount: demoClasses.length,
        studentCount: demoClasses.length * names.length,
        sessionCount: demoClasses.length
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
      upsertSession(session, now);

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
          binding.lastBlockedAt || "", now
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
