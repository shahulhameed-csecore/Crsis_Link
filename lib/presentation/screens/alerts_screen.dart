import 'package:flutter/material.dart';
import 'package:crsis_link_client/crsis_link_client.dart';
import '../../core/theme/design_system.dart';
import '../../core/auth/auth_manager.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  List<SosAlert> _myRescues = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchMyRescues();
  }

  Future<void> _fetchMyRescues() async {
    try {
      final allAlerts = await AuthManager.client.sos.getActiveAlerts();
      final userId = AuthManager.sessionManager.signedInUser?.id;
      
      setState(() {
        _myRescues = allAlerts.where((a) => a.volunteerId == userId && (a.status == 'CLAIMED' || a.status == 'ESCALATED')).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Failed to fetch rescues: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _completeRescue(SosAlert alert) async {
    try {
      await AuthManager.client.sos.completeRescue(alert.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rescue marked as completed. Stay safe!')),
        );
      }
      _fetchMyRescues();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to complete rescue: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('MY RESCUES', style: AppTypography.primaryHeader.copyWith(fontSize: 24)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.pitchBlack))
          : _myRescues.isEmpty
              ? const Center(child: Text('You have no active rescues.', style: AppTypography.body))
              : ListView.separated(
                  padding: const EdgeInsets.all(24),
                  itemCount: _myRescues.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final alert = _myRescues[index];
                    final isEscalated = alert.status == 'ESCALATED';

                    return Card(
                      color: isEscalated ? AppColors.emergencyRed.withValues(alpha: 0.1) : AppColors.radarGreen.withValues(alpha: 0.1),
                      shape: RoundedRectangleBorder(
                        side: BorderSide(
                          color: isEscalated ? AppColors.emergencyRed : AppColors.radarGreen,
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
                                  isEscalated ? Icons.warning_amber_rounded : Icons.health_and_safety,
                                  color: isEscalated ? AppColors.emergencyRed : AppColors.radarGreen,
                                  size: 28,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    isEscalated ? 'ESCALATED SAFETY CHECK' : 'ACTIVE RESCUE',
                                    style: AppTypography.subtitle.copyWith(
                                      color: isEscalated ? AppColors.emergencyRed : AppColors.radarGreen,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              isEscalated 
                                ? 'You have not checked in! Are you safe? Please confirm your rescue status immediately.'
                                : 'Rescue in progress for ${alert.userInfo?.userName ?? "Unknown"}.',
                              style: AppTypography.body,
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton(
                                onPressed: () => _completeRescue(alert),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isEscalated ? AppColors.emergencyRed : AppColors.pitchBlack,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                ),
                                child: Text(
                                  'CONFIRM SAFE / COMPLETE',
                                  style: AppTypography.button,
                                ),
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
