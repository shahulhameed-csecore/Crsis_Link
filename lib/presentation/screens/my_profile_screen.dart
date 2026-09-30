import 'package:flutter/material.dart';
import '../../core/theme/design_system.dart';
import '../../core/auth/auth_manager.dart';
import '../screens/auth/login_screen.dart';

class MyProfileScreen extends StatelessWidget {
  const MyProfileScreen({super.key});

  Future<void> _handleLogout(BuildContext context) async {
    try {
      // Force clear local tokens first so we don't get stuck if the server rejects it
      await AuthManager.client.authenticationKeyManager?.remove();
      await AuthManager.sessionManager.signOutDevice();
    } catch (e) {
      debugPrint('Server logout threw an error, but local session cleared: $e');
    }

    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (Route<dynamic> route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthManager.sessionManager.signedInUser;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('PROFILE', style: AppTypography.primaryHeader.copyWith(fontSize: 24)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const CircleAvatar(
              radius: 50,
              backgroundColor: AppColors.pitchBlack,
              child: Icon(Icons.person, size: 50, color: Colors.white),
            ),
            const SizedBox(height: 24),
            Text(
              user?.userName ?? 'GUEST USER', 
              style: AppTypography.primaryHeader,
            ),
            const SizedBox(height: 8),
            Text(
              user?.email ?? 'No email linked', 
              style: AppTypography.body.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                    'ACTIVE',
                    style: AppTypography.body.copyWith(
                      color: AppColors.emergencyRed,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),
            
            // Log Out Button (Prominent, High-Contrast)
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () => _handleLogout(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.emergencyRed,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                  elevation: 4,
                  shadowColor: AppColors.emergencyRed.withValues(alpha: 0.5),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.power_settings_new, size: 24),
                    SizedBox(width: 12),
                    Text(
                      'LOG OUT',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
