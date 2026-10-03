import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geocoding/geocoding.dart';
import '../../core/theme/design_system.dart';
import '../../core/auth/auth_manager.dart';
import '../../core/state/map_pins_manager.dart';
import '../../core/state/alerts_manager.dart';
import 'main_navigation.dart';
import '../widgets/voice_note_recorder.dart';
import '../widgets/capsule_button.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> with SingleTickerProviderStateMixin {
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
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 5),
        ).timeout(const Duration(seconds: 5));
      } catch (e) {
        // If it times out or fails, fallback to last known position immediately
        position = await Geolocator.getLastKnownPosition();
        
        // If there's no last known position, try one more time with low accuracy (network/cell tower)
        if (position == null) {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
          ).timeout(const Duration(seconds: 5));
        }
      }
      
      if (position == null) {
        throw Exception('Could not determine location after multiple attempts. Please ensure your GPS is active.');
      }
      
      // DOUBLE-TAP FIX: Do NOT reset _isLocating here.
      // Await the modal so _isLocating stays true (button locked) until modal is fully dismissed.
      if (mounted) {
        await _showSosModal(position);
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = e.toString();
        final isPermanent = errorMsg.contains('permanently denied') || errorMsg.contains('disabled');
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isPermanent ? 'Location access is permanently denied. We cannot broadcast your SOS.' : 'Failed to get location: ${errorMsg.replaceAll('Exception: ', '')}'),
            backgroundColor: AppColors.emergencyRed,
            duration: const Duration(seconds: 5),
            action: isPermanent ? SnackBarAction(
              label: 'OPEN SETTINGS',
              textColor: Colors.white,
              onPressed: () {
                errorMsg.contains('disabled') ? Geolocator.openLocationSettings() : Geolocator.openAppSettings();
              },
            ) : null,
          ),
        );
      }
    } finally {
      // Button unlocks ONLY after modal is fully gone (or on error)
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _showSosModal(Position position) async {
    final TextEditingController messageController = TextEditingController();
    final TextEditingController phoneController = TextEditingController();
    bool isSubmitting = false;
    String? pendingAudioUrl;
    bool hasLivePhoto = false;

    return showModalBottomSheet(
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
                  VoiceNoteRecorder(
                    onRecorded: (url) {
                      pendingAudioUrl = url.isEmpty ? null : url;
                    },
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final ImagePicker picker = ImagePicker();
                      final XFile? image = await picker.pickImage(source: ImageSource.camera);
                      if (image != null) {
                        setModalState(() => hasLivePhoto = true);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('Live Photo attached and verified locally!'), backgroundColor: Colors.green),
                          );
                        }
                      }
                    },
                    icon: Icon(hasLivePhoto ? Icons.check_circle : Icons.camera_alt, color: Colors.white),
                    label: Text(hasLivePhoto ? 'Photo Verified' : 'Take Live Photo to Verify (Recommended)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasLivePhoto ? Colors.green : Colors.blueGrey,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
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
                          null,
                          approxLocation,
                        ).timeout(const Duration(seconds: 10));
                        
                        var finalAlert = response.alert;
                        if (hasLivePhoto) {
                          final verified = await AuthManager.client.sos.verifySOS(finalAlert.id!).timeout(const Duration(seconds: 5));
                          if (verified) {
                            finalAlert.isVisuallyVerified = true;
                          }
                        }
                        
                        MapPinsManager().addOrUpdatePin(finalAlert);
                        AlertsManager().addSosAlert(finalAlert);
                        
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(response.notifiedCount == 0 
                                ? 'No one is available near you at the moment. Your request is still active.'
                                : 'SOS Broadcasted successfully!'),
                              backgroundColor: AppColors.emergencyRed,
                              duration: const Duration(seconds: 5),
                            ),
                          );
                          
                          // Bridge to Map Screen automatically
                          MainNavigation.jumpToMap();
                          globalHomeMapKey.currentState?.jumpToCurrentLocation();
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
    // LEAK-P3-02 FIX: Dispose the controller when the modal is dismissed in any way.
    ).whenComplete(() {
      messageController.dispose();
      phoneController.dispose();
    });
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
                          ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 4)
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.touch_app, size: 64, color: Colors.white),
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
