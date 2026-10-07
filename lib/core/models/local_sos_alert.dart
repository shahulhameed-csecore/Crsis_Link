import 'package:hive/hive.dart';

class LocalSosAlert extends HiveObject {
  final String id;
  double lat;
  double lng;
  final String message;
  final String? approximateLocationText;
  final String originalDeviceId;
  final String originalSenderName;
  int timestamp;
  int sequenceNumber;
  bool isSynced;

  LocalSosAlert({
    required this.id,
    required this.lat,
    required this.lng,
    required this.message,
    this.approximateLocationText,
    required this.originalDeviceId,
    required this.originalSenderName,
    required this.timestamp,
    this.sequenceNumber = 0,
    this.isSynced = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'lat': lat,
      'lng': lng,
      'message': message,
      'approximateLocationText': approximateLocationText,
      'originalDeviceId': originalDeviceId,
      'originalSenderName': originalSenderName,
      'timestamp': timestamp,
      'sequenceNumber': sequenceNumber,
      'isSynced': isSynced,
    };
  }

  factory LocalSosAlert.fromJson(Map<String, dynamic> json) {
    return LocalSosAlert(
      id: json['id'],
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      message: json['message'] ?? 'Emergency',
      approximateLocationText: json['approximateLocationText'],
      originalDeviceId: json['originalDeviceId'] ?? 'unknown_device',
      originalSenderName: json['originalSenderName'] ?? 'Unknown Sender',
      timestamp: json['timestamp'],
      sequenceNumber: json['sequenceNumber'] ?? 0,
      isSynced: json['isSynced'] ?? false,
    );
  }
}
