import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../main.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:crsis_link_client/crsis_link_client.dart';
import '../models/local_sos_alert.dart';
import 'offline_cache_manager.dart';
import '../auth/auth_manager.dart';
import '../state/map_pins_manager.dart';
import '../state/alerts_manager.dart';
import 'dart:async';
import 'package:flutter/services.dart';

class OfflineMeshService {
  static final OfflineMeshService _instance = OfflineMeshService._internal();
  factory OfflineMeshService() => _instance;
  OfflineMeshService._internal();

  final Strategy _strategy = Strategy.P2P_CLUSTER;
  final String _serviceId = "com.crsis_link.mesh";
  final List<String> _connectedEndpoints = [];
  bool _isOfflineModeEnabled = false;
  Timer? _telemetryTimer;
  
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
      if (enable) {
        bool success = await startMesh();
        _isOfflineModeEnabled = success;
      } else {
        await Nearby().stopAdvertising();
        await Nearby().stopDiscovery();
        Nearby().stopAllEndpoints();
        _connectedEndpoints.clear();
        _stopTelemetryBroadcast();
        _isOfflineModeEnabled = false;
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

    bool hasEssential = await Permission.location.isGranted;
    statuses.forEach((permission, status) {
      if (!status.isGranted) {
        debugPrint('[P2P_DEBUG] Permission missing: $permission');
      }
    });

    return hasEssential;
  }

