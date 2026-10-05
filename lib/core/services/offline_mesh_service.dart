import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import '../models/local_sos_alert.dart';
import 'offline_cache_manager.dart';
import '../auth/auth_manager.dart';

class OfflineMeshService {
  static final OfflineMeshService _instance = OfflineMeshService._internal();
  factory OfflineMeshService() => _instance;
  OfflineMeshService._internal();

  final Strategy _strategy = Strategy.P2P_CLUSTER;
  final String _serviceId = "com.crsis_link.mesh";
  final List<String> _connectedEndpoints = [];
  bool _isOfflineModeEnabled = false;
  
  bool get isOfflineModeEnabled => _isOfflineModeEnabled;

  void toggleOfflineMode(bool enable) {
    _isOfflineModeEnabled = enable;
    if (enable) {
      startMesh();
    } else {
      Nearby().stopAdvertising();
      Nearby().stopDiscovery();
      Nearby().stopAllEndpoints();
      _connectedEndpoints.clear();
    }
  }

  Future<void> startMesh() async {
    try {
      await Nearby().startAdvertising(
        AuthManager.displayName,
        _strategy,
        onConnectionInitiated: (id, info) async {
          await Nearby().acceptConnection(id, onPayLoadRecieved: (endpointId, payload) {
            _handleIncomingPayload(payload, endpointId);
          });
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
        serviceId: _serviceId,
      );

      await Nearby().startDiscovery(
        AuthManager.displayName,
        _strategy,
        onEndpointFound: (id, name, serviceId) async {
          await Nearby().requestConnection(
            AuthManager.displayName,
            id,
            onConnectionInitiated: (id, info) async {
              await Nearby().acceptConnection(id, onPayLoadRecieved: (endpointId, payload) {
                _handleIncomingPayload(payload, endpointId);
              });
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
        },
        onEndpointLost: (id) {},
        serviceId: _serviceId,
      );
    } catch (e) {
      debugPrint("Mesh start failed: $e");
    }
  }

  Future<void> _syncLocalDatabaseWithPeer(String endpointId) async {
    final unsynced = OfflineCacheManager.getUnsyncedAlerts();
    if (unsynced.isEmpty) return;

    final jsonList = unsynced.map((a) => a.toJson()).toList();
    final payloadStr = jsonEncode(jsonList);
    
    await Nearby().sendBytesPayload(endpointId, Uint8List.fromList(utf8.encode(payloadStr)));
  }

  Future<void> _handleIncomingPayload(Payload payload, String endpointId) async {
    if (payload.type == PayloadType.BYTES && payload.bytes != null) {
      final str = utf8.decode(payload.bytes!);
      try {
        final List<dynamic> dataList = jsonDecode(str);
        bool hasNewData = false;

        for (var item in dataList) {
          final alert = LocalSosAlert.fromJson(item as Map<String, dynamic>);
          
          // STRICT MESH VALIDATION (Threat Vector 2)
          if (alert.lat < -90 || alert.lat > 90 || alert.lng < -180 || alert.lng > 180) {
            continue; // Invalid coordinates, drop payload
          }
          if (alert.message.length > 500) {
            alert.message = alert.message.substring(0, 500); // Truncate DoS payloads
          }
          if (alert.victimPhone.length > 20) {
            alert.victimPhone = alert.victimPhone.substring(0, 20);
          }

          if (!OfflineCacheManager.alertExists(alert.id)) {
            // New alert hopping through
            alert.isSynced = false;
            await OfflineCacheManager.saveAlert(alert);
            hasNewData = true;
          }
        }

        // If we received new data, relay the updated local queue to peers
        if (hasNewData) {
          for (final peerId in _connectedEndpoints) {
            // Skip the peer that just sent us this data to prevent echo loops
            if (peerId != endpointId) {
              // Re-syncs only the alerts marked as `isSynced = false` in our Hive DB
              await _syncLocalDatabaseWithPeer(peerId);
            }
          }
        }
      } catch (e) {
        debugPrint('Error decoding mesh payload: $e');
      }
    }
  }
}
