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
import '../state/alerts_manager.dart';
import '../state/map_pins_manager.dart';
import 'rescue_chat_session.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'p2p_crypto_service.dart';

class OfflineMeshService {
  static final OfflineMeshService _instance = OfflineMeshService._internal();
  factory OfflineMeshService() => _instance;
  OfflineMeshService._internal();

  final Strategy _strategy = Strategy.P2P_CLUSTER;
  final String _serviceId = "com.crsis_link.mesh";
  final List<String> _connectedEndpoints = [];
  bool _isOfflineModeEnabled = false;
  Timer? _telemetryTimer;
  Timer? _dutyCycleTimer;
  bool _isDiscovering = false;
  
  int _telemetrySequence = 0;
  final Set<String> _processedPacketIds = <String>{};
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
        _dutyCycleTimer?.cancel();
        _dutyCycleTimer = null;
        await Nearby().stopAdvertising();
        await Nearby().stopDiscovery();
        Nearby().stopAllEndpoints();
        _connectedEndpoints.clear();
        _stopTelemetryBroadcast();
        _isOfflineModeEnabled = false;
        _isDiscovering = false;
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

    statuses.forEach((permission, status) {
      if (!status.isGranted) {
        debugPrint('[P2P_DEBUG] Permission missing: $permission');
      }
    });

    bool isLocationGranted = statuses[Permission.location]?.isGranted ?? false;
    bool bluetoothGranted = statuses[Permission.bluetooth]?.isGranted ?? false;
    
    // For newer SDKs these are specific, for older SDKs fallback to general bluetooth.
    bool bleScanGranted = statuses[Permission.bluetoothScan]?.isGranted ?? bluetoothGranted;
    bool bleAdvGranted = statuses[Permission.bluetoothAdvertise]?.isGranted ?? bluetoothGranted;
    bool bleConnGranted = statuses[Permission.bluetoothConnect]?.isGranted ?? bluetoothGranted;

