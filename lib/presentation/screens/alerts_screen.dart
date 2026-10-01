import 'package:flutter/material.dart';
import '../../core/theme/design_system.dart';
import '../../core/state/alerts_manager.dart';
import 'package:intl/intl.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  void _update() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    AlertsManager().addListener(_update);
  }

  @override
  void dispose() {
    AlertsManager().removeListener(_update);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifications = AlertsManager().notifications;

    return Scaffold(
      appBar: AppBar(
        title: Text('ALERTS FEED', style: AppTypography.primaryHeader.copyWith(fontSize: 24)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: notifications.isEmpty
          ? Center(child: Text('No recent alerts.', style: AppTypography.body))
          : ListView.separated(
              padding: const EdgeInsets.all(24),
              itemCount: notifications.length,
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final alert = notifications[index];
                
                return Card(
                  color: alert.isRescue ? AppColors.radarGreen.withValues(alpha: 0.1) : AppColors.emergencyRed.withValues(alpha: 0.1),
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      color: alert.isRescue ? AppColors.radarGreen : AppColors.emergencyRed,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              alert.isRescue ? Icons.health_and_safety : Icons.warning_amber_rounded,
                              color: alert.isRescue ? AppColors.radarGreen : AppColors.emergencyRed,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                alert.title,
                                style: AppTypography.subtitle.copyWith(
                                  color: alert.isRescue ? AppColors.radarGreen : AppColors.emergencyRed,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          alert.description,
                          style: AppTypography.body.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            DateFormat.jm().format(alert.timestamp),
                            style: AppTypography.body.copyWith(color: Colors.grey, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
