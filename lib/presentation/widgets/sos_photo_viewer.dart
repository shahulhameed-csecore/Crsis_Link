import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/theme/design_system.dart';

/// Universal photo renderer widget for SOS alerts.
/// Reliably handles Base64 Data URIs ('data:image/jpeg;base64,...'), raw base64,
/// and sanitized HTTPS network URLs with loading spinners and error fallbacks.
class SosPhotoViewer extends StatelessWidget {
  final String photoUrl;
  final double? height;
  final double? width;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final bool enableFullScreen;

  const SosPhotoViewer({
    super.key,
    required this.photoUrl,
    this.height = 220,
    this.width = double.infinity,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.enableFullScreen = true,
  });

  bool get _isBase64 {
    return photoUrl.startsWith('data:image') ||
        (!photoUrl.startsWith('http://') &&
            !photoUrl.startsWith('https://') &&
            photoUrl.length > 100);
  }

  Uint8List? _decodeBase64() {
    try {
      final base64Content =
          photoUrl.contains(',') ? photoUrl.split(',').last : photoUrl;
      return base64Decode(base64Content.trim());
    } catch (e) {
      debugPrint('Failed to decode base64 SOS photo: $e');
      return null;
    }
  }

  String _sanitizeUrl(String url) {
    return url
        .replaceAll('\${public_host}', 'crsis-link-api.onrender.com')
        .replaceAll('\$%7Bpublic_host%7D', 'crsis-link-api.onrender.com')
        .replaceAll('http://', 'https://');
  }

  void _openFullScreen(BuildContext context) {
    if (!enableFullScreen) return;

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) {
        Widget imageWidget;
        if (_isBase64) {
          final bytes = _decodeBase64();
          if (bytes != null) {
            imageWidget = Image.memory(bytes, fit: BoxFit.contain);
          } else {
            imageWidget = _buildErrorWidget();
          }
        } else {
          imageWidget = Image.network(
            _sanitizeUrl(photoUrl),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => _buildErrorWidget(),
          );
        }

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(12),
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                child: Center(child: imageWidget),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.of(ctx).pop(),
                  tooltip: 'Close',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(12);

    Widget imageContent;

    if (_isBase64) {
      final bytes = _decodeBase64();
      if (bytes != null) {
        imageContent = Image.memory(
          bytes,
          height: height,
          width: width,
          fit: fit,
          errorBuilder: (context, error, stackTrace) =>
              _buildErrorWidget(radius),
        );
      } else {
        imageContent = _buildErrorWidget(radius);
      }
    } else {
      final sanitized = _sanitizeUrl(photoUrl);
      imageContent = Image.network(
        sanitized,
        height: height,
        width: width,
        fit: fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            height: height,
            width: width,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.1),
              borderRadius: radius,
            ),
            child: const Center(
              child: CircularProgressIndicator(
                color: AppColors.emergencyRed,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) =>
            _buildErrorWidget(radius),
      );
    }

    final clipped = ClipRRect(
      borderRadius: radius,
      child: imageContent,
    );

    if (enableFullScreen) {
      return GestureDetector(
        onTap: () => _openFullScreen(context),
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            clipped,
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.fullscreen, color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
      );
    }

    return clipped;
  }

  Widget _buildErrorWidget([BorderRadius? radius]) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: radius ?? BorderRadius.circular(12),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image, color: Colors.grey, size: 40),
            SizedBox(height: 6),
            Text(
              'Unable to load photo',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
