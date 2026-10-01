import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:crsis_link_client/crsis_link_client.dart';
import '../../core/theme/design_system.dart';
import '../../core/auth/auth_manager.dart';
import 'auth/login_screen.dart';

class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({super.key});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen> {
  LatLng? _currentLocation;
  final MapController _mapController = MapController();
  String _errorMsg = '';
  List<SosAlert> _sosPins = [];
  StreamSubscription? _sosSubscription;

  @override
  void initState() {
    super.initState();
    _determinePosition();
    _fetchActiveSos();
    _initStreaming();
  }

  void _initStreaming() {
    try {
      // Open Serverpod WebSockets connection
      AuthManager.client.openStreamingConnection();
      
      // Listen to real-time SOS broadcasts
      _sosSubscription = AuthManager.client.sos.stream.listen((message) {
        if (message is SosAlert) {
          if (mounted) {
            setState(() {
              if (message.isActive) {
                // Add or update the pin instantly
                final idx = _sosPins.indexWhere((a) => a.id == message.id);
                if (idx >= 0) {
                  _sosPins[idx] = message;
                } else {
                  _sosPins.add(message);
                }
              } else {
                // Remove if the alert was cancelled
                _sosPins.removeWhere((a) => a.id == message.id);
              }
            });
          }
        }
      }, onError: (e) {
        debugPrint('WebSocket stream error: $e');
      });
    } catch (e) {
      debugPrint('Failed to initialize streaming: $e');
    }
  }

  @override
  void dispose() {
    _sosSubscription?.cancel();
    AuthManager.client.closeStreamingConnection();
    super.dispose();
  }

  Future<void> _fetchActiveSos() async {
    try {
      final alerts = await AuthManager.client.sos.getActiveAlerts();
      if (mounted) {
        setState(() {
          _sosPins = alerts;
        });
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

      Position? position = await Geolocator.getLastKnownPosition();
      if (position == null) {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
        ).timeout(const Duration(seconds: 5));
      }
      
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position!.latitude, position.longitude);
          _errorMsg = '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          // Fallback to New Delhi so we don't show an endless brown ocean (Null Island)
          _currentLocation = const LatLng(28.6139, 77.2090); 
          _errorMsg = ''; // Clear error so map renders
        });
      }
    }
  }

  void _recenterMap() {
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 15.0);
    }
  }

  void _showSosModal(LatLng position) {
    final TextEditingController messageController = TextEditingController();
    bool isSubmitting = false;

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
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.emergencyRed,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                      ),
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              setModalState(() => isSubmitting = true);
                              try {
                                final newAlert = await AuthManager.client.sos.broadcastSos(
                                  position.latitude,
                                  position.longitude,
                                  messageController.text.trim(),
                                );
                                setState(() {
                                  // Remove any previous pin by this user to keep it simple, 
                                  // or just refresh the list. Let's just refresh.
                                  _sosPins.add(newAlert);
                                });
                                _fetchActiveSos(); // Ensure sync
                                if (ctx.mounted) Navigator.pop(ctx);
                              } catch (e) {
                                debugPrint('SOS Broadcast failed: $e');
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content: Text('Failed to drop pin. Try again.'),
                                      backgroundColor: AppColors.emergencyRed,
                                    ),
                                  );
                                }
                                setModalState(() => isSubmitting = false);
                              }
                            },
                      child: isSubmitting
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text(
                              'BROADCAST SOS',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const ColorFilter greyscaleAndInvert = ColorFilter.matrix(<double>[
      -1,  0,  0, 0, 255,
       0, -1,  0, 0, 255,
       0,  0, -1, 0, 255,
       0,  0,  0, 1,   0,
    ]);

    return Scaffold(
      backgroundColor: AppColors.pitchBlack,
      body: Stack(
        children: [
          if (_currentLocation != null)
            Positioned.fill(
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _currentLocation!,
                  initialZoom: 15.0,
                  minZoom: 3.0, // Prevents zooming out too far (stops multiple Earths from rendering)
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all, // Rotation restored
                  ),
                  onLongPress: (tapPosition, point) => _showSosModal(point),
                ),
                children: [
                  ColorFiltered(
                    colorFilter: greyscaleAndInvert,
                    child: TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.crsis_link',
                    ),
                  ),
                  MarkerLayer(
                    markers: [
                      // Render dropped SOS pins
                      ..._sosPins.map((alert) {
                        return Marker(
                          point: LatLng(alert.latitude, alert.longitude),
                          width: 40,
                          height: 40,
                          child: _AnimatedSosMarker(alert: alert),
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
          else if (_errorMsg.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_off, color: AppColors.emergencyRed, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      _errorMsg,
                      textAlign: TextAlign.center,
                      style: AppTypography.body.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _determinePosition,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.emergencyRed),
                      child: const Text('RETRY', style: TextStyle(color: Colors.white)),
                    )
                  ],
                ),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: AppColors.emergencyRed),
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
                    ],
                  ),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FloatingActionButton(
                        onPressed: _recenterMap,
                        backgroundColor: AppColors.pitchBlack,
                        foregroundColor: Colors.white,
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
        ],
      ),
    );
  }
}

class _AnimatedSosMarker extends StatefulWidget {
  final SosAlert alert;
  const _AnimatedSosMarker({required this.alert});

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
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTap: () => _showSosDetails(context, widget.alert),
        child: Icon(
          Icons.warning, 
          color: widget.alert.status == 'CLAIMED' ? Colors.green : AppColors.emergencyRed, 
          size: 40
        ),
      ),
    );
  }

  void _showSosDetails(BuildContext context, SosAlert alert) {
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.pitchBlack,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final bool isClaimed = alert.status == 'CLAIMED';
            return Padding(
              padding: const EdgeInsets.all(24),
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
                        isClaimed ? 'RESCUE CLAIMED' : 'SOS ALERT',
                        style: AppTypography.primaryHeader.copyWith(
                          color: isClaimed ? Colors.green : AppColors.emergencyRed,
                          fontSize: 22,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Victim: ${alert.userInfo?.userName ?? 'Unknown User'}',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    alert.message?.isNotEmpty == true ? alert.message! : 'No additional details provided.',
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  if (!isClaimed)
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.emergencyRed,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                setModalState(() => isSubmitting = true);
                                try {
                                  await AuthManager.client.sos.claimRescue(alert.id!);
                                  if (ctx.mounted) {
                                    Navigator.pop(ctx);
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
                        child: isSubmitting
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('ACCEPT RESCUE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      ),
                    ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      }
    );
  }
}
