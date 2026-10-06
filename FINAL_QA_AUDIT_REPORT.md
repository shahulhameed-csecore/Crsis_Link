# FINAL QA AUDIT REPORT

## 1. The Regression Check
- **SQL Injection**: SECURE. Verified that `unsafeQuery` in `sos_endpoint.dart` strictly uses `QueryParameters.positional([$1, $2])` and that no direct string interpolation remains.
- **P2P Overflow**: SECURE. Verified that `offline_mesh_service.dart` iterates through unsynced alerts and strictly drops individual payloads if they exceed the 32,768-byte limit.
- **Canvas Performance**: SECURE. Verified that `disaster_radar_view.dart` completely isolates the Haversine trigonometric math and `TextPainter` instantiations in the cached `_recalculatePinProjections()` method, leaving a pure, lightweight 60FPS `paint()` loop.

## 2. The Secondary Edge-Case Sweep
While the primary vulnerabilities are successfully sealed, the secondary sweep caught three latent edge cases that must be patched for absolute zero-regression stability:

Severity: Medium
Location: lib/core/services/network_sync_manager.dart (uploadPendingAlerts)
The Bug: If the Serverpod backend returns a 500 Internal Server Error or 503 Service Unavailable, the exception is caught but falls through to the final `else` block instead of breaking. The loop stubbornly continues trying to upload all remaining alerts, which causes the client to rapidly hammer an already failing server, worsening the outage.
The Fix: 
```dart
          } else if (errorStr.contains('Rate limit') || errorStr.contains('500') || errorStr.contains('503')) {
            debugPrint('Server unavailable or rate limited. Retrying after backoff.');
            break;
          } else {
            debugPrint('Failed to sync alert ${alert.id}: $e');
          }
```

Severity: Medium
Location: lib/core/services/offline_cache_manager.dart (saveAlert)
The Bug: If the device has 0 bytes of storage left, `await _box.put(alert.id, alert);` throws a `FileSystemException`. Because `saveAlert()` lacks a localized `try/catch` block, this exception bubbles up. The mesh listener (`_handleIncomingPayload`) catches it, preventing a hard UI crash—but it forces the listener loop to prematurely abort. This drops all remaining valid alerts in that received mesh packet.
The Fix: 
```dart
  static Future<void> saveAlert(LocalSosAlert alert) async {
    try {
      if (_box.length >= 1000) {
        final syncedKeys = _box.keys.where((k) {
          final item = _box.get(k);
          return item != null && item.isSynced;
        }).toList();
        if (syncedKeys.isNotEmpty) {
          await _box.delete(syncedKeys.first);
        } else {
          await _box.delete(_box.keys.first);
        }
      }
      await _box.put(alert.id, alert);
    } catch (e) {
      debugPrint('Storage Exhaustion or Hive Error: $e');
    }
  }
```

Severity: High
Location: lib/core/services/offline_mesh_service.dart (startMesh)
The Bug: While `startMesh()` contains a master `try/catch` block, the asynchronous listener callbacks (like `onEndpointFound` and `onConnectionInitiated`) do not. If the physical Bluetooth antenna suffers a hardware fault and immediately rejects the connection, `Nearby().requestConnection(...)` throws an asynchronous exception that bypasses the master catch block, crashing the Dart event loop and permanently terminating the background mesh.
The Fix: 
```dart
        onEndpointFound: (id, name, serviceId) async {
          try {
            await Nearby().requestConnection(
              shortId,
              id,
              onConnectionInitiated: (id, info) async {
                try {
                  await Nearby().acceptConnection(id, onPayLoadRecieved: (endpointId, payload) {
                    _handleIncomingPayload(endpointId, payload);
                  });
                } catch (e) {
                  debugPrint('Hardware fault during accept: $e');
                }
              },
              onConnectionResult: (id, status) {
                if (status == Status.CONNECTED) {
                  if (!_connectedEndpoints.contains(id)) _connectedEndpoints.add(id);
                  _syncLocalDatabaseWithPeer(id);
                } else {
                  _connectedEndpoints.remove(id);
                }
              },
              onDisconnected: (id) {
                _connectedEndpoints.remove(id);
              },
            );
          } catch (e) {
            debugPrint('Hardware fault during request: $e');
          }
        },
```
