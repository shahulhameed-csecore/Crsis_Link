import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../core/services/offline_cache_manager.dart';
import '../../core/models/local_sos_alert.dart';
import '../../core/auth/auth_manager.dart';

class DisasterRadarView extends StatefulWidget {
  final LatLng currentLocation;

  const DisasterRadarView({super.key, required this.currentLocation});

  @override
  State<DisasterRadarView> createState() => _DisasterRadarViewState();
}

class _DisasterRadarViewState extends State<DisasterRadarView> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  List<LocalSosAlert> _offlineAlerts = [];

  @override
  void initState() {
    super.initState();
    // 2-second pulse animation loop
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _loadAlerts();
  }

  void _loadAlerts() {
    setState(() {
      _offlineAlerts = OfflineCacheManager.getUnsyncedAlerts();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D1117), // Tactical Dark Background
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Guaranteed Fullscreen Canvas Layout
          return SizedBox.expand(
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return CustomPaint(
                  painter: RadarPainter(
                    currentLocation: widget.currentLocation,
                    alerts: _offlineAlerts,
                    pulseValue: _pulseController.value,
                  ),
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class RadarPainter extends CustomPainter {
  final LatLng currentLocation;
  final List<LocalSosAlert> alerts;
  final double pulseValue;
  final Distance distanceCalc = const Distance();

  RadarPainter({
    required this.currentLocation,
    required this.alerts,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Dynamic max radius relative to screen size constraints
    final maxRadius = math.min(size.width, size.height) / 2 * 0.9;
    final maxRangeMeters = 1200.0;

    // Background Base
    final bgPaint = Paint()..color = const Color(0xFF0D1117);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Crosshairs
    final gridPaint = Paint()
      ..color = Colors.tealAccent.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), gridPaint);
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), gridPaint);

    // Concentric Distance Rings (25%, 55%, 85%)
    final ringPaint = Paint()
      ..color = Colors.tealAccent.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final ringPercentages = [0.25, 0.55, 0.85];
    final ringLabels = ['100m', '500m', '1km'];
    
    for (int i = 0; i < ringPercentages.length; i++) {
      final r = maxRadius * ringPercentages[i];
      canvas.drawCircle(center, r, ringPaint);
      
      // Range Label
      final textPainter = TextPainter(
        text: TextSpan(
          text: ringLabels[i],
          style: TextStyle(
            color: Colors.tealAccent.withValues(alpha: 0.7),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(center.dx + 5, center.dy - r - 15));
    }

    // Cardinal Markers (N, E, S, W)
    _drawCardinalMarker(canvas, 'N', Offset(center.dx - 4, center.dy - maxRadius - 20));
    _drawCardinalMarker(canvas, 'S', Offset(center.dx - 4, center.dy + maxRadius + 8));
    _drawCardinalMarker(canvas, 'E', Offset(center.dx + maxRadius + 8, center.dy - 7));
    _drawCardinalMarker(canvas, 'W', Offset(center.dx - maxRadius - 20, center.dy - 7));

    // Pin Rendering & Pulse Animation
    bool hasOwnSos = false;
    int peerCount = 0;

    final sosPaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.fill;
      
    final pulsePaint = Paint()
      ..color = Colors.redAccent.withValues(alpha: 0.3 * (1 - pulseValue))
      ..style = PaintingStyle.fill;

    for (var alert in alerts) {
      final target = LatLng(alert.lat, alert.lng);
      final dist = distanceCalc.as(LengthUnit.Meter, currentLocation, target);
      
      // Filter out user's own local pin that spawns exactly at their GPS (0m)
      if (dist <= 10) {
        hasOwnSos = true; // Flag for own SOS pulse
      } else {
        peerCount++;
        _drawSosPin(
          canvas, center, maxRadius, maxRangeMeters, 
          dist.toDouble(), distanceCalc.bearing(currentLocation, target), 
          sosPaint, pulsePaint,
        );
      }
    }

    // Demo Mode Toggle (Crucial for Live Demos)
    if (peerCount == 0) {
      // Mock demo beacon 280m to the North-East (45 degrees)
      _drawSosPin(
        canvas, center, maxRadius, maxRangeMeters, 
        280.0, 45.0, 
        sosPaint, pulsePaint,
      );
    }

    // Volunteer center dot (Blue) with optional own SOS pulse
    canvas.drawCircle(center, 6, Paint()..color = Colors.blue);
    
    if (hasOwnSos) {
      final ownPulsePaint = Paint()
        ..color = Colors.redAccent.withValues(alpha: 0.5 * (1 - pulseValue))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 + (pulseValue * 10);
      canvas.drawCircle(center, 12 + (pulseValue * 20), ownPulsePaint);
    } else {
      canvas.drawCircle(center, 12, Paint()..color = Colors.blue.withValues(alpha: 0.3));
    }
  }

  void _drawCardinalMarker(Canvas canvas, String label, Offset position) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.tealAccent,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, position);
  }

  void _drawSosPin(
    Canvas canvas, 
    Offset center, 
    double maxRadius, 
    double maxRangeMeters,
    double dist, 
    double bearingDegrees,
    Paint sosPaint,
    Paint pulsePaint,
  ) {
    final bearingRad = bearingDegrees * (math.pi / 180.0);
    
    // Scale distance onto the radar radius (max range = 1,200m)
    final scale = maxRadius / maxRangeMeters;
    final r = math.min(dist * scale, maxRadius); // Clamp to max radius visually
    
    // North is locked to Top (0 degrees = UP)
    final dx = center.dx + r * math.sin(bearingRad);
    final dy = center.dy - r * math.cos(bearingRad);
    
    final dotCenter = Offset(dx, dy);

    // Draw pulsing outer halo
    canvas.drawCircle(dotCenter, 8 + (pulseValue * 15), pulsePaint);
    
    // Draw glowing red marker
    canvas.drawCircle(dotCenter, 6, sosPaint);
    
    // Draw exact distance label under the dot
    final label = '${dist.toInt()}m';
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.redAccent, 
          fontSize: 12, 
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(dx - textPainter.width / 2, dy + 12));
  }

  @override
  bool shouldRepaint(RadarPainter oldDelegate) => true; // Always repaint for pulse animation
}
