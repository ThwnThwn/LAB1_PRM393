import 'student_portal_url_service_stub.dart'
    if (dart.library.io) 'student_portal_url_service_io.dart'
    as platform;
import 'runtime_environment.dart';

class StudentPortalUrlService {
  static const String _configuredServerUrl = String.fromEnvironment(
    'ATTENDANCE_SERVER_URL',
    defaultValue: '',
  );

  static String get _effectiveServerUrl {
    final runtimeUrl = readRuntimeEnvironment('ATTENDANCE_SERVER_URL');
    return runtimeUrl.isNotEmpty ? runtimeUrl : _configuredServerUrl;
  }

  static String get fallbackUrl {
    if (_effectiveServerUrl.isNotEmpty) {
      return '${_withoutTrailingSlash(_effectiveServerUrl)}/student/';
    }

    if (Uri.base.scheme == 'http' || Uri.base.scheme == 'https') {
      return '${Uri.base.origin}/student/';
    }

    return 'http://localhost:8080/student/';
  }

  static Future<String> resolve() async {
    if (_effectiveServerUrl.isNotEmpty ||
        Uri.base.scheme == 'http' ||
        Uri.base.scheme == 'https') {
      return fallbackUrl;
    }

    final lanAddress = await platform.findLanIpv4Address();
    if (lanAddress == null || lanAddress.isEmpty) {
      return fallbackUrl;
    }

    return 'http://$lanAddress:8080/student/';
  }

  static String buildSessionUrl(String portalUrl, {required String sessionId}) {
    final uri = Uri.parse(portalUrl);
    return uri
        .replace(
          queryParameters: {...uri.queryParameters, 'session': sessionId},
        )
        .toString();
  }

  static String _withoutTrailingSlash(String value) =>
      value.replaceAll(RegExp(r'/$'), '');
}
