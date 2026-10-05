import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:crsis_link_client/crsis_link_client.dart';
import '../models/local_sos_alert.dart';
import 'offline_cache_manager.dart';
import '../auth/auth_manager.dart';
import '../state/map_pins_manager.dart';

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
    if (_isToggling) return;
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
      _isToggling = false;
    }
  }

  Future<bool> requestPermissions() async {
    final Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ].request();

    bool allGranted = true;
    statuses.forEach((permission, status) {
      if (!status.isGranted) {
        debugPrint('Mesh Permission missing: $permission');
        allGranted = false;
      }
    });

    return allGranted;
  }

  Future<void> startMesh() async {
    try {
      // 1. Aggressive Permission Requesting (Android 12+)
      bool hasPermissions = await requestPermissions();
    // We don't abort on hasPermissions because Android versions will reject either legacy or modern permissions
    // We just request them and let the OS handle it, then try starting the mesh.

      String shortId = AuthManager.deviceId;
      if (shortId.length > 31) shortId = shortId.substring(0, 31);
      
      // 2. The P2P_CLUSTER Strategy
      await Nearby().startAdvertising(
        shortId,
        _strategy,
        onConnectionInitiated: (id, info) async {
          // 3. The Two-Way Handshake (Auto-Accept)
          await Nearby().acceptConnection(id, onPayLoadRecieved: (endpointId, payload) {
            _handleIncomingPayload(endpointId, payload);
          });
        },
        onConnectionResult: (id, status) {
          // 4. Triggering the Payload Transfer
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
        shortId,
        _strategy,
        onEndpointFound: (id, name, serviceId) async {
          await Nearby().requestConnection(
            shortId,
            id,
            onConnectionInitiated: (id, info) async {
              // 3. The Two-Way Handshake Auto-Accept for Discoverer
              await Nearby().acceptConnection(id, onPayLoadRecieved: (endpointId, payload) {
                _handleIncomingPayload(endpointId, payload);
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
      final bytes = Uint8List.fromList(utf8.encode(payloadStr));
      await Nearby().sendBytesPayload(endpointId, bytes);
    } catch (e) {
      debugPrint('Failed to sync mesh database with peer $endpointId: $e');
    }
  }

  Future<void> broadcastNewAlert(LocalSosAlert alert) async {
    final payloadStr = jsonEncode([alert.toJson()]);
    final bytes = Uint8List.fromList(utf8.encode(payloadStr));
    
    for (final peerId in _connectedEndpoints) {
      try {
        await Nearby().sendBytesPayload(peerId, bytes);
      } catch (e) {
        debugPrint('Failed to broadcast alert to peer $peerId: $e');
      }
    }
  }

  Future<void> broadcastNukeCommand() async {
    final payloadStr = jsonEncode({"command": "NUKE_MESH"});
    final bytes = Uint8List.fromList(utf8.encode(payloadStr));
    
    for (final peerId in _connectedEndpoints) {
      try {
        await Nearby().sendBytesPayload(peerId, bytes);
      } catch (e) {
        debugPrint('Failed to broadcast nuke command to peer $peerId: $e');
      }
    }
  }

  // 5. Receiving and Processing
  Future<void> _handleIncomingPayload(String endpointId, Payload payload) async {
    if (payload.type == PayloadType.BYTES && payload.bytes != null) {
      try {
        final str = utf8.decode(payload.bytes!);
        final dynamic decodedData = jsonDecode(str);

        if (decodedData is Map && decodedData['command'] == 'NUKE_MESH') {
          debugPrint('Nuke Command Received! Wiping local mesh database.');
          await OfflineCacheManager.clearEntireCache();
          MapPinsManager().setPins([]);
          return;
        }

        if (decodedData is! List) return;
        
        final List<dynamic> dataList = decodedData;
        bool hasNewData = false;

        for (var item in dataList) {
          final Map<String, dynamic> jsonMap = Map<String, dynamic>.from(item as Map);
          
          if (jsonMap['lat'] is num) jsonMap['lat'] = (jsonMap['lat'] as num).toDouble();
          if (jsonMap['lng'] is num) jsonMap['lng'] = (jsonMap['lng'] as num).toDouble();
          
          if (jsonMap['lat'] < -90 || jsonMap['lat'] > 90 || jsonMap['lng'] < -180 || jsonMap['lng'] > 180) {
            continue; // Drop impossible coordinates
          }
          
          if (jsonMap['message'] != null && jsonMap['message'].toString().length > 500) {
            jsonMap['message'] = jsonMap['message'].toString().substring(0, 500);
          }
          if (jsonMap['victimPhone'] != null && jsonMap['victimPhone'].toString().length > 20) {
            jsonMap['victimPhone'] = jsonMap['victimPhone'].toString().substring(0, 20);
          }
          
          final alert = LocalSosAlert.fromJson(jsonMap);

          if (!OfflineCacheManager.alertExists(alert.id)) {
            alert.isSynced = false;
            await OfflineCacheManager.saveAlert(alert);
            hasNewData = true;

            // Map LocalSosAlert to SosAlert and push to MapPinsManager
            final sosAlert = SosAlert(
              id: int.tryParse(alert.id.replaceAll(RegExp(r'[^0-9]'), '')) ?? (DateTime.now().millisecondsSinceEpoch % 100000),
              latitude: alert.lat,
              longitude: alert.lng,
              message: alert.message,
              status: 'OPEN',
              timestamp: DateTime.fromMillisecondsSinceEpoch(alert.timestamp),
              victimPhone: alert.victimPhone,
              deviceId: alert.originalDeviceId,
              senderName: alert.originalSenderName,
              isActive: true,
            );
            
            MapPinsManager().addOrUpdatePin(sosAlert);
          }
        }

        if (hasNewData) {
          for (final peerId in _connectedEndpoints) {
            if (peerId != endpointId) {
              try {
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
