import 'dart:async';
import 'package:flutter/material.dart';
import 'package:crsis_link_client/crsis_link_client.dart';
import '../../core/theme/design_system.dart';
import '../../core/state/alerts_manager.dart';
import 'package:latlong2/latlong.dart';
import 'main_navigation.dart';
import '../../core/auth/auth_manager.dart';
import '../../core/state/map_pins_manager.dart';
import '../widgets/sos_details_bottom_sheet.dart';
import '../widgets/sos_photo_viewer.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  Timer? _pollingTimer;
  SosAlert? _myLatestSos;

  @override
  void initState() {
    super.initState();
    MapPinsManager().addListener(_onPinsChanged);
    _fetchLatestSOS();
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchLatestSOS();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    MapPinsManager().removeListener(_onPinsChanged);
    super.dispose();
  }

  Future<void> _fetchLatestSOS() async {
    try {
      final sos = await AuthManager.client.sos.getMyActiveSos(AuthManager.deviceId);
      if (mounted) {
        setState(() {
          _myLatestSos = sos;
        });
      }
    } catch (e) {
      debugPrint('Error fetching SOS: $e');
    }
  }

  void _onPinsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  String _timeAgo(DateTime d) {
    Duration diff = DateTime.now().difference(d);
    if (diff.inDays > 1) return '${diff.inDays} days ago';
    if (diff.inDays == 1) return '1 day ago';
    if (diff.inHours > 1) return '${diff.inHours} hrs ago';
    if (diff.inHours == 1) return '1 hr ago';
    if (diff.inMinutes > 1) return '${diff.inMinutes} mins ago';
    if (diff.inMinutes == 1) return '1 min ago';
    return 'Just now';
  }

  Widget _getIconForType(AlertType type) {
    switch (type) {
      case AlertType.sos:
        return const Icon(Icons.emergency, color: AppColors.emergencyRed, size: 28);
      case AlertType.accepted:
        return const Icon(Icons.check_circle, color: AppColors.radarGreen, size: 28);
      case AlertType.resolved:
        return const Icon(Icons.check_circle_outline, color: Colors.grey, size: 28);
      case AlertType.ignored:
        return const Icon(Icons.visibility_off, color: Colors.grey, size: 28);
    }
  }

  void _handleAlertTap(AlertNotification alert) {
    if (alert.latitude != null && alert.longitude != null) {
      MainNavigation.jumpToMap();
      Future.delayed(const Duration(milliseconds: 300), () {
        globalHomeMapKey.currentState?.panTo(LatLng(alert.latitude!, alert.longitude!));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cleanBackground,
      appBar: AppBar(
        title: Text('ALERTS FEED', style: AppTypography.primaryHeader.copyWith(fontSize: 22, color: AppColors.pitchBlack)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _fetchLatestSOS,
        child: ValueListenableBuilder<List<AlertNotification>>(
          valueListenable: AlertsManager(),
          builder: (context, notifications, child) {
            return ListView(
              padding: const EdgeInsets.all(24),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (_myLatestSos != null)
                  GestureDetector(
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: AppColors.pitchBlack,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                        ),
                        isScrollControlled: true,
                        builder: (ctx) => SosDetailsBottomSheet(
                          alert: _myLatestSos!,
                          isOwnPin: true,
                          onResolve: () {
                            setState(() {
                              _myLatestSos = null;
                            });
                            _fetchLatestSOS();
                          },
                        ),
                      );
                    },
                    child: _myLatestSos!.volunteerDeviceId == null
                        ? Container(
                            margin: const EdgeInsets.only(bottom: 24),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(color: Colors.orange, strokeWidth: 2.5),
                                    ),
                                    const SizedBox(width: 14),
                                    const Expanded(
                                      child: Text(
                                        'Searching for nearby rescuers...',
                                        style: TextStyle(color: Colors.orange, fontSize: 16, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const Icon(Icons.touch_app, color: Colors.orange, size: 20),
                                  ],
                                ),
                                if (_myLatestSos!.message != null && _myLatestSos!.message!.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    _myLatestSos!.message!,
                                    style: const TextStyle(color: Colors.white, fontSize: 14),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                if (_myLatestSos!.photoUrl != null && _myLatestSos!.photoUrl!.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      SosPhotoViewer(
                                        photoUrl: _myLatestSos!.photoUrl!,
                                        height: 56,
                                        width: 56,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      const SizedBox(width: 10),
                                      const Text(
                                        'Attached Photo (Tap to view details)',
                                        style: TextStyle(color: Colors.grey, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          )
                        : Container(
                            margin: const EdgeInsets.only(bottom: 24),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFF198754), width: 1.5),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Icon(Icons.verified_user, color: Color(0xFF0F5132), size: 40),
                                const SizedBox(height: 8),
                                const Text('RESCUER ASSIGNED!', style: TextStyle(color: Color(0xFF0F5132), fontSize: 16, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F5132),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _myLatestSos!.verificationPin ?? '----',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 4.0,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Give this PIN to your rescuer when they call or arrive.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Color(0xFF1E293B), fontSize: 13),
                                ),
                                if (_myLatestSos!.photoUrl != null && _myLatestSos!.photoUrl!.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SosPhotoViewer(
                                        photoUrl: _myLatestSos!.photoUrl!,
                                        height: 50,
                                        width: 50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      const SizedBox(width: 10),
                                      const Text(
                                        'Tap card to view SOS details',
                                        style: TextStyle(color: Color(0xFF0F5132), fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                  ),
                
                if (notifications.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.security, size: 80, color: AppColors.pitchBlack.withValues(alpha: 0.1)),
                          const SizedBox(height: 16),
                          Text('No active alerts nearby', style: AppTypography.subtitle.copyWith(color: Colors.grey)),
                        ],
                      ),
                    ),
                  )
                else
                  ...notifications.map((alert) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: GestureDetector(
                      onTap: () => _handleAlertTap(alert),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceCards,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.surfaceBorder, width: 1),
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _getIconForType(alert.type),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        alert.title,
                                        style: AppTypography.subtitle.copyWith(
                                          color: AppColors.pitchBlack,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        alert.description,
                                        style: AppTypography.body.copyWith(
                                          color: Colors.grey.shade700,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                _timeAgo(alert.timestamp),
                                style: AppTypography.body.copyWith(
                                  color: Colors.grey.shade500,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )),
              ],
            );
          },
        ),
      ),
    );
  }
}
