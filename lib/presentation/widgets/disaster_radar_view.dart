import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../core/services/offline_cache_manager.dart';
import '../../core/models/local_sos_alert.dart';
import '../../core/state/map_pins_manager.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/auth/auth_manager.dart';
import '../screens/rescue_compass_screen.dart';

class CachedRadarPin {
  final Offset offset;
  final double distance;
  final String label;
  final bool isWithinRange;
  final TextPainter textPainter;

  CachedRadarPin({
    required this.offset,
    required this.distance,
    required this.label,
    required this.isWithinRange,
    required this.textPainter,
  });
}

class DisasterRadarView extends StatefulWidget {
  final LatLng currentLocation;

  const DisasterRadarView({super.key, required this.currentLocation});

  @override
  State<DisasterRadarView> createState() => _DisasterRadarViewState();
}

class _DisasterRadarViewState extends State<DisasterRadarView> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  List<LocalSosAlert> _offlineAlerts = [];
  List<CachedRadarPin> _cachedPins = [];
  
  // Cache for static elements
  final List<TextPainter> _ringTextPainters = [];
  final Map<String, TextPainter> _cardinalTextPainters = {};
  TextPainter? _youTextPainter;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    MapPinsManager().addListener(_loadAlerts);
    _loadAlerts();
    _initStaticTextPainters();
  }

  void _initStaticTextPainters() {
    final ringLabels = ['100m', '500m', '1km'];
    for (var label in ringLabels) {
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.tealAccent.withValues(alpha: 0.7),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      _ringTextPainters.add(tp);
    }

    for (var label in ['N', 'S', 'E', 'W']) {
      final tp = TextPainter(
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
      tp.layout();
      _cardinalTextPainters[label] = tp;
    }

    _youTextPainter = TextPainter(
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
    _youTextPainter!.layout();
  }

  void _loadAlerts() {
    setState(() {
      _offlineAlerts = OfflineCacheManager.getUnsyncedAlerts();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    MapPinsManager().removeListener(_loadAlerts);
    super.dispose();
  }

  void _recalculatePinProjections(Size size, List<LocalSosAlert> peerAlerts) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) / 2 * 0.9;
    final maxRangeMeters = 1200.0;
    final distanceCalc = const Distance();

    List<CachedRadarPin> newPins = [];

    for (var alert in peerAlerts) {
      final target = LatLng(alert.lat, alert.lng);
      final dist = distanceCalc.as(LengthUnit.Meter, widget.currentLocation, target).toDouble();
      final bearingDegrees = distanceCalc.bearing(widget.currentLocation, target);
      final bearingRad = bearingDegrees * (math.pi / 180.0);
      
      final scale = maxRadius / maxRangeMeters;
      final r = math.min(dist * scale, maxRadius); 
      
      final dx = center.dx + r * math.sin(bearingRad);
      final dy = center.dy - r * math.cos(bearingRad);
      
      final label = 'SOS: ${alert.originalSenderName} (${dist.toInt()}m)';
      
      final tp = TextPainter(
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
      tp.layout();

      newPins.add(CachedRadarPin(
        offset: Offset(dx, dy),
        distance: dist,
        label: label,
        isWithinRange: dist <= maxRangeMeters,
        textPainter: tp,
      ));
    }
    _cachedPins = newPins;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: OfflineCacheManager.getBox().listenable(),
      builder: (context, box, _) {
        final distanceCalc = const Distance();
        final rawAlerts = OfflineCacheManager.getUnsyncedAlerts();
        
        final peerAlerts = rawAlerts.where((a) {
          return a.originalDeviceId != AuthManager.deviceId;
        }).toList();

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
          color: const Color(0xFF0D1117), 
          child: Stack(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, constraints.maxHeight);
                  _recalculatePinProjections(size, peerAlerts);

                  return SizedBox.expand(
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return CustomPaint(
                          painter: RadarPainter(
                            cachedPins: _cachedPins,
                            pulseValue: _pulseController.value,
                            hasOwnSos: rawAlerts.length > peerAlerts.length,
                            ringTextPainters: _ringTextPainters,
                            cardinalTextPainters: _cardinalTextPainters,
                            youTextPainter: _youTextPainter!,
                          ),
                          size: size,
                        );
                      },
                    ),
                  );
                },
              ),
              
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
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => RescueCompassScreen(victimAlert: nearestAlert!),
                              ),
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
      },
    );
  }
}

class RadarPainter extends CustomPainter {
  final List<CachedRadarPin> cachedPins;
  final double pulseValue;
  final bool hasOwnSos;
  final List<TextPainter> ringTextPainters;
  final Map<String, TextPainter> cardinalTextPainters;
  final TextPainter youTextPainter;

  RadarPainter({
    required this.cachedPins,
    required this.pulseValue,
    required this.hasOwnSos,
    required this.ringTextPainters,
    required this.cardinalTextPainters,
    required this.youTextPainter,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) / 2 * 0.9;

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
    
    for (int i = 0; i < ringPercentages.length; i++) {
      final r = maxRadius * ringPercentages[i];
      canvas.drawCircle(center, r, ringPaint);
      if (i < ringTextPainters.length) {
        ringTextPainters[i].paint(canvas, Offset(center.dx + 5, center.dy - r - 15));
      }
    }

    // Cardinal Markers
    if (cardinalTextPainters['N'] != null) {
      cardinalTextPainters['N']!.paint(canvas, Offset(center.dx - 4, center.dy - maxRadius - 20));
      cardinalTextPainters['S']!.paint(canvas, Offset(center.dx - 4, center.dy + maxRadius + 8));
      cardinalTextPainters['E']!.paint(canvas, Offset(center.dx + maxRadius + 8, center.dy - 7));
      cardinalTextPainters['W']!.paint(canvas, Offset(center.dx - maxRadius - 20, center.dy - 7));
    }

    // Volunteer center dot (Blue)
    canvas.drawCircle(center, 6, Paint()..color = Colors.blue);
    
    // "YOU" Label
    youTextPainter.paint(canvas, Offset(center.dx - (youTextPainter.width / 2), center.dy - 20));

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

    for (var pin in cachedPins) {
      // Pulsing outer halo
      canvas.drawCircle(pin.offset, 8 + (pulseValue * 15), pulsePaint);
      
      // Glowing red marker
      canvas.drawCircle(pin.offset, 6, sosPaint);
      
      // Real Alert Badge
      pin.textPainter.paint(canvas, Offset(pin.offset.dx - pin.textPainter.width / 2, pin.offset.dy + 12));
    }
  }

  @override
  bool shouldRepaint(RadarPainter oldDelegate) => true; 
}
