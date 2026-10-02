import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/design_system.dart';

enum CapsuleStyle { primary, emergency, secondary }

class CapsuleButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final CapsuleStyle style;
  final IconData? icon;
  final bool isLoading;

  const CapsuleButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.style = CapsuleStyle.primary,
    this.icon,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color textColor;
    BorderSide borderSide = BorderSide.none;

    switch (style) {
      case CapsuleStyle.primary:
        backgroundColor = AppColors.pitchBlack;
        textColor = Colors.white;
        break;
      case CapsuleStyle.emergency:
        backgroundColor = AppColors.emergencyRed;
        textColor = Colors.white;
        break;
      case CapsuleStyle.secondary:
        backgroundColor = AppColors.surfaceCards;
        textColor = AppColors.pitchBlack;
        borderSide = const BorderSide(color: AppColors.surfaceBorder, width: 1);
        break;
    }

    return SizedBox(
      height: 54,
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: textColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
            side: borderSide,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24),
        ),
        onPressed: () {
          if (isLoading) return;
          HapticFeedback.lightImpact();
          onPressed();
        },
        child: isLoading
            ? SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  color: textColor,
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    text,
                    style: AppTypography.button.copyWith(
                      color: textColor,
                      fontSize: 16,
                    ),
                  ),
                  if (icon != null) ...[
                    const SizedBox(width: 8),
                    Icon(icon, size: 20, color: textColor),
                  ],
                ],
              ),
      ),
    );
  }
}
