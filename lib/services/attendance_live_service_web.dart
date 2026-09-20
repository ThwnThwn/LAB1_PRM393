// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html';

class AttendanceLiveService {
  WebSocket? _socket;
  StreamSubscription<MessageEvent>? _messageSubscription;

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

    final socket = WebSocket(socketUri.toString());
    _socket = socket;
    await socket.onOpen.first;
    var handshakeComplete = false;

    _messageSubscription = socket.onMessage.listen((event) {
      for (final frame in event.data.toString().split('\u001e')) {
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

    socket.send('${jsonEncode({'protocol': 'json', 'version': 1})}\u001e');
  }

  Future<void> disconnect() async {
    await _messageSubscription?.cancel();
    _messageSubscription = null;
    _socket?.close();
    _socket = null;
  }

  Future<String> _negotiate(String baseUrl) async {
    final response = await HttpRequest.request(
      '$baseUrl/hubs/attendance/negotiate?negotiateVersion=1',
      method: 'POST',
      requestHeaders: {'Content-Type': 'application/json'},
      sendData: '{}',
    );
    final payload =
        jsonDecode(response.responseText ?? '{}') as Map<String, dynamic>;
    return payload['connectionToken'].toString();
  }

  void _joinSession(String sessionId) {
    _socket?.send(
      '${jsonEncode({
        'type': 1,
        'invocationId': 'join-session',
        'target': 'JoinSession',
        'arguments': [sessionId],
      })}\u001e',
    );
  }
}
