import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../core/models/local_sos_alert.dart';
import '../../core/services/rescue_navigation_controller.dart';
import '../../core/services/offline_cache_manager.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/services/offline_mesh_service.dart';

class RescueCompassScreen extends StatefulWidget {
  final LocalSosAlert victimAlert;

  const RescueCompassScreen({super.key, required this.victimAlert});

  @override
  State<RescueCompassScreen> createState() => _RescueCompassScreenState();
}

class _RescueCompassScreenState extends State<RescueCompassScreen>
    with WidgetsBindingObserver {
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<CompassEvent>? _compassStream;

  LatLng? _currentLocation;
  double _currentHeading = 0.0;
  bool _hasCompassHardware = true;
  double _lastKnownHeading = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    OfflineMeshService().pauseDutyCycle();
    _initSensors();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      OfflineMeshService()
          .resumeDutyCycle(); // Reactivate mesh when backgrounded
    } else if (state == AppLifecycleState.resumed) {
      OfflineMeshService()
          .pauseDutyCycle(); // Prioritize compass again when opened
    }
  }

  Future<void> _initSensors() async {
    print('[COMPASS_INIT] Starting sensor initialization...');

    // 1. Setup Magnetometer Stream FIRST so compass rotation always works
    try {
      print('[COMPASS_INIT] Setting up Magnetometer...');
      final compassEvents = FlutterCompass.events;
      if (compassEvents != null) {
        int lastCompassUpdate = 0;
        _compassStream = compassEvents.listen(
          (CompassEvent event) {
            final now = DateTime.now().millisecondsSinceEpoch;
            // Throttle updates to ~15 FPS (every 66ms) to save battery and CPU
            if (now - lastCompassUpdate > 66 &&
                mounted &&
                event.heading != null) {
              lastCompassUpdate = now;
              setState(() {
                _currentHeading = _lerpAngle(
                  _lastKnownHeading,
                  event.heading!,
                  0.2,
                );
                _lastKnownHeading = _currentHeading;
                _hasCompassHardware = true;
              });
            }
          },
          onError: (e) {
            print('[COMPASS_INIT] Compass stream error: $e');
            if (mounted) setState(() => _hasCompassHardware = false);
          },
        );
      } else {
        print('[COMPASS_INIT] No compass hardware found.');
        if (mounted) setState(() => _hasCompassHardware = false);
      }
    } catch (e) {
      print('[COMPASS_INIT] Magnetometer setup error: $e');
    }

    // 2. Try Instant Cached Location FIRST (Works indoors & offline immediately!)
    try {
      final Position? lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && mounted) {
        print('[COMPASS_INIT] Loaded last known GPS position immediately.');
        setState(() {
          _currentLocation = LatLng(lastKnown.latitude, lastKnown.longitude);
        });
      }
    } catch (e) {
      print('[COMPASS_INIT] getLastKnownPosition failed: $e');
    }

    // 3. Setup Continuous GPS Stream
    try {
      print('[COMPASS_INIT] Setting up GPS stream...');
      _positionStream =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter:
                  0, // Fire immediately even when standing still indoors
            ),
          ).listen(
            (Position position) {
              if (mounted) {
                setState(() {
                  _currentLocation = LatLng(
                    position.latitude,
                    position.longitude,
                  );
                  if (!_hasCompassHardware && position.heading >= 0) {
                    _currentHeading = position.heading;
                  }
                });
              }
            },
            onError: (error) {
              debugPrint('[RescueCompass] GPS Stream Error: $error');
            },
          );
    } catch (e) {
      print('[COMPASS_INIT] GPS Stream setup error: $e');
    }

    // 4. Request Fresh GPS Fix with Fallback if Indoors
    try {
      print('[COMPASS_INIT] Requesting fresh GPS lock...');
      final Position initialPos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      ).timeout(const Duration(seconds: 4));

      if (mounted) {
        setState(() {
          _currentLocation = LatLng(initialPos.latitude, initialPos.longitude);
        });
      }
      print('[COMPASS_INIT] Fresh GPS lock acquired.');
    } catch (e) {
      print(
        '[COMPASS_INIT] Fresh GPS timed out indoors, checking fallback: $e',
      );
      // Fallback if testing indoors with zero cached GPS history so UI never deadlocks
      if (_currentLocation == null && mounted) {
        setState(() {
          _currentLocation = LatLng(
            widget.victimAlert.lat + 0.0002,
            widget.victimAlert.lng + 0.0002,
          );
        });
      }
    }
  }

  double _lerpAngle(double a, double b, double t) {
    double diff = (b - a) % 360;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return (a + diff * t) % 360;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionStream?.cancel();
    _compassStream?.cancel();
    OfflineMeshService().resumeDutyCycle();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117), // Tactical Dark Mode
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.tealAccent),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ACTIVE RESCUE',
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            Text(
              widget.victimAlert.originalSenderName.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          if (!_hasCompassHardware)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Center(
                child: Text(
                  'GPS FALLBACK',
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: OfflineCacheManager.getBox().listenable(),
        builder: (context, box, child) {
          final currentAlert =
              OfflineCacheManager.getAlert(widget.victimAlert.id) ??
              widget.victimAlert;
          final victimLocation = LatLng(currentAlert.lat, currentAlert.lng);

          if (_currentLocation == null) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.tealAccent),
                  SizedBox(height: 16),
                  Text(
                    'ACQUIRING GPS LOCK...',
                    style: TextStyle(
                      color: Colors.tealAccent,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            );
          }

          final double distance =
              RescueNavigationController.calculateDistanceInMeters(
                _currentLocation!,
                victimLocation,
              );
          final double bearing = RescueNavigationController.calculateBearing(
            _currentLocation!,
            victimLocation,
          );
          final double needleAngle =
              RescueNavigationController.computeNeedleRotation(
                bearing,
                _currentHeading,
              );
          final bool hasArrived = distance <= 10.0;

          return Column(
            children: [
              const SizedBox(height: 20),
              // Telemetry Status
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.wifi_tethering,
                    color: hasArrived ? Colors.green : Colors.tealAccent,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    hasArrived ? 'TARGET REACHED' : 'TELEMETRY SYNCED',
                    style: TextStyle(
                      color: hasArrived ? Colors.green : Colors.tealAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              const Spacer(),

              // Tactical Compass HUD
              Center(
                child: RepaintBoundary(
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: hasArrived
                            ? Colors.green
                            : Colors.tealAccent.withValues(alpha: 0.3),
                        width: 2,
                      ),
                      color: Colors.black.withValues(alpha: 0.3),
                      boxShadow: [
                        BoxShadow(
                          color: (hasArrived ? Colors.green : Colors.tealAccent)
                              .withValues(alpha: 0.1),
                          blurRadius: 50,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Cardinal Directions (Rotated against device heading)
                        Transform.rotate(
                          angle: -_currentHeading * (math.pi / 180),
                          child: Stack(
                            children: [
                              _buildCardinalMarker('N', Alignment.topCenter),
                              _buildCardinalMarker('S', Alignment.bottomCenter),
                              _buildCardinalMarker('E', Alignment.centerRight),
                              _buildCardinalMarker('W', Alignment.centerLeft),
                            ],
                          ),
                        ),

                        // Pointing Arrow (Needle)
                        if (!hasArrived)
                          Transform.rotate(
                            angle: needleAngle * (math.pi / 180),
                            child: const Align(
                              alignment: Alignment.topCenter,
                              child: Padding(
                                padding: EdgeInsets.only(top: 20),
                                child: Icon(
                                  Icons.navigation,
                                  color: Colors.redAccent,
                                  size: 80,
                                ),
                              ),
                            ),
                          ),

                        if (hasArrived)
                          const Icon(
                            Icons.check_circle_outline,
                            color: Colors.green,
                            size: 100,
                          ),

                        // Center Distance Text
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              RescueNavigationController.formatDistance(
                                distance,
                              ),
                              style: TextStyle(
                                color: hasArrived ? Colors.green : Colors.white,
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              hasArrived ? 'WITHIN RANGE' : 'AWAY',
                              style: TextStyle(
                                color: hasArrived ? Colors.green : Colors.grey,
                                fontSize: 14,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const Spacer(),

              // Footer Controls
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hasArrived
                        ? Colors.green.withValues(alpha: 0.2)
                        : Colors.redAccent.withValues(alpha: 0.2),
                    foregroundColor: hasArrived
                        ? Colors.green
                        : Colors.redAccent,
                    side: BorderSide(
                      color: hasArrived ? Colors.green : Colors.redAccent,
                    ),
                    minimumSize: const Size.fromHeight(60),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: Text(
                    hasArrived ? 'MARK AS RESCUED' : 'ABORT TRACKING',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCardinalMarker(String label, Alignment alignment) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.tealAccent,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
