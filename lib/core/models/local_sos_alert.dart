import 'package:hive/hive.dart';

class LocalSosAlert extends HiveObject {
  final String id;
  double lat;
  double lng;
  final String message;
  final String victimPhone;
  final String? approximateLocationText;
  final String originalDeviceId;
  final String originalSenderName;
  int timestamp;
  bool isSynced;

  LocalSosAlert({
    required this.id,
    required this.lat,
    required this.lng,
    required this.message,
    required this.victimPhone,
    this.approximateLocationText,
    required this.originalDeviceId,
    required this.originalSenderName,
    required this.timestamp,
    this.isSynced = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'lat': lat,
      'lng': lng,
      'message': message,
      'victimPhone': victimPhone,
      'approximateLocationText': approximateLocationText,
      'originalDeviceId': originalDeviceId,
      'originalSenderName': originalSenderName,
      'timestamp': timestamp,
      'isSynced': isSynced,
    };
  }

  factory LocalSosAlert.fromJson(Map<String, dynamic> json) {
    return LocalSosAlert(
      id: json['id'],
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      message: json['message'] ?? 'Emergency',
      victimPhone: json['victimPhone'] ?? 'URGENT-NO-NUMBER',
      approximateLocationText: json['approximateLocationText'],
      originalDeviceId: json['originalDeviceId'] ?? 'unknown_device',
      originalSenderName: json['originalSenderName'] ?? 'Unknown Sender',
      timestamp: json['timestamp'],
      isSynced: json['isSynced'] ?? false,
    );
  }
}
