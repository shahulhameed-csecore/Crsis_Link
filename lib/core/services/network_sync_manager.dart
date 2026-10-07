import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'offline_cache_manager.dart';
import '../auth/auth_manager.dart';
import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:geolocator/geolocator.dart';
import '../../core/state/alerts_manager.dart';
import '../../core/state/map_pins_manager.dart';

enum SyncState { offline, connecting, onlineSyncing, idleOnline }

class NetworkSyncManager {
  static final NetworkSyncManager _instance = NetworkSyncManager._internal();
  factory NetworkSyncManager() => _instance;
  NetworkSyncManager._internal();

  bool _isSyncing = false;
  bool _isRetryScheduled = false;
  int _retryBackoffSeconds = 2;
  
  final ValueNotifier<SyncState> state = ValueNotifier(SyncState.offline);

  void init() {
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.contains(ConnectivityResult.wifi) || results.contains(ConnectivityResult.mobile)) {
        _verifyActualConnection();
      } else {
        state.value = SyncState.offline;
      }
    });
    
    // Cleanup old alerts every 12 hours locally (Threshold: 72 hours)
    Timer.periodic(const Duration(hours: 12), (_) {
      OfflineCacheManager.clearExpiredAlerts(const Duration(hours: 72));
    });
  }

  Future<void> _verifyActualConnection() async {
    state.value = SyncState.connecting;
    try {
      // Lightweight Ping/DNS check
      final result = await InternetAddress.lookup('google.com');
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        uploadPendingAlerts();
      } else {
        state.value = SyncState.offline;
      }
    } catch (_) {
      state.value = SyncState.offline;
    }
  }

  Future<void> uploadPendingAlerts() async {
    if (_isSyncing || _isRetryScheduled) return;
    _isSyncing = true;
    state.value = SyncState.onlineSyncing;

    try {
      final pendingAlerts = OfflineCacheManager.getUnsyncedAlerts();
      
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
              null, // photoUrl
              alert.approximateLocationText,
              alert.id, // clientAlertId
            );
            
            await OfflineCacheManager.markAsSynced(alert.id);
            debugPrint('[BENCHMARK] Synced alert ${alert.id}');
          } catch (e) {
            final errorStr = e.toString();
            if (errorStr.contains('duplicate') || errorStr.contains('already exists')) {
               await OfflineCacheManager.markAsSynced(alert.id);
            } else if (errorStr.contains('Rate limit') || errorStr.contains('500') || errorStr.contains('503')) {
              debugPrint('[BENCHMARK] Rate limit/Server Error hit on ${alert.id}, aborting batch for backoff.');
              throw Exception('Backoff trigger'); 
            } else {
              debugPrint('[BENCHMARK] Failed to sync alert ${alert.id}: $e');
              throw Exception('Network trigger');
            }
          }
        }));
        
        await Future.delayed(const Duration(milliseconds: 250));
      }
      
      // Bi-Directional State Reconciliation:
      // Fetch active global SOS alerts broadcast from Serverpod while offline
      await _fetchGlobalAlerts();
      
      stopwatch.stop();
      debugPrint('[BENCHMARK] Uploaded ${pendingAlerts.length} backlog records in ${stopwatch.elapsedMilliseconds}ms');
      _retryBackoffSeconds = 2; // Reset on success
      state.value = SyncState.idleOnline;
    } catch (e) {
      _retryBackoffSeconds = min(60, _retryBackoffSeconds * 2);
      final jitter = Random().nextInt(1000); 
      debugPrint('[SYNC] Sync aborted. Retrying in $_retryBackoffSeconds seconds (+$jitter ms jitter)...');
      
      _isRetryScheduled = true;
      Future.delayed(Duration(seconds: _retryBackoffSeconds, milliseconds: jitter), () {
        _isRetryScheduled = false;
        if (state.value != SyncState.offline) {
           uploadPendingAlerts();
        }
      });
    } finally {
      _isSyncing = false;
    }
  }
  
  Future<void> _fetchGlobalAlerts() async {
    try {
      Position? position;
      try {
        position = await Geolocator.getLastKnownPosition();
      } catch (_) {}
      
      if (position != null) {
        final alerts = await AuthManager.client.sos.getActiveAlerts(position.latitude, position.longitude);
        MapPinsManager().setPins(alerts);
        
        // Merge into AlertsManager ledger
        for (var alert in alerts) {
           if (!AlertsManager().notifications.any((a) => a.clientAlertId == alert.clientAlertId)) {
               AlertsManager().addSosAlert(alert);
           }
        }
      }
    } catch (e) {
      debugPrint('Reconciliation fetch failed: $e');
    }
  }
}
