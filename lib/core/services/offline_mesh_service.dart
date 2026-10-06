import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../main.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:crsis_link_client/crsis_link_client.dart';
import '../models/local_sos_alert.dart';
import 'offline_cache_manager.dart';
import '../auth/auth_manager.dart';
import '../state/map_pins_manager.dart';
import '../state/alerts_manager.dart';
class OfflineMeshService {
  static final OfflineMeshService _instance = OfflineMeshService._internal();
  factory OfflineMeshService() => _instance;
  OfflineMeshService._internal();

  final Strategy _strategy = Strategy.P2P_CLUSTER;
  final String _serviceId = "com.crsis_link.mesh";
  final List<String> _connectedEndpoints = [];
  bool _isOfflineModeEnabled = false;
  
  bool get isOfflineModeEnabled => _isOfflineModeEnabled;

  void _showDebugToast(String message) {
    globalMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text('Mesh: $message'),
        duration: const Duration(seconds: 3),
        backgroundColor: Colors.blueGrey,
      ),
    );
  }

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
      await requestPermissions();
      
      String shortId = AuthManager.deviceId;
      if (shortId.length > 31) shortId = shortId.substring(0, 31);
      
      // 2. The P2P_CLUSTER Strategy
      await Nearby().startAdvertising(
        shortId,
        _strategy,
        onConnectionInitiated: (id, info) async {
          _showDebugToast('Connection Initiated with $id');
          // 3. The Two-Way Handshake (Auto-Accept)
          try {
            await Nearby().acceptConnection(id, onPayLoadRecieved: (endpointId, payload) {
              _handleIncomingPayload(endpointId, payload);
            });
          } catch (e) {
            debugPrint('Hardware fault or security rejection during accept: $e');
          }
        },
        onConnectionResult: (id, status) {
          // 4. Triggering the Payload Transfer
          if (status == Status.CONNECTED) {
            _showDebugToast('Connected to $id');
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
          _showDebugToast('Discovered peer $name ($id)');
          // Prevent mutual request collision: only one device initiates connection
          if (shortId.compareTo(name) > 0) {
            debugPrint('Yielding connection request to peer $name to avoid collision');
            return;
          }
          
          if (_connectedEndpoints.contains(id)) return;
          
          try {
            _showDebugToast('Requesting connection to $name');
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
                  _showDebugToast('Connected to $id');
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

    for (final alert in unsynced) {
      try {
        final payloadStr = jsonEncode([alert.toJson()]);
        final bytes = Uint8List.fromList(utf8.encode(payloadStr));
        
        if (bytes.lengthInBytes <= 32768) {
          _showDebugToast('Syncing DB to $endpointId');
          await Nearby().sendBytesPayload(endpointId, bytes);
        } else {
          debugPrint('Alert payload too large, skipping sync for peer $endpointId.');
        }
      } catch (e) {
        debugPrint('Failed to sync mesh database alert with peer $endpointId: $e');
      }
    }
  }

  Future<void> broadcastNewAlert(LocalSosAlert alert) async {
    final payloadStr = jsonEncode([alert.toJson()]);
    final bytes = Uint8List.fromList(utf8.encode(payloadStr));
    
    for (final peerId in _connectedEndpoints) {
      try {
        _showDebugToast('Transmitting SOS to $peerId');
        await Nearby().sendBytesPayload(peerId, bytes).timeout(const Duration(seconds: 3));
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
          if (kDebugMode && decodedData['adminKey'] == AuthManager.deviceId) {
            debugPrint('Authenticated debug cache reset initiated.');
            await OfflineCacheManager.clearEntireCache();
            MapPinsManager().setPins([]);
          }
          return;
        }

        if (decodedData is! List) return;
        
        final List<dynamic> dataList = decodedData;
        bool hasNewData = false;

        for (var item in dataList) {
          if (item is! Map) continue;
          
          final Map<String, dynamic> jsonMap = Map<String, dynamic>.from(item);
          
          if (jsonMap['id'] == null || jsonMap['timestamp'] == null) {
            continue;
          }
          
          if (jsonMap['lat'] is! num || jsonMap['lng'] is! num) {
            continue;
          }
          
          double lat = (jsonMap['lat'] as num).toDouble();
          double lng = (jsonMap['lng'] as num).toDouble();
          
          if (lat.isNaN || lat.isInfinite || lng.isNaN || lng.isInfinite) {
            continue;
          }
          
          jsonMap['lat'] = lat.clamp(-90.0, 90.0);
          jsonMap['lng'] = lng.clamp(-180.0, 180.0);
          
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
            _showDebugToast('Received SOS from ${alert.originalSenderName}');
            hasNewData = true;

            final sosAlert = SosAlert(
              id: alert.id.hashCode,
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
            AlertsManager().addSosAlert(sosAlert);
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
