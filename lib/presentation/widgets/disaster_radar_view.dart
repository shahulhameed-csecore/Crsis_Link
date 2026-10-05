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
  late AnimationController _pulseController;
  List<LocalSosAlert> _offlineAlerts = [];

  @override
  void initState() {
    super.initState();
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
    final distanceCalc = const Distance();
    
    // Strictly read REAL LocalSosAlert items and filter out user's own broadcast (< 10m)
    final peerAlerts = _offlineAlerts.where((a) {
      final dist = distanceCalc.as(LengthUnit.Meter, widget.currentLocation, LatLng(a.lat, a.lng));
      return dist > 10;
    }).toList();

    // Find nearest alert for the Tactical HUD
    LocalSosAlert? nearestAlert;
    double nearestDist = double.infinity;
    double nearestBearing = 0.0;
    
    for (var a in peerAlerts) {
      final target = LatLng(a.lat, a.lng);
      final dist = distanceCalc.as(LengthUnit.Meter, widget.currentLocation, target).toDouble();
      if (dist < nearestDist) {
        nearestDist = dist;
        nearestAlert = a;
        nearestBearing = distanceCalc.bearing(widget.currentLocation, target);
      }
    }

    return Container(
      color: const Color(0xFF0D1117), // Tactical Dark Background
      child: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              return SizedBox.expand(
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: RadarPainter(
                        currentLocation: widget.currentLocation,
                        alerts: peerAlerts,
                        pulseValue: _pulseController.value,
                        hasOwnSos: _offlineAlerts.length > peerAlerts.length, 
                      ),
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                    );
                  },
                ),
              );
            },
          ),
          
          // Empty State: Scanning Overlay
          if (peerAlerts.isEmpty)
            Center(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Opacity(
                    opacity: 0.3 + (_pulseController.value * 0.7),
                    child: const Text(
                      "SCANNING LOCAL MESH\nFOR SOS SIGNALS...",
                      style: TextStyle(
                        color: Colors.tealAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.0,
                        height: 1.5,
                        shadows: [
                          Shadow(color: Colors.tealAccent, blurRadius: 10)
                        ]
                      ),
                      textAlign: TextAlign.center,
                    ),
                  );
                },
              ),
            ),
            
          // Tactical Navigation HUD
          if (nearestAlert != null)
            Positioned(
              left: 20,
              right: 20,
              bottom: 40,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.5), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.tealAccent.withValues(alpha: 0.2),
                      blurRadius: 12,
                      spreadRadius: 2,
                    )
                  ],
                ),
                child: Row(
                  children: [
                    // Dynamic rotation arrow pointing towards SOS
                    Transform.rotate(
                      angle: nearestBearing * (math.pi / 180.0),
                      child: const Icon(
                        Icons.arrow_upward,
                        color: Colors.tealAccent,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            nearestAlert.originalSenderName.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${nearestDist.toInt()}m AWAY',
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.tealAccent.withValues(alpha: 0.2),
                        foregroundColor: Colors.tealAccent,
                        side: const BorderSide(color: Colors.tealAccent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Tracking ${nearestAlert!.originalSenderName}...')),
                        );
                      },
                      child: const Text('TRACK'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class RadarPainter extends CustomPainter {
  final LatLng currentLocation;
  final List<LocalSosAlert> alerts;
  final double pulseValue;
  final bool hasOwnSos;
  final Distance distanceCalc = const Distance();

  RadarPainter({
    required this.currentLocation,
    required this.alerts,
    required this.pulseValue,
    required this.hasOwnSos,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
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

    // Concentric Distance Rings
    final ringPaint = Paint()
      ..color = Colors.tealAccent.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final ringPercentages = [0.25, 0.55, 0.85];
    final ringLabels = ['100m', '500m', '1km'];
    
    for (int i = 0; i < ringPercentages.length; i++) {
      final r = maxRadius * ringPercentages[i];
      canvas.drawCircle(center, r, ringPaint);
      
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

    // Cardinal Markers
    _drawCardinalMarker(canvas, 'N', Offset(center.dx - 4, center.dy - maxRadius - 20));
    _drawCardinalMarker(canvas, 'S', Offset(center.dx - 4, center.dy + maxRadius + 8));
    _drawCardinalMarker(canvas, 'E', Offset(center.dx + maxRadius + 8, center.dy - 7));
    _drawCardinalMarker(canvas, 'W', Offset(center.dx - maxRadius - 20, center.dy - 7));

    // Volunteer center dot (Blue)
    canvas.drawCircle(center, 6, Paint()..color = Colors.blue);
    
    // "YOU" Label
    final youPainter = TextPainter(
      text: const TextSpan(
        text: 'YOU',
        style: TextStyle(
          color: Colors.blue,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    youPainter.layout();
    youPainter.paint(canvas, Offset(center.dx - (youPainter.width / 2), center.dy - 20));

    // Own SOS pulse effect
    if (hasOwnSos) {
      final ownPulsePaint = Paint()
        ..color = Colors.redAccent.withValues(alpha: 0.5 * (1 - pulseValue))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 + (pulseValue * 10);
      canvas.drawCircle(center, 12 + (pulseValue * 20), ownPulsePaint);
    } else {
      canvas.drawCircle(center, 12, Paint()..color = Colors.blue.withValues(alpha: 0.3));
    }

    // Pin Rendering for REAL Peer Alerts
    final sosPaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.fill;
      
    final pulsePaint = Paint()
      ..color = Colors.redAccent.withValues(alpha: 0.3 * (1 - pulseValue))
      ..style = PaintingStyle.fill;

    for (var alert in alerts) {
      final target = LatLng(alert.lat, alert.lng);
      final dist = distanceCalc.as(LengthUnit.Meter, currentLocation, target).toDouble();
      final bearing = distanceCalc.bearing(currentLocation, target);
      
      _drawSosPin(
        canvas, center, maxRadius, maxRangeMeters, 
        dist, bearing, 
        alert.originalSenderName,
        sosPaint, pulsePaint,
      );
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
    String senderName,
    Paint sosPaint,
    Paint pulsePaint,
  ) {
    final bearingRad = bearingDegrees * (math.pi / 180.0);
    
    // Scale distance onto the radar radius
    final scale = maxRadius / maxRangeMeters;
    final r = math.min(dist * scale, maxRadius); // Clamp visually
    
    // North is locked to Top
    final dx = center.dx + r * math.sin(bearingRad);
    final dy = center.dy - r * math.cos(bearingRad);
    
    final dotCenter = Offset(dx, dy);

    // Pulsing outer halo
    canvas.drawCircle(dotCenter, 8 + (pulseValue * 15), pulsePaint);
    
    // Glowing red marker
    canvas.drawCircle(dotCenter, 6, sosPaint);
    
    // Real Alert Badge
    final label = 'SOS: $senderName (${dist.toInt()}m)';
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.redAccent, 
          fontSize: 10, 
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(dx - textPainter.width / 2, dy + 12));
  }

  @override
  bool shouldRepaint(RadarPainter oldDelegate) => true; 
}
