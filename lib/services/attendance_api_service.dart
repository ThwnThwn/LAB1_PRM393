import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/attendance_session.dart';
import '../models/student.dart';

class AttendanceApiService {
  static const String _configuredServerUrl = String.fromEnvironment(
    'ATTENDANCE_SERVER_URL',
    defaultValue: '',
  );

  String get baseUrl {
    if (_configuredServerUrl.isNotEmpty) {
      return _configuredServerUrl.replaceAll(RegExp(r'/$'), '');
    }

    if (Uri.base.scheme == 'http' || Uri.base.scheme == 'https') {
      return Uri.base.origin;
    }

    return 'http://localhost:8080';
  }

  String exportUrl(String sessionId) =>
      '$baseUrl/api/sessions/${Uri.encodeComponent(sessionId)}/export.csv';

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

  Future<Map<String, dynamic>> updateAttendance(
    String sessionId,
    String rollNo,
    AttendanceStatus status, {
    String reason = 'Giảng viên cập nhật từ dashboard',
  }) async {
    return _sendJson(
      'PATCH',
      '/api/sessions/${Uri.encodeComponent(sessionId)}/attendance/${Uri.encodeComponent(rollNo)}',
      {'status': status.toLabel(), 'actor': 'Giảng viên', 'reason': reason},
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

  Future<Map<String, dynamic>> _sendJson(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) async {
    final uri = Uri.parse('$baseUrl$path');
    late http.Response response;
    final headers = {'Content-Type': 'application/json'};

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
