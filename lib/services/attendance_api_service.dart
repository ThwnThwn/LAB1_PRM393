import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/attendance_session.dart';
import '../models/student.dart';
import 'runtime_environment.dart';

class AttendanceApiService {
  static const String _configuredServerUrl = String.fromEnvironment(
    'ATTENDANCE_SERVER_URL',
    defaultValue: '',
  );
  static const String _configuredTeacherToken = String.fromEnvironment(
    'ATTENDANCE_TEACHER_TOKEN',
    defaultValue: '',
  );

  String get _runtimeServerUrl =>
      readRuntimeEnvironment('ATTENDANCE_SERVER_URL');

  String get _teacherToken {
    final runtimeToken = readRuntimeEnvironment('ATTENDANCE_TEACHER_TOKEN');
    return runtimeToken.isNotEmpty ? runtimeToken : _configuredTeacherToken;
  }

  String get baseUrl {
    if (_runtimeServerUrl.isNotEmpty) {
      return _runtimeServerUrl.replaceAll(RegExp(r'/$'), '');
    }

    if (_configuredServerUrl.isNotEmpty) {
      return _configuredServerUrl.replaceAll(RegExp(r'/$'), '');
    }

    if (Uri.base.scheme == 'http' || Uri.base.scheme == 'https') {
      return Uri.base.origin;
    }

    return 'http://localhost:8080';
  }

  String exportUrl(String sessionId) {
    final uri = Uri.parse(
      '$baseUrl/api/sessions/${Uri.encodeComponent(sessionId)}/export.csv',
    );
    if (_teacherToken.isEmpty) return uri.toString();
    return uri
        .replace(
          queryParameters: {
            ...uri.queryParameters,
            'teacherToken': _teacherToken,
          },
        )
        .toString();
  }

  Future<Map<String, dynamic>> getGoogleSheetsConfiguration({
    bool verify = false,
  }) {
    return _sendJson('GET', '/api/config/google-sheets?verify=$verify', null);
  }

  Future<Map<String, dynamic>> configureGoogleSheets(String webAppUrl) {
    return _sendJson('PUT', '/api/config/google-sheets', {
      'webAppUrl': webAppUrl,
    });
  }

  Future<Map<String, dynamic>> syncSessionToGoogleSheets(String sessionId) {
    return _sendJson(
      'POST',
      '/api/google-sheets/sync/${Uri.encodeComponent(sessionId)}',
      null,
    );
  }

  Future<Map<String, dynamic>> seedGoogleSheetsDemo() {
    return _sendJson('POST', '/api/google-sheets/seed-demo', null);
  }

  Future<Map<String, dynamic>> openSession(
    AttendanceSession session,
    List<Student> students,
  ) async {
    return _sendJson('POST', '/api/sessions', {
      'classCode': session.classCode,
      'subjectCode': session.subjectCode,
      'slot': session.slot,
      'date': session.date.toIso8601String().split('T').first,
      'lateAfterMinutes': 10,
      'actor': 'Giảng viên',
      'students': students
          .map(
            (student) => {
              'rollNo': student.rollNo,
              'fullName': student.fullName,
              'email': student.email,
            },
          )
          .toList(),
    });
  }

  Future<Map<String, dynamic>> closeSession(String sessionId) async {
    return _sendJson(
      'POST',
      '/api/sessions/${Uri.encodeComponent(sessionId)}/close?actor=${Uri.encodeComponent('Giảng viên')}',
      null,
    );
  }

  Future<Map<String, dynamic>> pauseOtp(String sessionId) async {
    return _sendJson(
      'POST',
      '/api/sessions/${Uri.encodeComponent(sessionId)}/otp/pause?actor=${Uri.encodeComponent('Giảng viên')}',
      null,
    );
  }

  Future<Map<String, dynamic>> resumeOtp(String sessionId) async {
    return _sendJson(
      'POST',
      '/api/sessions/${Uri.encodeComponent(sessionId)}/otp/resume?actor=${Uri.encodeComponent('Giảng viên')}',
      null,
    );
  }

