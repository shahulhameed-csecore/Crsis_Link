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

  bool _isToggling = false;

  Future<void> toggleOfflineMode(bool enable) async {
    if (_isToggling) return; // Drop panicked inputs
    _isToggling = true;
    
    try {
      _isOfflineModeEnabled = enable;
      if (enable) {
        await startMesh();
      } else {
        await Nearby().stopAdvertising();
        await Nearby().stopDiscovery();
        Nearby().stopAllEndpoints();
        _connectedEndpoints.clear();
      }
    } finally {
      _isToggling = false; // Release the lock
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
    
    try {
      await Nearby().sendBytesPayload(endpointId, Uint8List.fromList(utf8.encode(payloadStr)));
    } catch (e) {
      debugPrint('Failed to sync mesh database with peer $endpointId: $e');
    }
  }

  Future<void> _handleIncomingPayload(Payload payload, String endpointId) async {
    if (payload.type == PayloadType.BYTES && payload.bytes != null) {
      final str = utf8.decode(payload.bytes!);
      try {
        final List<dynamic> dataList = jsonDecode(str);
        bool hasNewData = false;

        for (var item in dataList) {
          final Map<String, dynamic> jsonMap = Map<String, dynamic>.from(item as Map);
          
          // Force safe conversion of numbers to double to prevent TypeError crashes
          if (jsonMap['lat'] is num) jsonMap['lat'] = (jsonMap['lat'] as num).toDouble();
          if (jsonMap['lng'] is num) jsonMap['lng'] = (jsonMap['lng'] as num).toDouble();
          
          // STRICT MESH VALIDATION BEFORE IMMUTABLE INSTANTIATION
          if (jsonMap['lat'] < -90 || jsonMap['lat'] > 90 || jsonMap['lng'] < -180 || jsonMap['lng'] > 180) {
            continue; // Drop impossible GPS coordinates entirely
          }
          
          // Truncate malicious string payloads
          if (jsonMap['message'] != null && jsonMap['message'].toString().length > 500) {
            jsonMap['message'] = jsonMap['message'].toString().substring(0, 500);
          }
          if (jsonMap['victimPhone'] != null && jsonMap['victimPhone'].toString().length > 20) {
            jsonMap['victimPhone'] = jsonMap['victimPhone'].toString().substring(0, 20);
          }
          
          final alert = LocalSosAlert.fromJson(jsonMap);

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
              try {
                // Re-syncs only the alerts marked as `isSynced = false` in our Hive DB
                await _syncLocalDatabaseWithPeer(peerId);
              } catch (e) {
                debugPrint('Failed to relay to peer $peerId: $e');
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Error decoding mesh payload: $e');
      }
    }
  }
}
