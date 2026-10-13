import 'package:serverpod/serverpod.dart';

/// Endpoint providing app version configuration for in-app updates.
class ConfigEndpoint extends Endpoint {
  /// Returns the latest app version and APK download URL.
  Future<Map<String, String>> getAppUpdateInfo(Session session) async {
    return {
      'latestVersion': '1.0.1',
      'apkDownloadUrl': 'https://example.com/crisisslink.apk',
    };
  }
}
