import 'package:latlong2/latlong.dart';

class RescueNavigationController {
  static const Distance _distance = Distance();

  static double calculateBearing(LatLng rescuer, LatLng victim) {
    return _distance.bearing(rescuer, victim);
  }

  static double calculateDistanceInMeters(LatLng rescuer, LatLng victim) {
    return _distance.as(LengthUnit.Meter, rescuer, victim).toDouble();
  }

  static double computeNeedleRotation(double bearingToVictim, double deviceMagneticHeading) {
    // Return relative rotation in degrees for UI transforms
    double diff = (bearingToVictim - deviceMagneticHeading) % 360;
    if (diff < 0) diff += 360;
    return diff; 
  }

  static String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toInt()} m';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
  }
}
