import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../auth/auth_manager.dart';

class UpdateInfo {
  final bool isUpdateRequired;
  final String currentVersion;
  final String latestVersion;
  final String apkDownloadUrl;

  UpdateInfo({
    required this.isUpdateRequired,
    required this.currentVersion,
    required this.latestVersion,
    required this.apkDownloadUrl,
  });
}

class UpdateService {
  /// Checks whether an in-app update is required by comparing installed version
  /// with the latest version published by the Serverpod backend config endpoint.
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final config = await AuthManager.client.config.getAppUpdateInfo().timeout(
        const Duration(seconds: 8),
      );

      final latestVersion = config['latestVersion'] ?? currentVersion;
      final apkDownloadUrl = config['apkDownloadUrl'] ?? '';

      final isUpdateRequired = isVersionHigher(latestVersion, currentVersion);

      return UpdateInfo(
        isUpdateRequired: isUpdateRequired,
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        apkDownloadUrl: apkDownloadUrl,
      );
    } catch (e) {
      debugPrint('[UpdateService] Failed to check for app update: $e');
      return null;
    }
  }

  /// Compares semantic versions (e.g. "1.0.1" vs "1.0.0").
  /// Returns true if serverVersion is strictly higher than currentVersion.
  static bool isVersionHigher(String serverVersion, String currentVersion) {
    try {
      final cleanServer = serverVersion.split('+').first.split('-').first.trim();
      final cleanCurrent = currentVersion.split('+').first.split('-').first.trim();

      final serverParts = cleanServer.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final currentParts = cleanCurrent.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      final maxLength = serverParts.length > currentParts.length ? serverParts.length : currentParts.length;

      for (int i = 0; i < maxLength; i++) {
        final s = i < serverParts.length ? serverParts[i] : 0;
        final c = i < currentParts.length ? currentParts[i] : 0;
        if (s > c) return true;
        if (s < c) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
