import 'package:flutter/material.dart';
import '../../core/theme/design_system.dart';

class CapsulePillButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const CapsulePillButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.pitchBlack,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(50),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: AppTypography.subtitle.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.arrow_forward_rounded,
              color: AppColors.pitchBlack,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

class SosButton extends StatelessWidget {
  final VoidCallback onPressed;
  
  const SosButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.emergencyRed,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(50),
        ),
      ),
      child: Text(
        'SOS',
        style: AppTypography.primaryHeader.copyWith(
          color: Colors.white,
          fontSize: 32,
        ),
      ),
    );
  }
}
