import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../core/theme/design_system.dart';
import '../../core/auth/auth_manager.dart';
import '../../core/state/map_pins_manager.dart';
import '../../core/state/alerts_manager.dart';
import 'main_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/offline_mesh_service.dart';
import '../../core/services/offline_cache_manager.dart';
import '../../core/models/local_sos_alert.dart';
import 'package:crsis_link_client/crsis_link_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _handleSosTap() async {
    HapticFeedback.heavyImpact();
    if (_isLocating) return;

    setState(() {
      _isLocating = true;
    });

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
        // Try getting the high-accuracy position first
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 5,
          ),
        ).timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('Error: $e');
        // If it times out or fails, fallback to last known position immediately
        position = await Geolocator.getLastKnownPosition();

        // If there's no last known position, try one more time with low accuracy (network/cell tower)
        position ??= await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
          ),
        ).timeout(const Duration(seconds: 5));
      }

      // INSTANT BROADCAST LOGIC
      if (mounted) {
        String? approxLocation;
          try {
            List<Placemark> placemarks = await Geocoding().placemarkFromCoordinates(
              position.latitude,
              position.longitude,
            ).timeout(const Duration(seconds: 3));
            if (placemarks.isNotEmpty) {
              final place = placemarks.first;
              approxLocation = place.subLocality?.isNotEmpty == true
                  ? place.subLocality
                  : (place.locality?.isNotEmpty == true
                        ? place.locality
                        : place.name);
              if (approxLocation != null && approxLocation.isNotEmpty) {
                approxLocation = 'Emergency in $approxLocation';
              }
            }
          } catch (e) {
            debugPrint('Geocoding failed: $e');
          }

          final prefs = await SharedPreferences.getInstance();
          const secureStorage = FlutterSecureStorage();
          String? securePhone = await secureStorage.read(
            key: 'secure_victim_phone',
          );
          if (securePhone == null) {
            String legacyPhone =
                prefs.getString('phone') ??
                prefs.getString('user_phone') ??
                prefs.getString('phoneNumber') ??
                '';
            if (legacyPhone.isNotEmpty) {
              await secureStorage.write(
                key: 'secure_victim_phone',
                value: legacyPhone,
              );
              await prefs.remove('phone');
              await prefs.remove('user_phone');
              await prefs.remove('phoneNumber');
            }
            securePhone = legacyPhone;
          }
          final victimPhone = securePhone.isNotEmpty
              ? securePhone
              : 'URGENT-NO-NUMBER';

          // STORE: Always save to offline cache first
          final alert = LocalSosAlert(
            id: const Uuid().v4(),
            lat: position.latitude,
            lng: position.longitude,
            message: 'CRITICAL EMERGENCY: Immediate assistance required. (Instant SOS)',
            victimPhone: victimPhone,
            approximateLocationText: approxLocation,
            originalDeviceId: AuthManager.deviceId,
            originalSenderName: AuthManager.displayName,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          );
          await OfflineCacheManager.saveAlert(alert);

          if (OfflineMeshService().isOfflineModeEnabled) {
            await OfflineMeshService().broadcastNewAlert(alert);

            final localUiAlert = SosAlert(
              id: alert.id.hashCode, // Unique temporary ID
              clientAlertId: alert.id,
              deviceId: AuthManager.deviceId,
              senderName: AuthManager.displayName,
              latitude: alert.lat,
              longitude: alert.lng,
              message: alert.message,
              status: 'OPEN',
              victimPhone: alert.victimPhone,
              approximateLocationText: alert.approximateLocationText,
              timestamp: DateTime.now(),
              isActive: true,
            );
            MapPinsManager().addOrUpdatePin(localUiAlert);
            AlertsManager().addSosAlert(localUiAlert);

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Offline: SOS saved and broadcasting to nearby devices.',
                  ),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 5),
                ),
              );
              MainNavigation.jumpToMap();
              globalHomeMapKey.currentState?.jumpToCurrentLocation();
            }
            return;
          }

          // FORWARD: Attempt to send to server
          try {
            final response = await AuthManager.client.sos
                .broadcastSos(
                  AuthManager.deviceId,
                  AuthManager.displayName,
                  position.latitude,
                  position.longitude,
                  alert.message,
                  null,
                  victimPhone,
                  null,
                  approxLocation,
                  alert.id, // clientAlertId for idempotency
                )
                .timeout(const Duration(seconds: 10));

            // Mark as synced upon success
            await OfflineCacheManager.markAsSynced(alert.id);

            final finalAlert = response.alert;
            MapPinsManager().addOrUpdatePin(finalAlert);
            AlertsManager().addSosAlert(finalAlert);

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    response.notifiedCount == 0
                        ? 'No one is available near you at the moment. Your request is still active.'
                        : 'SOS Broadcasted successfully!',
                  ),
                  backgroundColor: AppColors.emergencyRed,
                  duration: const Duration(seconds: 5),
                ),
              );

              MainNavigation.jumpToMap();
              globalHomeMapKey.currentState?.jumpToCurrentLocation();
            }
          } catch (e) {
            debugPrint('SOS Broadcast network failed, relying on store-and-forward: $e');
            
            // Fallback: update local UI and rely on NetworkSyncManager
            final localUiAlert = SosAlert(
              id: alert.id.hashCode,
              clientAlertId: alert.id,
              deviceId: AuthManager.deviceId,
              senderName: AuthManager.displayName,
              latitude: alert.lat,
              longitude: alert.lng,
              message: alert.message,
              status: 'OPEN',
              victimPhone: alert.victimPhone,
              approximateLocationText: alert.approximateLocationText,
              timestamp: DateTime.now(),
              isActive: true,
            );
            MapPinsManager().addOrUpdatePin(localUiAlert);
            AlertsManager().addSosAlert(localUiAlert);

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Saved offline. Will sync to server when connection is restored.',
                  ),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 5),
                ),
              );
              MainNavigation.jumpToMap();
              globalHomeMapKey.currentState?.jumpToCurrentLocation();
            }
          }
      }
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) {
        final errorMsg = e.toString();
        final isPermanent =
            errorMsg.contains('permanently denied') ||
            errorMsg.contains('disabled');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isPermanent
                  ? 'Location access is permanently denied. We cannot broadcast your SOS.'
                  : 'Failed to get location: ${errorMsg.replaceAll('Exception: ', '')}',
            ),
            backgroundColor: AppColors.emergencyRed,
            duration: const Duration(seconds: 5),
            action: isPermanent
                ? SnackBarAction(
                    label: 'OPEN SETTINGS',
                    textColor: Colors.white,
                    onPressed: () {
                      errorMsg.contains('disabled')
                          ? Geolocator.openLocationSettings()
                          : Geolocator.openAppSettings();
                    },
                  )
                : null,
          ),
        );
      }
    } finally {
      // Button unlocks ONLY after modal is fully gone (or on error)
      if (mounted) setState(() => _isLocating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pitchBlack,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'CRISIS LINK',
                style: AppTypography.primaryHeader.copyWith(
                  color: Colors.white,
                  fontSize: 28,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Are you in an emergency?',
                style: AppTypography.body.copyWith(
                  color: Colors.grey,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 64),
              GestureDetector(
                onTap: _handleSosTap,
                child: ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      color: AppColors.emergencyRed,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.emergencyRed.withValues(alpha: 0.5),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: Center(
                      child: _isLocating
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 4,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Broadcasting...',
                                  style: AppTypography.primaryHeader.copyWith(
                                    color: Colors.white,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.touch_app,
                                  size: 64,
                                  color: Colors.white,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'TAP FOR\nEMERGENCY',
                                  textAlign: TextAlign.center,
                                  style: AppTypography.primaryHeader.copyWith(
                                    color: Colors.white,
                                    fontSize: 22,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 64),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'Tapping this button will instantly grab your GPS location and broadcast a high-priority distress signal to nearby volunteers.',
                  textAlign: TextAlign.center,
                  style: AppTypography.body.copyWith(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