  Future<Map<String, dynamic>> getSession(String sessionId) async {
    return _sendJson(
      'GET',
      '/api/sessions/${Uri.encodeComponent(sessionId)}',
      null,
    );
  }

  Future<List<Map<String, dynamic>>> getSessions({
    int limit = 100,
    String? classCode,
    String? subjectCode,
    int? slot,
  }) async {
    final query = Uri(
      queryParameters: {
        'limit': '$limit',
        if (classCode != null) 'classCode': classCode,
        if (subjectCode != null) 'subjectCode': subjectCode,
        if (slot != null) 'slot': '$slot',
      },
    ).query;
    final payload = await _sendJson('GET', '/api/sessions?$query', null);
    final sessions = payload['sessions'];
    if (sessions is! List) return [];
    return sessions
        .whereType<Map>()
        .map((session) => Map<String, dynamic>.from(session))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getClassRoster(String classCode) async {
    final payload = await _sendJson(
      'GET',
      '/api/rosters/${Uri.encodeComponent(classCode)}',
      null,
    );
    final students = payload['students'];
    if (students is! List) return [];
    return students
        .whereType<Map>()
        .map((student) => Map<String, dynamic>.from(student))
        .toList();
  }

  Future<Map<String, dynamic>> syncClassRoster(
    String classCode,
    List<Student> students, {
    String? sessionId,
  }) async {
    return _sendJson('PUT', '/api/rosters/${Uri.encodeComponent(classCode)}', {
      'sessionId': sessionId,
      'actor': 'Giảng viên',
      'students': students
          .map(
            (student) => {
              'rollNo': student.rollNo,
              'fullName': student.fullName,
              'email': student.email,
            },
          )
          .toList(),
    });
  }

  Future<Map<String, dynamic>> updateAttendance(
    String sessionId,
    String rollNo,
    AttendanceStatus status, {
    String reason = 'Giảng viên cập nhật từ dashboard',
    AttendanceStatus? expectedStatus,
  }) async {
    return _sendJson(
      'PATCH',
      '/api/sessions/${Uri.encodeComponent(sessionId)}/attendance/${Uri.encodeComponent(rollNo)}',
      {
        'status': status.toLabel(),
        'actor': 'Giảng viên',
        'reason': reason,
        if (expectedStatus != null) 'expectedStatus': expectedStatus.toLabel(),
      },
    );
  }

  Future<List<Map<String, dynamic>>> getAuditLogs(String sessionId) async {
    final payload = await _sendJson(
      'GET',
      '/api/sessions/${Uri.encodeComponent(sessionId)}/audit',
      null,
    );
    final logs = payload['logs'];
    if (logs is! List) return [];
    return logs
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> releaseDeviceBinding(
    String sessionId,
    int bindingId,
    String reason,
  ) async {
    return _sendJson(
      'POST',
      '/api/sessions/${Uri.encodeComponent(sessionId)}/devices/$bindingId/release',
      {'actor': 'Giảng viên', 'reason': reason},
    );
  }

  Future<Map<String, dynamic>> _sendJson(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) async {
    final uri = Uri.parse('$baseUrl$path');
    late http.Response response;
    final headers = {
      'Content-Type': 'application/json',
      if (_teacherToken.isNotEmpty) 'X-Attendance-Teacher-Token': _teacherToken,
    };

    switch (method) {
      case 'POST':
        response = await http.post(
          uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        );
        break;
      case 'PATCH':
        response = await http.patch(
          uri,
          headers: headers,
          body: jsonEncode(body),
        );
        break;
      case 'PUT':
        response = await http.put(
          uri,
          headers: headers,
          body: jsonEncode(body),
        );
        break;
      default:
        response = await http.get(uri, headers: headers);
    }

    final decoded = response.bodyBytes.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(utf8.decode(response.bodyBytes));
    final payload = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AttendanceApiException(
        payload['message']?.toString() ??
            'API trả về lỗi ${response.statusCode}.',
        response.statusCode,
      );
    }

    return payload;
  }
}

class AttendanceApiException implements Exception {
  final String message;
  final int statusCode;

  const AttendanceApiException(this.message, this.statusCode);

  @override
  String toString() => message;
}
