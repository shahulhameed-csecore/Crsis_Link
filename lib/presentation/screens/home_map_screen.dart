import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:crsis_link_client/crsis_link_client.dart';
import '../../core/theme/design_system.dart';
import '../../core/auth/auth_manager.dart';
import '../../core/state/alerts_manager.dart';
import '../widgets/voice_note_recorder.dart';
import '../widgets/capsule_button.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/state/map_pins_manager.dart';
import '../widgets/audio_player_button.dart';
import 'package:geocoding/geocoding.dart';
class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({super.key});

  @override
  State<HomeMapScreen> createState() => HomeMapScreenState();
}

class HomeMapScreenState extends State<HomeMapScreen> with WidgetsBindingObserver {
  Timer? _heartbeatTimer;
  LatLng? _currentLocation;
  final MapController _mapController = MapController();
  String _errorMsg = '';
  final Set<int> _ignoredSosIds = {};
  StreamSubscription? _sosSubscription;
  bool _isConnected = true;
  // Default center (India) shown instantly while GPS resolves
  LatLng _mapCenter = const LatLng(20.5937, 78.9629);
  double _mapZoom = 5.0;

  @override
  void initState() {
    super.initState();
    _loadIgnoredIds();
    WidgetsBinding.instance.addObserver(this);
    MapPinsManager().addListener(_onPinsChanged);
    _determinePosition().whenComplete(() => _fetchActiveSos());
    _initStreaming();
    AuthManager.client.connectivityMonitor?.addListener(_onConnectivityChanged);
    
    // Start periodic heartbeat to prevent server-side TTL eviction (5 min)
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      // ignore: deprecated_member_use
      if (_currentLocation != null && AuthManager.client.streamingConnectionStatus == StreamingConnectionStatus.connected) {
        AuthManager.client.sos.updateLocation(
          AuthManager.deviceId, 
          _currentLocation!.latitude, 
          _currentLocation!.longitude
        ).catchError((e) {
          debugPrint('Heartbeat failed: $e');
        });
      }
    });
  }

  void _onConnectivityChanged(bool connected) {
    if (mounted) {
      setState(() {
        _isConnected = connected;
      });
    }
  }

  Future<void> _loadIgnoredIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('ignoredSosIds');
    if (list != null) {
      setState(() {
        _ignoredSosIds.addAll(list.map((e) => int.parse(e)));
      });
    }
  }

  Future<void> _saveIgnoredIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('ignoredSosIds', _ignoredSosIds.map((e) => e.toString()).toList());
  }

  void _onPinsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void jumpToCurrentLocation() {
    _recenterMap();
  }

  void _initStreaming() {
    // 1. Listen to streaming status changes to handle reconnects safely
    // ignore: deprecated_member_use
    AuthManager.client.addStreamingConnectionStatusListener(_onStreamingConnectionStatusChanged);

    // 2. If already connected when this runs, immediately bind
    // ignore: deprecated_member_use
    if (AuthManager.client.streamingConnectionStatus == StreamingConnectionStatus.connected) {
      _bindStream();
    }
  }

  void _onStreamingConnectionStatusChanged() {
    // ignore: deprecated_member_use
    if (AuthManager.client.streamingConnectionStatus == StreamingConnectionStatus.connected) {
      _bindStream();
      
      if (_currentLocation != null) {
        AuthManager.client.sos.updateLocation(
          AuthManager.deviceId, 
          _currentLocation!.latitude, 
          _currentLocation!.longitude
        ).catchError((e) {
          debugPrint('Reconnect heartbeat failed: $e');
        });
      }
      _fetchActiveSos();
    }
  }

  void _bindStream() {
    try {
      // Ensure we don't duplicate subscriptions on reconnect
      _sosSubscription?.cancel();
      
      // Send a Greeting to bind the stream to this deviceId on the server
      AuthManager.client.sos.sendStreamMessage(Greeting(
        message: AuthManager.deviceId,
        author: AuthManager.displayName,
        timestamp: DateTime.now(),
      ));

      _sosSubscription = AuthManager.client.sos.stream.listen((message) {
        debugPrint('Received stream message: ${message.runtimeType}');
        if (message is SosAlert) {
          debugPrint('[WebSocket] Received SosAlert from: ${message.deviceId}, status: ${message.status}');
          // Client-Side Echo Protection
          if (message.deviceId == AuthManager.deviceId) return;
          
          // Early Exit Guard Clause: If user ignored this pin, drop it entirely
          if (_ignoredSosIds.contains(message.id)) return;
          
          if (mounted) {
            setState(() {
              MapPinsManager().addOrUpdatePin(message);
              AlertsManager().addSosAlert(message);
            });
          }
        } else if (message is RescueAcceptedEvent) {
          debugPrint('[WebSocket] Received RescueAcceptedEvent for victim: ${message.victimDeviceId}');
          // Add to persistent alerts feed for everyone observing the ledger (except the volunteer who already added a local alert)
          if (message.volunteerDeviceId != AuthManager.deviceId) {
            AlertsManager().addRescueEvent(message);
          }
          
          if (message.victimDeviceId == AuthManager.deviceId) {
            if (mounted) {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: AppColors.pitchBlack,
                  title: const Text('Rescue on the way!', style: TextStyle(color: Colors.green)),
                  content: Text('${message.volunteerName} has accepted your request.', style: const TextStyle(color: Colors.white)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK', style: TextStyle(color: Colors.green)),
                    ),
                  ],
                ),
              );
            }
          }
        } else if (message is SosResolvedEvent) {
          debugPrint('[WebSocket] Received SosResolvedEvent for SOS ID: ${message.sosId}');
          AlertsManager().addResolvedEvent(message);
          MapPinsManager().removePin(message.sosId);
        }
      }, onError: (e) {
        debugPrint('WebSocket stream error: $e');
      });
    } catch (e) {
      debugPrint('Failed to bind streaming: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    MapPinsManager().removeListener(_onPinsChanged);
    _sosSubscription?.cancel();
    // ignore: deprecated_member_use
    AuthManager.client.removeStreamingConnectionStatusListener(_onStreamingConnectionStatusChanged);
    AuthManager.client.connectivityMonitor?.removeListener(_onConnectivityChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // ignore: deprecated_member_use
      if (_currentLocation != null && AuthManager.client.streamingConnectionStatus == StreamingConnectionStatus.connected) {
        AuthManager.client.sos.updateLocation(
          AuthManager.deviceId, 
          _currentLocation!.latitude, 
          _currentLocation!.longitude
        ).catchError((e) {
          debugPrint('Resumed heartbeat failed: $e');
        });
      }
      _fetchActiveSos();
    }
  }

  Future<void> _manualRefresh() async {
    HapticFeedback.mediumImpact();
    
    // Attempt to re-establish connection if needed
    // ignore: deprecated_member_use
    if (AuthManager.client.streamingConnectionStatus != StreamingConnectionStatus.connected) {
      // ignore: deprecated_member_use
      await AuthManager.client.openStreamingConnection();
    }
    
    await _fetchActiveSos();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Map and radar data refreshed'),
          backgroundColor: AppColors.pitchBlack,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _fetchActiveSos() async {
    try {
      final lat = _currentLocation?.latitude ?? _mapCenter.latitude;
      final lng = _currentLocation?.longitude ?? _mapCenter.longitude;
      
      final alerts = await AuthManager.client.sos.getActiveAlerts(lat, lng);
      if (mounted) {
        MapPinsManager().setPins(alerts.where((a) => !_ignoredSosIds.contains(a.id)).toList());
      }
    } catch (e) {
      debugPrint('Error fetching SOS pins: $e');
    }
  }

  Future<void> _determinePosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services disabled');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions permanently denied');
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 5),
        ).timeout(const Duration(seconds: 5));
      } catch (e) {
        position = await Geolocator.getLastKnownPosition();
        position ??= await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
        ).timeout(const Duration(seconds: 5));
      }
      

      
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position!.latitude, position.longitude);
          _mapCenter = _currentLocation!;
          _mapZoom = 15.0;
          _errorMsg = '';
        });
        _mapController.move(_currentLocation!, 15.0);
        
        // Push the location to the server for spatial broadcasting
        try {
          await AuthManager.client.sos.updateLocation(AuthManager.deviceId, position.latitude, position.longitude);
        } catch (e) {
          debugPrint('Failed to update location on server: $e');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          // Explicitly block map rendering instead of falling back to a hardcoded location
          _currentLocation = null;
          _errorMsg = e.toString();
        });
        
        final isPermanent = _errorMsg.contains('permanently denied') || _errorMsg.contains('disabled');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isPermanent ? 'Location access is permanently denied. We cannot broadcast your SOS.' : 'Location Error: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: AppColors.emergencyRed,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: isPermanent ? 'OPEN SETTINGS' : 'RETRY',
              textColor: Colors.white,
              onPressed: () {
                if (isPermanent) {
                  _errorMsg.contains('disabled') ? Geolocator.openLocationSettings() : Geolocator.openAppSettings();
                } else {
                  _determinePosition().whenComplete(() => _fetchActiveSos());
                }
              },
            ),
          ),
        );
      }
    }
  }

  void _recenterMap() {
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 15.0);
    }
  }

  void panTo(LatLng position) {
    _mapController.move(position, 16.0);
  }

  void _showFuzzySosDetails(SosAlert alert) {
    bool isSubmitting = false;
    
    // Triage Inference Logic
    String category = 'General Emergency';
    final msg = alert.message?.toLowerCase() ?? '';
    if (msg.contains('medical') || msg.contains('doctor') || msg.contains('bleeding')) {
      category = 'Medical';
    } else if (msg.contains('flood') || msg.contains('water') || msg.contains('drowning')) {
      category = 'Flood Extraction';
    } else if (msg.contains('food') || msg.contains('supply') || msg.contains('supplies')) {
      category = 'Supplies Needed';
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.pitchBlack,
      isScrollControlled: true, // Crucial for preventing overflow
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Triage Header (Emergency Type)
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: AppColors.emergencyRed, size: 36),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              category,
                              style: AppTypography.primaryHeader.copyWith(
                                color: AppColors.emergencyRed,
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      // General Area
                      const Text('LOCATION AREA', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        alert.approximateLocationText ?? 'Emergency nearby (Exact route unlocked on accept)',
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 20),
                      
                      // Description
                      const Text('SITUATION NOTES', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          alert.message?.isNotEmpty == true ? alert.message! : 'No additional details provided.',
                          style: const TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                      ),
                      if (alert.photoBase64 != null && alert.photoBase64!.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text('ATTACHED PHOTO', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            base64Decode(alert.photoBase64!),
                            height: 200,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.grey, size: 50),
                          ),
                        ),
                      ],
                      if (alert.audioUrl != null && alert.audioUrl!.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text('VOICE NOTE', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        AudioPlayerButton(audioUrl: alert.audioUrl!),
                      ],
                      const SizedBox(height: 32),
                      
                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: TextButton(
                              onPressed: () {
                                final alertId = alert.id;
                                if (alertId == null) return;
                                setState(() {
                                  _ignoredSosIds.add(alertId);
                                  MapPinsManager().removePin(alertId);
                                });
                                _saveIgnoredIds();
                                AlertsManager().addIgnoredAlert(alertId, alert.senderName);
                                Navigator.pop(ctx);
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.grey,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                              ),
                              child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: isSubmitting ? null : () async {
                                final alertId = alert.id;
                                if (alertId == null) return;
                                setModalState(() => isSubmitting = true);
                                try {
                                  await AuthManager.client.sos.claimRescue(AuthManager.deviceId, AuthManager.displayName, alertId);
                                  if (ctx.mounted) {
                                    final updatedAlert = alert.copyWith(
                                      status: 'CLAIMED',
                                      volunteerDeviceId: AuthManager.deviceId,
                                    );
                                    MapPinsManager().addOrUpdatePin(updatedAlert);
                                    
                                    AlertsManager().addSelfRescueEvent(RescueAcceptedEvent(
                                      victimDeviceId: alert.deviceId,
                                      volunteerName: AuthManager.displayName,
                                      volunteerDeviceId: AuthManager.deviceId,
                                    ));
                                    Navigator.pop(ctx);
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Rescue Claimed Successfully!'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(content: Text('Failed to claim: $e')),
                                    );
                                  }
                                  setModalState(() => isSubmitting = false);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                              ),
                              child: isSubmitting 
                                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white))
                                : const Text('Accept & Reveal Route', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showSosModal(LatLng position) {
    final TextEditingController messageController = TextEditingController();
    final TextEditingController phoneController = TextEditingController();
    bool isSubmitting = false;
    String? pendingAudioUrl;
    String? pendingPhotoBase64;

    Future<void> pickImage(StateSetter setModalState) async {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.camera);
      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        final compressed = await FlutterImageCompress.compressWithList(
          bytes,
          minWidth: 400,
          minHeight: 400,
          quality: 50,
        );
        setModalState(() {
          pendingPhotoBase64 = base64Encode(compressed);
        });
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.pitchBlack,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppColors.emergencyRed, size: 32),
                      const SizedBox(width: 12),
                      Text(
                        'DROP SOS PIN',
                        style: AppTypography.primaryHeader.copyWith(
                          color: AppColors.emergencyRed,
                          fontSize: 22,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Provide emergency details to broadcast to nearby responders.',
                    style: AppTypography.body.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: messageController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'e.g. Need generator, Medical help...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Colors.grey.withValues(alpha: 0.1),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: AppColors.emergencyRed),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Victim Phone (Required)',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Colors.grey.withValues(alpha: 0.1),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: AppColors.emergencyRed),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.camera_alt, color: Colors.blue),
                        onPressed: () => pickImage(setModalState),
                      ),
                      if (pendingPhotoBase64 != null)
                        const Text('Photo attached', style: TextStyle(color: Colors.green)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Voice Note Recorder
                  VoiceNoteRecorder(
                    onRecorded: (url) {
                      pendingAudioUrl = url.isEmpty ? null : url;
                    },
                  ),
                  const SizedBox(height: 24),
                  CapsuleButton(
                    text: 'BROADCAST SOS',
                    style: CapsuleStyle.emergency,
                    isLoading: isSubmitting,
                    onPressed: () async {
                      setModalState(() => isSubmitting = true);
                      try {
                        String? approxLocation;
                        try {
                          List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
                          if (placemarks.isNotEmpty) {
                            final place = placemarks.first;
                            approxLocation = place.subLocality?.isNotEmpty == true ? place.subLocality : (place.locality?.isNotEmpty == true ? place.locality : place.name);
                            if (approxLocation != null && approxLocation.isNotEmpty) {
                              approxLocation = 'Emergency in $approxLocation';
                            }
                          }
                        } catch (e) {
                          debugPrint('Geocoding failed: $e');
                        }

                        final response = await AuthManager.client.sos.broadcastSos(
                          AuthManager.deviceId,
                          AuthManager.displayName,
                          position.latitude,
                          position.longitude,
                          messageController.text.trim().isEmpty ? null : messageController.text.trim(),
                          pendingAudioUrl,
                          phoneController.text.trim(),
                          pendingPhotoBase64,
                          approxLocation,
                        ).timeout(const Duration(seconds: 10));
                        if (mounted) {
                          setState(() {
                            MapPinsManager().addOrUpdatePin(response.alert);
                          });
                        }
                        _fetchActiveSos(); // Ensure sync
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          if (!mounted) return;
                          if (response.notifiedCount == 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('No one is available near you at the moment. Your request is still active.'),
                                backgroundColor: AppColors.emergencyRed,
                                duration: Duration(seconds: 5),
                              ),
                            );
                          }
                        }
                      } on TimeoutException catch (e) {
                        debugPrint('SOS Broadcast timed out: $e');
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('Connection timed out. Please check your internet and try again.'),
                              backgroundColor: AppColors.emergencyRed,
                            ),
                          );
                        }
                        setModalState(() => isSubmitting = false);
                      } on SocketException catch (e) {
                        debugPrint('SOS Broadcast offline: $e');
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('No internet connection. Please connect and try again.'),
                              backgroundColor: AppColors.emergencyRed,
                            ),
                          );
                        }
                        setModalState(() => isSubmitting = false);
                      } catch (e) {
                        debugPrint('SOS Broadcast failed: $e');
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text('Failed to drop pin: $e'),
                              backgroundColor: AppColors.emergencyRed,
                            ),
                          );
                        }
                        setModalState(() => isSubmitting = false);
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
          },
        );
      },
    // LEAK-P3-01 FIX: Dispose the controller when the modal is dismissed in any way.
    ).whenComplete(() {
      messageController.dispose();
      phoneController.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    const ColorFilter greyscaleAndInvert = ColorFilter.matrix(<double>[
      -1,  0,  0, 0, 255,
       0, -1,  0, 0, 255,
       0,  0, -1, 0, 255,
       0,  0,  0, 1,   0,
    ]);

    final activeClaimed = MapPinsManager().pins.where((a) => a.status == 'CLAIMED' && a.volunteerDeviceId == AuthManager.deviceId).toList();

    return Scaffold(
      backgroundColor: AppColors.pitchBlack,
      body: Stack(
        children: [
          // Dark background so map never shows white
          Positioned.fill(
            child: Container(color: const Color(0xFF1a1a2e)),
          ),
          if (_currentLocation != null)
            Positioned.fill(
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _mapCenter,
                  initialZoom: _mapZoom,
                  minZoom: 3.0,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all,
                  ),
                  onLongPress: (tapPosition, point) => _showSosModal(point),
                  onTap: (tapPosition, point) {
                    final openAlerts = MapPinsManager().pins.where((a) => a.status == 'OPEN' && a.deviceId != AuthManager.deviceId);
                    for (var alert in openAlerts) {
                      final distance = const Distance().as(LengthUnit.Meter, point, LatLng(alert.latitude, alert.longitude));
                      if (distance <= 2000) {
                        _showFuzzySosDetails(alert);
                        break;
                      }
                    }
                  },
                ),
                children: [
                  ColorFiltered(
                    colorFilter: greyscaleAndInvert,
                    child: ColoredBox(
                      color: Colors.white, // white inverts to dark via matrix
                      child: TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.crsis_link.app',
                        errorTileCallback: (tile, error, stackTrace) {
                          debugPrint('Tile load error: $error');
                        },
                      ),
                    ),
                  ),
                  CircleLayer(
                    circles: [
                      ...MapPinsManager().pins
                        .where((a) => a.status == 'CLAIMED' && a.volunteerDeviceId == AuthManager.deviceId && !a.isRescuerVerified)
                        .map((a) => CircleMarker(
                              point: LatLng(a.latitude, a.longitude),
                              color: Colors.blue.withValues(alpha: 0.2),
                              borderColor: Colors.blue,
                              borderStrokeWidth: 2,
                              useRadiusInMeter: true,
                              radius: 200,
                            )),
                      ...MapPinsManager().pins
                        .where((a) => a.status == 'OPEN' && a.deviceId != AuthManager.deviceId)
                        .map((a) => CircleMarker(
                              point: LatLng(a.latitude, a.longitude),
                              color: Colors.red.withValues(alpha: 0.3),
                              borderColor: Colors.red,
                              borderStrokeWidth: 1,
                              useRadiusInMeter: true,
                              radius: 2000,
                            )),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      // Render dropped SOS pins
                      ...MapPinsManager().pins
                        .where((alert) => alert.deviceId == AuthManager.deviceId || alert.status != 'OPEN')
                        .map((alert) {
                        return Marker(
                          point: LatLng(alert.latitude, alert.longitude),
                          width: 40,
                          height: 40,
                          child: _AnimatedSosMarker(
                            key: ValueKey('${alert.id}_${alert.status}'),
                            alert: alert,
                            onIgnore: (id) {
                              _ignoredSosIds.add(id);
                              MapPinsManager().removePin(id);
                            },
                            onResolve: (id) {
                              MapPinsManager().removePin(id);
                              AlertsManager().resolveSosAlert(id);
                            },
                          ),
                        );
                      }),
                      
                      // Render current location
                      Marker(
                        point: _currentLocation!,
                        width: 60,
                        height: 60,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.3),
                                shape: BoxShape.circle,
                              ),
                            ),
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            // Show map immediately at default center even before GPS resolves
            Positioned.fill(
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _mapCenter,
                  initialZoom: _mapZoom,
                  minZoom: 3.0,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all,
                  ),
                  onLongPress: _currentLocation != null
                      ? (tapPosition, point) => _showSosModal(point)
                      : null,
                  onTap: (tapPosition, point) {
                    final openAlerts = MapPinsManager().pins.where((a) => a.status == 'OPEN' && a.deviceId != AuthManager.deviceId);
                    for (var alert in openAlerts) {
                      final distance = const Distance().as(LengthUnit.Meter, point, LatLng(alert.latitude, alert.longitude));
                      if (distance <= 2000) {
                        _showFuzzySosDetails(alert);
                        break;
                      }
                    }
                  },
                ),
                children: [
                  ColorFiltered(
                    colorFilter: ColorFilter.matrix(<double>[
                      -1,  0,  0, 0, 255,
                       0, -1,  0, 0, 255,
                       0,  0, -1, 0, 255,
                       0,  0,  0, 1,   0,
                    ]),
                    child: ColoredBox(
                      color: Colors.white, // white inverts to dark via matrix
                      child: TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.crsis_link.app',
                      ),
                    ),
                  ),
                  CircleLayer(
                    circles: [
                      ...MapPinsManager().pins
                        .where((a) => a.status == 'CLAIMED' && a.volunteerDeviceId == AuthManager.deviceId && !a.isRescuerVerified)
                        .map((a) => CircleMarker(
                              point: LatLng(a.latitude, a.longitude),
                              color: Colors.blue.withValues(alpha: 0.2),
                              borderColor: Colors.blue,
                              borderStrokeWidth: 2,
                              useRadiusInMeter: true,
                              radius: 200,
                            )),
                      ...MapPinsManager().pins
                        .where((a) => a.status == 'OPEN' && a.deviceId != AuthManager.deviceId)
                        .map((a) => CircleMarker(
                              point: LatLng(a.latitude, a.longitude),
                              color: Colors.red.withValues(alpha: 0.3),
                              borderColor: Colors.red,
                              borderStrokeWidth: 1,
                              useRadiusInMeter: true,
                              radius: 2000,
                            )),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      ...MapPinsManager().pins
                        .where((alert) => alert.deviceId == AuthManager.deviceId || alert.status != 'OPEN')
                        .map((alert) {
                        return Marker(
                          point: LatLng(alert.latitude, alert.longitude),
                          width: 40,
                          height: 40,
                          child: _AnimatedSosMarker(
                            key: ValueKey('${alert.id}_${alert.status}'),
                            alert: alert,
                            onIgnore: (id) {
                              _ignoredSosIds.add(id);
                              MapPinsManager().removePin(id);
                            },
                            onResolve: (id) {
                              MapPinsManager().removePin(id);
                              AlertsManager().resolveSosAlert(id);
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                  if (_errorMsg.isNotEmpty)
                    Center(
                      child: Container(
                        margin: const EdgeInsets.all(24),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.emergencyRed),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_off, color: AppColors.emergencyRed, size: 40),
                            const SizedBox(height: 12),
                            Text(_errorMsg.contains('permanently denied') ? 'Location access is permanently denied. We cannot broadcast your SOS.' : _errorMsg.replaceAll('Exception: ', ''),
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white)),
                            const SizedBox(height: 12),
                            if (_errorMsg.contains('permanently denied') || _errorMsg.contains('disabled'))
                              ElevatedButton(
                                onPressed: _errorMsg.contains('disabled') ? Geolocator.openLocationSettings : Geolocator.openAppSettings,
                                style: ElevatedButton.styleFrom(backgroundColor: AppColors.emergencyRed),
                                child: const Text('OPEN SETTINGS', style: TextStyle(color: Colors.white)),
                              )
                            else
                              ElevatedButton(
                                onPressed: () {
                                  _determinePosition().whenComplete(() => _fetchActiveSos());
                                },
                                style: ElevatedButton.styleFrom(backgroundColor: AppColors.emergencyRed),
                                child: const Text('RETRY GPS', style: TextStyle(color: Colors.white)),
                              )
                          ],
                        ),
                      ),
                    )
                  else
                    const Center(child: CircularProgressIndicator(color: AppColors.emergencyRed)),
                ],
              ),
            ),
            
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.pitchBlack.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.surfaceBorder.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          'RADAR ACTIVE',
                          style: AppTypography.subtitle.copyWith(
                            color: AppColors.emergencyRed,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Long-press map to drop SOS',
                                  style: TextStyle(color: Colors.white, fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.delete_sweep, color: Colors.white54),
                              tooltip: 'Hide All Pins',
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: AppColors.pitchBlack,
                                    title: const Text('Hide all current pins?', style: TextStyle(color: Colors.white)),
                                    content: const Text('This will remove all pins from your map. Other users will still see them.', style: TextStyle(color: Colors.white70)),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(ctx);
                                          setState(() {
                                            for (final pin in MapPinsManager().pins) {
                                              if (pin.id != null) {
                                                _ignoredSosIds.add(pin.id!);
                                                AlertsManager().addIgnoredAlert(pin.id!, pin.senderName);
                                              }
                                            }
                                            _saveIgnoredIds();
                                            MapPinsManager().setPins([]);
                                          });
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('All pins hidden locally'), backgroundColor: Colors.green),
                                          );
                                        },
                                        child: const Text('Hide', style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _ManualRefreshButton(onRefresh: _manualRefresh),
                      FloatingActionButton(
                        heroTag: 'recenterBtn',
                        onPressed: _recenterMap,
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.pitchBlack,
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                          side: BorderSide(color: AppColors.surfaceBorder.withValues(alpha: 0.2)),
                        ),
                        child: const Icon(Icons.my_location),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
          
          if (!_isConnected)
            Positioned(
              top: 50,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade800,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text('Reconnecting to server...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          
          if (activeClaimed.isNotEmpty)
            Positioned(
              bottom: 120,
              left: 0,
              right: 0,
              child: Center(
                child: FloatingActionButton.extended(
                  onPressed: () async {
                    final alert = activeClaimed.first;
                    final lat = alert.latitude;
                    final lng = alert.longitude;
                    try {
                      final uri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
                      bool launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
                      if (!launched) {
                        final fallback = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
                        launched = await launchUrl(fallback, mode: LaunchMode.externalApplication);
                        if (!launched) {
                          throw Exception('No map application found.');
                        }
                      }
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to open Maps: $e'), backgroundColor: Colors.red),
                      );
                    }
                  },
                  backgroundColor: Colors.blue,
                  icon: const Icon(Icons.navigation, color: Colors.white),
                  label: const Text('Start Navigation', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AnimatedSosMarker extends StatefulWidget {
  final SosAlert alert;
  final void Function(int) onIgnore;
  final void Function(int) onResolve;
  const _AnimatedSosMarker({super.key, required this.alert, required this.onIgnore, required this.onResolve});

  @override
  State<_AnimatedSosMarker> createState() => _AnimatedSosMarkerState();
}

class _AnimatedSosMarkerState extends State<_AnimatedSosMarker> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_AnimatedSosMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.alert.status != widget.alert.status) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOwnPin = widget.alert.deviceId == AuthManager.deviceId;
    
    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTap: () => _showSosDetails(context, widget.alert, isOwnPin),
        child: Container(
          decoration: isOwnPin ? BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.blue, width: 2),
          ) : null,
          child: Stack(
            alignment: Alignment.topRight,
            clipBehavior: Clip.none,
            children: [
              Icon(
                Icons.warning, 
                color: widget.alert.status == 'CLAIMED' ? const Color(0xFF28A745) : AppColors.emergencyRed, 
                size: 40
              ),
              if (widget.alert.isVisuallyVerified)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.verified, color: Colors.blue, size: 18),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSosDetails(BuildContext context, SosAlert alert, bool isOwnPin) {
    bool isSubmitting = false;
    final TextEditingController pinController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.pitchBlack,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      isScrollControlled: true,
      builder: (ctx) {
        return PopScope(
          canPop: false,
          child: StatefulBuilder(
            builder: (ctx, setModalState) {
              final bool isClaimed = alert.status == 'CLAIMED';
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  Row(
                    children: [
                      Icon(isClaimed ? Icons.check_circle : Icons.emergency, 
                           color: isClaimed ? Colors.green : AppColors.emergencyRed, size: 32),
                      const SizedBox(width: 12),
                      Text(
                        isOwnPin ? 'YOUR SOS' : (isClaimed ? 'RESCUE CLAIMED' : 'SOS ALERT'),
                        style: AppTypography.primaryHeader.copyWith(
                          color: isOwnPin ? Colors.blue : (isClaimed ? Colors.green : AppColors.emergencyRed),
                          fontSize: 22,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Victim: ${alert.senderName}',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    alert.message?.isNotEmpty == true ? alert.message! : 'No additional details provided.',
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  if (alert.photoBase64 != null && alert.photoBase64!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        height: 220,
                        width: double.infinity,
                        child: Image.memory(
                          base64Decode(alert.photoBase64!),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ],
                  if (alert.audioUrl != null && alert.audioUrl!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    AudioPlayerButton(audioUrl: alert.audioUrl!),
                  ],
                  if (isOwnPin && isClaimed && alert.verificationPin != null && !alert.isRescuerVerified) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Show this PIN to your rescuer when they arrive.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.green, fontSize: 14),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            alert.verificationPin!,
                            style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 8),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (isOwnPin)
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(ctx),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.grey,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                ),
                                child: const Text('CANCEL'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: isSubmitting ? null : () async {
                                  final alertId = alert.id;
                                  if (alertId == null) return;
                                  setModalState(() => isSubmitting = true);
                                  try {
                                    final success = await AuthManager.client.sos.resolveSOS(alertId, AuthManager.deviceId);
                                    if (!success) {
                                      if (ctx.mounted) {
                                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Failed to resolve: Not found or unauthorized.')));
                                      }
                                      setModalState(() => isSubmitting = false);
                                      return;
                                    }
                                    if (ctx.mounted) {
                                      Navigator.pop(ctx);
                                      widget.onResolve(alertId);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('SOS Resolved / Cleared.')),
                                      );
                                    }
                                  } catch (e) {
                                    if (ctx.mounted) {
                                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Failed to resolve: $e')));
                                    }
                                    setModalState(() => isSubmitting = false);
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.emergencyRed,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                ),
                                child: isSubmitting 
                                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white))
                                  : const Text('RESOLVE SOS'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (!isClaimed)
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  final alertId = alert.id;
                                  if (alertId == null) return;
                                  widget.onIgnore(alertId);
                                  Navigator.pop(ctx);
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.grey,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                ),
                                child: const Text('DENY / IGNORE'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: isSubmitting ? null : () async {
                                  final alertId = alert.id;
                                  if (alertId == null) return;
                                  setModalState(() => isSubmitting = true);
                                  try {
                                    await AuthManager.client.sos.claimRescue(AuthManager.deviceId, AuthManager.displayName, alertId);
                                    if (ctx.mounted) {
                                      final updatedAlert = alert.copyWith(
                                        status: 'CLAIMED',
                                        volunteerDeviceId: AuthManager.deviceId,
                                      );
                                      MapPinsManager().addOrUpdatePin(updatedAlert);
                                      
                                      AlertsManager().addSelfRescueEvent(RescueAcceptedEvent(
                                        victimDeviceId: alert.deviceId,
                                        volunteerName: AuthManager.displayName,
                                        volunteerDeviceId: AuthManager.deviceId,
                                      ));
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        const SnackBar(
                                          content: Text('Rescue Claimed Successfully!'),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (ctx.mounted) {
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        SnackBar(content: Text('Failed to claim: $e')),
                                      );
                                    }
                                    setModalState(() => isSubmitting = false);
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                ),
                                child: isSubmitting 
                                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white))
                                  : const Text('ACCEPT RESCUE'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (isClaimed && alert.volunteerDeviceId == AuthManager.deviceId)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!alert.isRescuerVerified) ...[
                          CapsuleButton(
                            text: 'Contact Victim',
                            style: CapsuleStyle.secondary,
                            onPressed: () async {
                              try {
                                final url = Uri.parse('tel:${alert.victimPhone}');
                                bool launched = await launchUrl(url, mode: LaunchMode.externalApplication);
                                if (!launched) {
                                  throw Exception('Dialer not supported on this device.');
                                }
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Could not open phone: $e'), backgroundColor: Colors.red),
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Search the 200-meter area. Ask the victim for their 4-digit PIN to verify and reveal exact coordinates.',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: pinController,
                            keyboardType: TextInputType.number,
                            maxLength: 4,
                            style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              hintText: 'Enter 4-Digit Victim PIN',
                              hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 16, letterSpacing: 0, fontWeight: FontWeight.normal),
                              filled: true,
                              fillColor: Colors.grey.withValues(alpha: 0.1),
                              counterText: '',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          CapsuleButton(
                            text: 'VERIFY PIN',
                            style: CapsuleStyle.primary,
                            isLoading: isSubmitting,
                            onPressed: () async {
                              final alertId = alert.id;
                              if (alertId == null) return;
                              if (pinController.text.length != 4) return;
                              setModalState(() => isSubmitting = true);
                              try {
                                await AuthManager.client.sos.verifyHelperPin(alertId, pinController.text);
                                if (ctx.mounted) {
                                  alert.isRescuerVerified = true;
                                  setModalState(() => isSubmitting = false);
                                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('PIN Verified! Exact location revealed.', style: TextStyle(color: Colors.green))));
                                }
                              } catch (e) {
                                if (ctx.mounted) {
                                  setModalState(() => isSubmitting = false);
                                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Incorrect PIN. Please verify the 4-digit number with the victim.'), backgroundColor: AppColors.emergencyRed));
                                }
                              }
                            }
                          ),
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue.withValues(alpha: 0.5)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Exact GPS Coordinates:', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text('${alert.latitude}, ${alert.longitude}', style: const TextStyle(color: Colors.white, fontSize: 16)),
                                const SizedBox(height: 8),
                                const Text('Street Address:', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                const Text('Verified Victim Location', style: TextStyle(color: Colors.white, fontSize: 16)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          CapsuleButton(
                            text: 'COMPLETE RESCUE',
                            style: CapsuleStyle.primary,
                            isLoading: isSubmitting,
                            onPressed: () async {
                              final alertId = alert.id;
                              if (alertId == null) return;
                              setModalState(() => isSubmitting = true);
                              try {
                                await AuthManager.client.sos.completeRescue(AuthManager.deviceId, alertId);
                                if (ctx.mounted) {
                                  Navigator.pop(ctx);
                                  widget.onResolve(alertId);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Rescue Completed Successfully!'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: Text('Failed to complete: $e')),
                                  );
                                }
                                setModalState(() => isSubmitting = false);
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            );
            },
          ),
        );
      },
    ).whenComplete(() {
      pinController.dispose();
    });
  }
}

class _ManualRefreshButton extends StatefulWidget {
  final Future<void> Function() onRefresh;
  const _ManualRefreshButton({required this.onRefresh});

  @override
  State<_ManualRefreshButton> createState() => _ManualRefreshButtonState();
}

class _ManualRefreshButtonState extends State<_ManualRefreshButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    
    setState(() => _isRefreshing = true);
    _controller.repeat();
    
    await widget.onRefresh();
    
    if (mounted) {
      _controller.stop();
      _controller.reset();
      setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'refreshBtn',
      onPressed: _handleRefresh,
      backgroundColor: Colors.white,
      foregroundColor: AppColors.pitchBlack,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(30),
        side: const BorderSide(color: AppColors.surfaceBorder, width: 1),
      ),
      child: RotationTransition(
        turns: _controller,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

