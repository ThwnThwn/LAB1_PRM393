class AttendanceLiveService {
  Future<void> connect({
    required String baseUrl,
    required String sessionId,
    required void Function(String eventName) onEvent,
  }) async {}

  Future<void> disconnect() async {}
}