    return isLocationGranted && bleScanGranted && bleAdvGranted && bleConnGranted;
  }

  Future<bool> startMesh({bool isBackground = false}) async {
    try {
      if (!isBackground) {
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
      }

      String shortId = AuthManager.deviceId;
      if (shortId.length > 31) shortId = shortId.substring(0, 31);
      
      _showDebugToast('Starting Mesh Network...');

      // 2. The P2P_CLUSTER Strategy
      await _startAdvertisingLogic(shortId);

      _startDutyCycle(shortId);

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

  Future<void> _startAdvertisingLogic(String shortId) async {
    try {
      await Nearby().startAdvertising(
        shortId,
        _strategy,
        onConnectionInitiated: (id, info) async {
          _showDebugToast('Connection Initiated with $id');
          debugPrint('[P2P_DEBUG] startAdvertising: Connection Initiated with $id (name: ${info.endpointName})');
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
    } catch (e) {
      debugPrint('[P2P_DEBUG] Failed to start advertising: $e');
    }
  }

  void pauseDutyCycle() {
    debugPrint('[P2P_DEBUG] Pausing Mesh Duty Cycle for Compass (Keeping connections alive)');
    _dutyCycleTimer?.cancel();
    if (_isDiscovering) {
      Nearby().stopDiscovery();
      _isDiscovering = false;
    }
    Nearby().stopAdvertising();
  }

  void resumeDutyCycle() {
    debugPrint('[P2P_DEBUG] Resuming Mesh Duty Cycle');
    String shortId = AuthManager.deviceId;
    if (shortId.length > 31) shortId = shortId.substring(0, 31);
    
    _startAdvertisingLogic(shortId);
    _startDutyCycle(shortId);
  }

  void _startDutyCycle(String shortId) {
    _dutyCycleTimer?.cancel();
    
    // Start initial discovery immediately
    _executeDiscoveryCycle(shortId);
    
    // Toggle every 15 seconds: 15s scan, 15s sleep (unless active SOS)
    _dutyCycleTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      final alerts = OfflineCacheManager.getUnsyncedAlerts();
      final ownActiveAlert = alerts.where((a) => a.originalDeviceId == AuthManager.deviceId).firstOrNull;
      
      if (ownActiveAlert != null) {
        // Active Broadcast Mode: Continuous listening and broadcasting
        if (!_isDiscovering) await _executeDiscoveryCycle(shortId);
      } else {
        // Idle Mode: 50% Duty Cycle
        if (_isDiscovering) {
          debugPrint('[P2P_DEBUG] Mesh Duty Cycle: SLEEP (15s)');
          await Nearby().stopDiscovery();
          _isDiscovering = false;
        } else {
          debugPrint('[P2P_DEBUG] Mesh Duty Cycle: SCAN (15s)');
          await _executeDiscoveryCycle(shortId);
        }
      }
    });
  }

  Future<void> _executeDiscoveryCycle(String shortId) async {
    _isDiscovering = true;
    try {
      await Nearby().startDiscovery(
        shortId,
        _strategy,
        onEndpointFound: (id, name, serviceId) async {
          _showDebugToast('Discovered peer $name ($id)');
          debugPrint('[P2P_DEBUG] Discovered peer $name ($id)');
          if (shortId.compareTo(name) >= 0) return;
          if (_connectedEndpoints.contains(id)) return;
          
          try {
            await Nearby().requestConnection(
              shortId,
              id,
              onConnectionInitiated: (id, info) async {
                try {
                  await Nearby().acceptConnection(
                    id, 
                    onPayLoadRecieved: (endpointId, payload) => _handleIncomingPayload(endpointId, payload),
                    onPayloadTransferUpdate: (e, p) {}
                  );
                } catch (e) {
                  debugPrint('[P2P_DEBUG] Hardware fault during accept: $e');
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
              onDisconnected: (id) => _connectedEndpoints.remove(id),
            );
          } catch (e) {
            debugPrint('Hardware fault during request: $e');
          }
        },
        onEndpointLost: (id) => debugPrint('[P2P_DEBUG] Endpoint lost: $id'),
        serviceId: _serviceId,
      );
    } catch (e) {
      debugPrint('[P2P_DEBUG] Failed to start discovery: $e');
      _isDiscovering = false;
    }
  }

  Future<void> _syncLocalDatabaseWithPeer(String endpointId) async {
    final unsynced = OfflineCacheManager.getUnsyncedAlerts();
    if (unsynced.isEmpty) return;

    for (final alert in unsynced) {
      try {
        final payloadData = jsonEncode({
          "deviceId": AuthManager.deviceId,
          "alerts": [{
            "t": "SOS",
            "i": alert.id,
            "l": alert.lat,
            "g": alert.lng,
            "m": alert.message,
            "a": alert.approximateLocationText,
            "d": alert.originalDeviceId,
            "n": alert.originalSenderName,
            "ts": alert.timestamp
          }]
        });
        
        final signature = await P2pCryptoService().signPayload(payloadData);
        final envelope = jsonEncode({
          "p": payloadData,
          "k": P2pCryptoService().publicKey,
          "s": signature,
        });
        
        final bytes = Uint8List.fromList(utf8.encode(envelope));
        
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
    final payloadData = jsonEncode({
      "deviceId": AuthManager.deviceId,
      "alerts": [{
        "t": "SOS",
        "i": alert.id,
        "l": alert.lat,
        "g": alert.lng,
        "m": alert.message,
        "a": alert.approximateLocationText,
        "d": alert.originalDeviceId,
        "n": alert.originalSenderName,
        "ts": alert.timestamp
      }]
    });
    
    final signature = await P2pCryptoService().signPayload(payloadData);
    final envelope = jsonEncode({
      "p": payloadData,
      "k": P2pCryptoService().publicKey,
      "s": signature,
    });
    
    final bytes = Uint8List.fromList(utf8.encode(envelope));
    
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

  Future<void> broadcastClaimRescue(String alertId) async {
    final payloadData = jsonEncode({
      "deviceId": AuthManager.deviceId,
      "t": "CLAIM",
      "i": alertId,
      "ts": DateTime.now().millisecondsSinceEpoch,
    });
    
    final signature = await P2pCryptoService().signPayload(payloadData);
    final envelope = jsonEncode({
      "p": payloadData,
      "k": P2pCryptoService().publicKey,
      "s": signature,
    });
    
    final bytes = Uint8List.fromList(utf8.encode(envelope));
    for (final peerId in _connectedEndpoints) {
      try {
        await Nearby().sendBytesPayload(peerId, bytes);
      } catch (e) {
        debugPrint('[P2P_DEBUG] Failed to broadcast claim to $peerId: $e');
      }
    }
  }

  Future<void> broadcastChatMessage(String alertId, String encryptedText, String recipientPubKey) async {
    final payloadData = jsonEncode({
      "deviceId": AuthManager.deviceId,
      "t": "MSG",
      "i": alertId,
      "m": encryptedText,
      "ts": DateTime.now().millisecondsSinceEpoch,
    });
    
    final signature = await P2pCryptoService().signPayload(payloadData);
    final envelope = jsonEncode({
      "p": payloadData,
      "k": P2pCryptoService().publicKey,
      "s": signature,
    });
    
    final bytes = Uint8List.fromList(utf8.encode(envelope));
    for (final peerId in _connectedEndpoints) {
      try {
        await Nearby().sendBytesPayload(peerId, bytes);
      } catch (e) {
        debugPrint('[P2P_DEBUG] Failed to broadcast message to $peerId: $e');
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
          if (!await Permission.location.isGranted) {
            debugPrint('[P2P_DEBUG] Telemetry paused: Location permission missing in background');
            return;
          }
          final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
          _telemetrySequence++;
          final payloadData = jsonEncode({
            "deviceId": AuthManager.deviceId,
            "t": "LOC",
            "i": ownActiveAlert.id,
            "l": position.latitude,
            "g": position.longitude,
            "ts": DateTime.now().millisecondsSinceEpoch,
            "seq": _telemetrySequence,
            "hop": 4,
          });
          final signature = await P2pCryptoService().signPayload(payloadData);
          final envelope = jsonEncode({
            "p": payloadData,
            "k": P2pCryptoService().publicKey,
            "s": signature,
          });
          final bytes = Uint8List.fromList(utf8.encode(envelope));
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

  // 5. Receiving and Processing
  Future<void> _handleIncomingPayload(String endpointId, Payload payload) async {
    if (payload.type == PayloadType.BYTES && payload.bytes != null) {
      try {
        final str = utf8.decode(payload.bytes!);
        final dynamic envelopeData = jsonDecode(str);
        
        if (envelopeData is! Map || !envelopeData.containsKey('p') || !envelopeData.containsKey('k') || !envelopeData.containsKey('s')) {
          debugPrint('[P2P_SECURITY] Dropping unauthenticated or legacy non-signed packet.');
          return;
        }

        final String payloadStr = envelopeData['p'];
        final String pubKey = envelopeData['k'];
        final String signature = envelopeData['s'];
        
        final isValid = await P2pCryptoService().verifyPayload(payloadStr, pubKey, signature);
        if (!isValid) {
          debugPrint('[P2P_DEBUG] CRITICAL: Signature verification failed! Packet dropped (Potential spoofing/tampering).');
          return;
        }
        
        final decodedData = jsonDecode(payloadStr);
        if (decodedData is! Map || !decodedData.containsKey('deviceId')) {
          debugPrint('[P2P_DEBUG] CRITICAL: Missing deviceId in payload!');
          return;
        }

        final expectedDeviceId = P2pCryptoService.deriveDeviceIdFromKey(pubKey);
        if (decodedData['deviceId'] != expectedDeviceId) {
          debugPrint('[P2P_DEBUG] CRITICAL: Identity Spoofing Detected! Payload deviceId does not match derived public key.');
          return;
        }

        if (decodedData['type'] == 'LOCATION_UPDATE' || decodedData['t'] == 'LOC') {
          final String alertId = decodedData['id'] ?? decodedData['i'];
          final double lat = decodedData['lat'] ?? decodedData['l'];
          final double lng = decodedData['lng'] ?? decodedData['g'];
          final int ts = decodedData['timestamp'] ?? decodedData['ts'] ?? DateTime.now().millisecondsSinceEpoch;
          final int incomingSeq = decodedData['seq'] ?? 0;
          final int hops = decodedData['hop'] ?? 0;
          
          final String packetKey = "${alertId}_$incomingSeq";
          if (_processedPacketIds.contains(packetKey)) return;
          
          _processedPacketIds.add(packetKey);
          if (_processedPacketIds.length > 500) {
            _processedPacketIds.remove(_processedPacketIds.first);
          }
          
          if (hops <= 0) return;
          
          final existing = OfflineCacheManager.getAlert(alertId);
          if (existing != null) {
            if (ts <= existing.timestamp && incomingSeq <= existing.sequenceNumber) {
              return; // Ignore stale or delayed packet
            }
            existing.lat = lat;
            existing.lng = lng;
            existing.timestamp = ts;
            existing.sequenceNumber = incomingSeq;
            await OfflineCacheManager.saveAlert(existing);
            
            // Relay to other peers with decremented hop count
            final relayedData = Map<String, dynamic>.from(decodedData);
            relayedData['hop'] = hops - 1;
            relayedData['deviceId'] = AuthManager.deviceId;
            
            final relayedPayloadStr = jsonEncode(relayedData);
            final relayedSignature = await P2pCryptoService().signPayload(relayedPayloadStr);
            final relayedEnvelope = jsonEncode({
              "p": relayedPayloadStr,
              "k": P2pCryptoService().publicKey,
              "s": relayedSignature,
            });
            final relayedBytes = Uint8List.fromList(utf8.encode(relayedEnvelope));
            
            for (final peerId in _connectedEndpoints) {
              if (peerId != endpointId) await Nearby().sendBytesPayload(peerId, relayedBytes);
            }
          }
          return;
        }

        if (decodedData['t'] == 'CLAIM') {
          final String alertId = decodedData['i'];
          final String volunteerId = decodedData['deviceId'];
          final existing = OfflineCacheManager.getAlert(alertId);
          if (existing != null) {
            // Only victim updates their own alert or peers relay
            final alertNotification = AlertsManager().notifications.firstWhere((a) => a.clientAlertId == alertId, orElse: () => AlertNotification(clientAlertId: alertId, title: '', description: '', timestamp: DateTime.now(), type: AlertType.sos, latitude: 0, longitude: 0));
            if (alertNotification.type != AlertType.resolved) {
              AlertsManager().addSelfRescueEvent(RescueAcceptedEvent(
                victimDeviceId: existing.originalDeviceId,
                volunteerName: "Mesh Volunteer",
                volunteerDeviceId: volunteerId,
              ));
            }
          }
          return;
        }

        if (decodedData['t'] == 'MSG') {
          final String alertId = decodedData['i'];
          final String encryptedText = decodedData['m'];
          RescueChatSession().receiveMessagePayload(alertId, expectedDeviceId, encryptedText);
          return;
        }

        if (!decodedData.containsKey('alerts')) return;
        
        final List<dynamic> dataList = decodedData['alerts'];
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

          final approxLoc = jsonMap['approximateLocationText'] ?? jsonMap['a'];
          final origDevId = jsonMap['originalDeviceId'] ?? jsonMap['d'] ?? 'unknown_device';
          final origSender = jsonMap['originalSenderName'] ?? jsonMap['n'] ?? 'Unknown Sender';
          
          final alert = LocalSosAlert(
            id: id,
            lat: clampedLat,
            lng: clampedLng,
            message: message,
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
              clientAlertId: alert.id,
              latitude: alert.lat,
              longitude: alert.lng,
              message: alert.message,
              status: 'OPEN',
              timestamp: DateTime.fromMillisecondsSinceEpoch(alert.timestamp),
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
