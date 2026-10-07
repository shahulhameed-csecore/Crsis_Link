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
      if (pendingAlerts.isEmpty) return;

      final stopwatch = Stopwatch()..start();
      const int batchSize = 5;

      for (int i = 0; i < pendingAlerts.length; i += batchSize) {
        final chunk = pendingAlerts.sublist(
          i, 
          i + batchSize > pendingAlerts.length ? pendingAlerts.length : i + batchSize
        );
        
        await Future.wait(chunk.map((alert) async {
          try {
            await AuthManager.client.sos.broadcastSos(
              alert.originalDeviceId,
              alert.originalSenderName,
              alert.lat,
              alert.lng,
              alert.message,
              null, // audioUrl
              alert.victimPhone, 
              null, // photoBase64
              alert.approximateLocationText, 
            );
            
            await OfflineCacheManager.markAsSynced(alert.id);
            debugPrint('[BENCHMARK] Synced alert ${alert.id}');
          } catch (e) {
            final errorStr = e.toString();
            if (errorStr.contains('duplicate') || errorStr.contains('already exists')) {
              alert.isSynced = true;
              await alert.save(); 
              await OfflineCacheManager.markAsSynced(alert.id);
            } else if (errorStr.contains('Rate limit') || errorStr.contains('500') || errorStr.contains('503')) {
              debugPrint('[BENCHMARK] Rate limit hit on ${alert.id}, skipping for backoff.');
            } else {
              debugPrint('[BENCHMARK] Failed to sync alert ${alert.id}: $e');
            }
          }
        }));
        
        // Minor backoff between batches to prevent overwhelming the Serverpod instances
        await Future.delayed(const Duration(milliseconds: 250));
      }
      
      stopwatch.stop();
      debugPrint('[BENCHMARK] Uploaded ${pendingAlerts.length} backlog records in ${stopwatch.elapsedMilliseconds}ms via Batch Sync Worker');
    } finally {
      _isSyncing = false;
    }
  }
}