  Future<bool> startMesh() async {
    try {
      // 1. Aggressive Permission Requesting (Android 12+)
      bool hasPermissions = await requestPermissions();
      if (!hasPermissions) {
        _showDebugToast('Mesh Start Failed: Missing Location Permission');
        return false;
      }

      bool locationEnabled = await Geolocator.isLocationServiceEnabled();
      if (!locationEnabled) {
        _showDebugToast('Mesh Start Failed: Location Services OFF (Turn on GPS)');
        return false;
      }

      String shortId = AuthManager.deviceId;
      if (shortId.length > 31) shortId = shortId.substring(0, 31);
      
      _showDebugToast('Starting Mesh Network...');

      // 2. The P2P_CLUSTER Strategy
      await Nearby().startAdvertising(
        shortId,
        _strategy,
        onConnectionInitiated: (id, info) async {
          _showDebugToast('Connection Initiated with $id');
          debugPrint('[P2P_DEBUG] startAdvertising: Connection Initiated with $id (name: ${info.endpointName})');
          // 3. The Two-Way Handshake (Auto-Accept)
          try {
            await Nearby().acceptConnection(
              id, 
              onPayLoadRecieved: (endpointId, payload) {
                _handleIncomingPayload(endpointId, payload);
              },
              onPayloadTransferUpdate: (endpointId, payloadTransferUpdate) {
                debugPrint('[P2P_DEBUG] Transfer from $endpointId: status ${payloadTransferUpdate.status}, bytes: ${payloadTransferUpdate.bytesTransferred}/${payloadTransferUpdate.totalBytes}');
              }
            );
          } catch (e) {
            debugPrint('[P2P_DEBUG] Hardware fault or security rejection during accept: $e');
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
          debugPrint('[P2P_DEBUG] Discovered peer $name ($id)');
          // Prevent mutual request collision: only one device initiates connection
          if (shortId.compareTo(name) >= 0) {
            debugPrint('[P2P_DEBUG] Yielding connection request to peer $name to avoid collision');
            return;
          }
          
          if (_connectedEndpoints.contains(id)) return;
          
          try {
            _showDebugToast('Requesting connection to $name');
            debugPrint('[P2P_DEBUG] Requesting connection to $name ($id)');
            await Nearby().requestConnection(
              shortId,
              id,
              onConnectionInitiated: (id, info) async {
                debugPrint('[P2P_DEBUG] requestConnection: Connection Initiated with $id');
                try {
                  await Nearby().acceptConnection(
                    id, 
                    onPayLoadRecieved: (endpointId, payload) {
                      _handleIncomingPayload(endpointId, payload);
                    },
                    onPayloadTransferUpdate: (endpointId, payloadTransferUpdate) {
                      debugPrint('[P2P_DEBUG] Transfer from $endpointId: status ${payloadTransferUpdate.status}, bytes: ${payloadTransferUpdate.bytesTransferred}/${payloadTransferUpdate.totalBytes}');
                    }
                  );
                } catch (e) {
                  debugPrint('[P2P_DEBUG] Hardware fault during accept: $e');
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
        onEndpointLost: (id) {
          debugPrint('[P2P_DEBUG] Endpoint lost: $id');
        },
        serviceId: _serviceId,
      );
      debugPrint('[P2P_DEBUG] Mesh started successfully');
      _startTelemetryBroadcast();
      return true;
    } on PlatformException catch (e) {
      _showDebugToast("Mesh hardware fault: ${e.message}");
      debugPrint("[P2P_DEBUG] Mesh platform fault: $e");
      return false;
    } catch (e) {
      _showDebugToast("Mesh start failed: $e");
      debugPrint("[P2P_DEBUG] Mesh start failed: $e");
      return false;
    }
  }

  Future<void> _syncLocalDatabaseWithPeer(String endpointId) async {
    final unsynced = OfflineCacheManager.getUnsyncedAlerts();
    if (unsynced.isEmpty) return;

    for (final alert in unsynced) {
      try {
        final payloadStr = jsonEncode([{
          "t": "SOS",
          "i": alert.id,
          "l": alert.lat,
          "g": alert.lng,
          "m": alert.message,
          "v": alert.victimPhone,
          "a": alert.approximateLocationText,
          "d": alert.originalDeviceId,
          "n": alert.originalSenderName,
          "ts": alert.timestamp
        }]);
        final bytes = Uint8List.fromList(utf8.encode(payloadStr));
        
        if (bytes.lengthInBytes <= 32768) {
          _showDebugToast('Syncing DB to $endpointId');
          await Nearby().sendBytesPayload(endpointId, bytes);
        } else {
          debugPrint('Alert payload too large, skipping sync for peer $endpointId.');
        }
      } on PlatformException catch (e) {
        debugPrint('Platform fault syncing mesh alert: $e');
      } catch (e) {
        debugPrint('Failed to sync mesh database alert with peer $endpointId: $e');
      }
    }
  }

  Future<void> broadcastNewAlert(LocalSosAlert alert) async {
    final payloadStr = jsonEncode([{
      "t": "SOS",
      "i": alert.id,
      "l": alert.lat,
      "g": alert.lng,
      "m": alert.message,
      "v": alert.victimPhone,
      "a": alert.approximateLocationText,
      "d": alert.originalDeviceId,
      "n": alert.originalSenderName,
      "ts": alert.timestamp
    }]);
    final bytes = Uint8List.fromList(utf8.encode(payloadStr));
    
    for (final peerId in _connectedEndpoints) {
      try {
        _showDebugToast('Transmitting SOS to $peerId');
        debugPrint('[P2P_DEBUG] Transmitting SOS to $peerId');
        await Nearby().sendBytesPayload(peerId, bytes);
      } on PlatformException catch (e) {
        debugPrint('[P2P_DEBUG] Platform fault broadcasting alert to $peerId: $e');
      } catch (e) {
        debugPrint('[P2P_DEBUG] Failed to broadcast alert to peer $peerId: $e');
      }
    }
  }

  void _startTelemetryBroadcast() {
    _telemetryTimer?.cancel();
    _telemetryTimer = Timer.periodic(const Duration(seconds: 20), (timer) async {
      try {
        final alerts = OfflineCacheManager.getUnsyncedAlerts();
        final ownActiveAlert = alerts.where((a) => a.originalDeviceId == AuthManager.deviceId).firstOrNull;
        if (ownActiveAlert != null && _connectedEndpoints.isNotEmpty) {
          final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
          final payloadStr = jsonEncode({
            "t": "LOC",
            "i": ownActiveAlert.id,
            "l": position.latitude,
            "g": position.longitude,
            "ts": DateTime.now().millisecondsSinceEpoch,
          });
          final bytes = Uint8List.fromList(utf8.encode(payloadStr));
          for (final peerId in _connectedEndpoints) {
            await Nearby().sendBytesPayload(peerId, bytes);
          }
        }
      } catch (e) {
        debugPrint('[P2P_DEBUG] Telemetry error: $e');
      }
    });
  }

  void _stopTelemetryBroadcast() {
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
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

        if (decodedData is Map && (decodedData['type'] == 'LOCATION_UPDATE' || decodedData['t'] == 'LOC')) {
          final String alertId = decodedData['id'] ?? decodedData['i'];
          final double lat = decodedData['lat'] ?? decodedData['l'];
          final double lng = decodedData['lng'] ?? decodedData['g'];
          final int ts = decodedData['timestamp'] ?? decodedData['ts'] ?? DateTime.now().millisecondsSinceEpoch;
          
          final existing = OfflineCacheManager.getAlert(alertId);
          if (existing != null) {
            existing.lat = lat;
            existing.lng = lng;
            existing.timestamp = ts;
            await OfflineCacheManager.saveAlert(existing);
            // Re-sync with other peers
            for (final peerId in _connectedEndpoints) {
              if (peerId != endpointId) await Nearby().sendBytesPayload(peerId, payload.bytes!);
            }
          }
          return;
        }

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
          final bool isMinified = jsonMap['t'] == 'SOS';
          
          final String? id = jsonMap['id'] ?? jsonMap['i'];
          final timestamp = jsonMap['timestamp'] ?? jsonMap['ts'];
          if (id == null || timestamp == null) continue;
          
          final double? lat = isMinified ? (jsonMap['l'] as num?)?.toDouble() : (jsonMap['lat'] as num?)?.toDouble();
          final double? lng = isMinified ? (jsonMap['g'] as num?)?.toDouble() : (jsonMap['lng'] as num?)?.toDouble();
          
          if (lat == null || lng == null || lat.isNaN || lat.isInfinite || lng.isNaN || lng.isInfinite) {
            continue;
          }
          
          final clampedLat = lat.clamp(-90.0, 90.0);
          final clampedLng = lng.clamp(-180.0, 180.0);
          
          final msg = (jsonMap['message'] ?? jsonMap['m'] ?? 'Emergency').toString();
          final String message = msg.length > 500 ? msg.substring(0, 500) : msg;
          
          final phone = (jsonMap['victimPhone'] ?? jsonMap['v'] ?? 'URGENT-NO-NUMBER').toString();
          final String victimPhone = phone.length > 20 ? phone.substring(0, 20) : phone;

          final approxLoc = jsonMap['approximateLocationText'] ?? jsonMap['a'];
          final origDevId = jsonMap['originalDeviceId'] ?? jsonMap['d'] ?? 'unknown_device';
          final origSender = jsonMap['originalSenderName'] ?? jsonMap['n'] ?? 'Unknown Sender';
          
          final alert = LocalSosAlert(
            id: id,
            lat: clampedLat,
            lng: clampedLng,
            message: message,
            victimPhone: victimPhone,
            approximateLocationText: approxLoc,
            originalDeviceId: origDevId,
            originalSenderName: origSender,
            timestamp: timestamp,
            isSynced: false,
          );

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
      } catch (e, stack) {
        debugPrint('Error decoding mesh payload: $e\n$stack');
      }
    }
  }
}
