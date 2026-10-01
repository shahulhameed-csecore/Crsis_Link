import 'package:flutter/material.dart';
import '../../core/theme/design_system.dart';
import '../../core/state/alerts_manager.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'main_navigation.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
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
      body: ValueListenableBuilder<List<AlertNotification>>(
        valueListenable: AlertsManager(),
        builder: (context, notifications, child) {
          return notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.security, size: 80, color: AppColors.pitchBlack.withValues(alpha: 0.1)),
                      const SizedBox(height: 16),
                      Text('No active alerts nearby', style: AppTypography.subtitle.copyWith(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(24),
                  itemCount: notifications.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final alert = notifications[index];
                    
                    return GestureDetector(
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
                    );
                  },
                );
        },
      ),
    );
  }
}
