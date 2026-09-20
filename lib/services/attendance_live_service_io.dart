import 'dart:async';
import 'dart:convert';
import 'dart:io';

class AttendanceLiveService {
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;

  Future<void> connect({
    required String baseUrl,
    required String sessionId,
    required void Function(String eventName) onEvent,
  }) async {
    await disconnect();
    final token = await _negotiate(baseUrl);
    final httpUri = Uri.parse(baseUrl);
    final socketUri = httpUri.replace(
      scheme: httpUri.scheme == 'https' ? 'wss' : 'ws',
      path: '/hubs/attendance',
      queryParameters: {'id': token},
    );

    final socket = await WebSocket.connect(socketUri.toString());
    _socket = socket;
    var handshakeComplete = false;

    _subscription = socket.listen((data) {
      for (final frame in data.toString().split('\u001e')) {
        if (frame.trim().isEmpty) continue;
        final message = jsonDecode(frame);
        if (!handshakeComplete) {
          handshakeComplete = true;
          _joinSession(sessionId);
          continue;
        }

        if (message is Map &&
            message['type'] == 1 &&
            message['target'] != null) {
          onEvent(message['target'].toString());
        }
      }
    });

    socket.add('${jsonEncode({'protocol': 'json', 'version': 1})}\u001e');
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    await _socket?.close();
    _socket = null;
  }

  Future<String> _negotiate(String baseUrl) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri.parse('$baseUrl/hubs/attendance/negotiate?negotiateVersion=1'),
      );
      request.headers.contentType = ContentType.json;
      request.write('{}');
      final response = await request.close();
      final body = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'SignalR negotiate thất bại: ${response.statusCode}',
        );
      }
      final payload = jsonDecode(body) as Map<String, dynamic>;
      return payload['connectionToken'].toString();
    } finally {
      client.close();
    }
  }

  void _joinSession(String sessionId) {
    _socket?.add(
      '${jsonEncode({
        'type': 1,
        'invocationId': 'join-session',
        'target': 'JoinSession',
        'arguments': [sessionId],
      })}\u001e',
    );
  }
}
