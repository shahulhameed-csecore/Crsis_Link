import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'offline_cache_manager.dart';
import '../auth/auth_manager.dart';

class NetworkSyncManager {
  static final NetworkSyncManager _instance = NetworkSyncManager._internal();
  factory NetworkSyncManager() => _instance;
  NetworkSyncManager._internal();

  bool _isSyncing = false;

  void init() {
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.contains(ConnectivityResult.wifi) || results.contains(ConnectivityResult.mobile)) {
        uploadPendingAlerts();
      }
    });
  }

  Future<void> uploadPendingAlerts() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final pendingAlerts = OfflineCacheManager.getUnsyncedAlerts();
      
      for (var alert in pendingAlerts) {
        try {
          // Call Serverpod backend
          await AuthManager.client.sos.broadcastSos(
            alert.originalDeviceId,
            alert.originalSenderName,
            alert.lat,
            alert.lng,
            alert.message,
            null, // audioUrl
            alert.victimPhone, // Use the proper phone from alert
            null, // photoBase64
            alert.approximateLocationText, // Use approx location
          );
          
          // If successful, mark as synced
          await OfflineCacheManager.markAsSynced(alert.id);
          debugPrint('Successfully synced alert ${alert.id} to server');
        } catch (e) {
          final errorStr = e.toString();
          // If Serverpod throws duplicate entry or rate limit, we can assume it was already synced by another peer
          if (errorStr.contains('duplicate') || errorStr.contains('already exists')) {
            alert.isSynced = true;
            await alert.save(); // explicitly save back to Hive box
            await OfflineCacheManager.markAsSynced(alert.id);
            debugPrint('Alert ${alert.id} already exists on server, marking as synced.');
          } else if (errorStr.contains('Rate limit')) {
            debugPrint('Rate limit hit while syncing alert ${alert.id}. Retrying after backoff.');
            break;
          } else {
            debugPrint('Failed to sync alert ${alert.id}: $e');
          }
        }
      }
    } finally {
      _isSyncing = false;
    }
  }
}
