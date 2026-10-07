import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../../core/theme/design_system.dart';
import '../../core/auth/auth_manager.dart';
import '../widgets/capsule_button.dart';
import '../../core/services/offline_cache_manager.dart';
import '../../core/state/map_pins_manager.dart';
import '../../core/state/alerts_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/offline_mesh_service.dart';

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: AuthManager.displayName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    HapticFeedback.lightImpact();
    final newName = _nameController.text.trim();
    if (newName.isNotEmpty && newName != AuthManager.displayName) {
      await AuthManager.updateDisplayName(newName);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully'),
            backgroundColor: AppColors.radarGreen,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _copyDeviceId() {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: AuthManager.deviceId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Device ID copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _hardResetData() async {
    HapticFeedback.heavyImpact();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wipe All Disaster Data?'),
        content: const Text('This will purge local keys, encrypted caches, and mesh state. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.emergencyRed),
            child: const Text('Confirm Wipe', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await OfflineCacheManager.clearEntireCache();
    await AlertsManager().clearAll();
    
    // Aggressively wipe any stray SharedPreferences (like ignored pins)
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ignoredSosIds');
    await prefs.remove('alertsHistory'); // Just to be safe
    
    // NUKE_MESH was removed for security reasons
    
    MapPinsManager().setPins([]);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Local Database Wiped. Please restart the app.'),
          backgroundColor: AppColors.emergencyRed,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cleanBackground,
      appBar: AppBar(
        title: Text(
          'PROFILE',
          style: AppTypography.primaryHeader.copyWith(fontSize: 24),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          children: [
            // Header Section
            _buildHeader(),
            const SizedBox(height: 32),

            // Personal Identity Card
            _buildIdentityCard(),
            const SizedBox(height: 24),

            // Device Identification Card
            _buildDeviceCard(),
            const SizedBox(height: 32),

            // Debug Nuke Button
            if (kDebugMode) ...[
              ElevatedButton.icon(
                onPressed: _hardResetData,
                icon: const Icon(Icons.warning, color: Colors.white),
                label: const Text(
                  'DEBUG: Hard Reset Data',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.emergencyRed,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const CircleAvatar(
          radius: 56,
          backgroundColor: AppColors.pitchBlack,
          child: Icon(Icons.person, size: 56, color: Colors.white),
        ),
        const SizedBox(height: 16),
        Text(
          AuthManager.displayName,
          style: AppTypography.primaryHeader.copyWith(fontSize: 28),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.emergencyRed.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.emergencyRed),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.emergencyRed,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'ACTIVE VOLUNTEER',
                style: AppTypography.body.copyWith(
                  color: AppColors.emergencyRed,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIdentityCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Personal Identity',
              style: AppTypography.subtitle.copyWith(fontSize: 16),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              style: AppTypography.body,
              decoration: InputDecoration(
                hintText: 'Enter your display name',
                filled: true,
                fillColor: AppColors.cleanBackground,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.surfaceBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.surfaceBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.pitchBlack),
                ),
              ),
            ),
            const SizedBox(height: 16),
            CapsuleButton(
              text: 'Save Changes',
              onPressed: _saveName,
              style: CapsuleStyle.primary,
              icon: Icons.arrow_forward,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Device Identification',
              style: AppTypography.subtitle.copyWith(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Your anonymous identifier for the crisis network.',
              style: AppTypography.body.copyWith(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.cleanBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      AuthManager.deviceId,
                      style: AppTypography.body.copyWith(
                        fontFamily: 'monospace',
                        color: AppColors.pitchBlack,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20, color: AppColors.pitchBlack),
                    onPressed: _copyDeviceId,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
