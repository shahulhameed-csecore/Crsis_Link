import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../core/services/offline_cache_manager.dart';
import '../../core/models/local_sos_alert.dart';

class DisasterRadarView extends StatefulWidget {
  final LatLng currentLocation;

  const DisasterRadarView({super.key, required this.currentLocation});

  @override
  State<DisasterRadarView> createState() => _DisasterRadarViewState();
}

class _DisasterRadarViewState extends State<DisasterRadarView> with SingleTickerProviderStateMixin {
  late AnimationController _sweepController;
  List<LocalSosAlert> _offlineAlerts = [];

  @override
  void initState() {
    super.initState();
    _sweepController = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
    _loadAlerts();
  }

  void _loadAlerts() {
    // Fetches all unsynced alerts stored by the mesh network locally
    setState(() {
      _offlineAlerts = OfflineCacheManager.getUnsyncedAlerts();
    });
  }

  @override
  void dispose() {
    _sweepController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D1117), // Tactical Dark Background
      child: AnimatedBuilder(
        animation: _sweepController,
        builder: (context, child) {
          return CustomPaint(
            painter: RadarPainter(
              currentLocation: widget.currentLocation,
              alerts: _offlineAlerts,
              sweepAngle: _sweepController.value * 2 * math.pi,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class RadarPainter extends CustomPainter {
  final LatLng currentLocation;
  final List<LocalSosAlert> alerts;
  final double sweepAngle;
  final Distance distanceCalc = const Distance();

  RadarPainter({
    required this.currentLocation,
    required this.alerts,
    required this.sweepAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) / 2 * 0.9;

    // Background
    final bgPaint = Paint()..color = const Color(0xFF0D1117);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Crosshairs
    final gridPaint = Paint()
      ..color = Colors.green.withOpacity(0.3)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), gridPaint);
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), gridPaint);

    // Concentric rings (100m, 500m, 1000m)
    final double scale = maxRadius / 1000.0;
    final ringPaint = Paint()
      ..color = Colors.green.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final rings = [100.0, 500.0, 1000.0];
    for (var r in rings) {
      canvas.drawCircle(center, r * scale, ringPaint);
      
      // Range Label
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${r.toInt()}m',
          style: TextStyle(color: Colors.green.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(center.dx + 5, center.dy - (r * scale) - 15));
    }

    // Radar Sweep Cone
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.green.withOpacity(0.0),
          Colors.green.withOpacity(0.5),
          Colors.green.withOpacity(0.8),
        ],
        stops: const [0.0, 0.95, 1.0],
        startAngle: 0.0,
        endAngle: 2 * math.pi,
        transform: GradientRotation(sweepAngle - math.pi / 2),
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius))
      ..style = PaintingStyle.fill;
    
    // Draw sweeping arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: maxRadius),
      sweepAngle - math.pi / 2 - math.pi / 4, // Trail length
      math.pi / 4,
      true,
      sweepPaint,
    );

    // Volunteer center dot (Blue)
    canvas.drawCircle(center, 6, Paint()..color = Colors.blue);
    canvas.drawCircle(center, 12, Paint()..color = Colors.blue.withOpacity(0.3));

    // Offline SOS alerts (Red Dots)
    final sosPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    for (var alert in alerts) {
      final target = LatLng(alert.lat, alert.lng);
      final dist = distanceCalc.as(LengthUnit.Meter, currentLocation, target);
      final bearing = distanceCalc.bearing(currentLocation, target); // Bearing in degrees
      
      if (dist <= 1500) { // Draw anything within 1.5km
        final bearingRad = bearing * (math.pi / 180.0);
        
        // Clamp visually to radar bounds if slightly over 1km but under 1.5km
        final r = math.min(dist * scale, maxRadius); 
        
        // 0 degrees is North (UP)
        final dx = center.dx + r * math.sin(bearingRad);
        final dy = center.dy - r * math.cos(bearingRad);
        
        // Draw glowing red dot
        canvas.drawCircle(Offset(dx, dy), 12, Paint()..color = Colors.red.withOpacity(0.4));
        canvas.drawCircle(Offset(dx, dy), 6, sosPaint);
        
        // Draw exact distance label under the dot
        final label = '${dist.toInt()}m';
        final textPainter = TextPainter(
          text: TextSpan(
            text: label,
            style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(dx - textPainter.width / 2, dy + 10));
      }
    }
  }

  @override
  bool shouldRepaint(RadarPainter oldDelegate) => true; // Always repaint for sweep animation
}
