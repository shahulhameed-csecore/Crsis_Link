import 'package:flutter/foundation.dart';
import 'package:crsis_link_client/crsis_link_client.dart';

enum AlertType { sos, accepted, resolved }

class AlertNotification {
  final int? sosId;
  final DateTime timestamp;
  final String title;
  final String description;
  final AlertType type;
  final double? latitude;
  final double? longitude;

  AlertNotification({
    this.sosId,
    required this.timestamp,
    required this.title,
    required this.description,
    required this.type,
    this.latitude,
    this.longitude,
  });
}

class AlertsManager extends ValueNotifier<List<AlertNotification>> {
  static final AlertsManager _instance = AlertsManager._internal();
  factory AlertsManager() => _instance;
  AlertsManager._internal() : super([]);

  List<AlertNotification> get notifications => value;

  void addSosAlert(SosAlert alert) {
    final idx = value.indexWhere((n) => n.sosId != null && n.sosId == alert.id);
    final notification = AlertNotification(
      sosId: alert.id,
      timestamp: DateTime.now(),
      title: 'SOS Alert: ${alert.senderName}',
      description: alert.status == 'CLAIMED' ? 'Rescue on the way' : (alert.message ?? 'Needs emergency assistance.'),
      type: AlertType.sos,
      latitude: alert.latitude,
      longitude: alert.longitude,
    );

    if (idx >= 0) {
      final newList = List<AlertNotification>.from(value);
      newList[idx] = notification;
      value = newList;
    } else {
      value = [notification, ...value];
    }
  }

  void addRescueEvent(RescueAcceptedEvent event) {
    value = [
      AlertNotification(
        timestamp: DateTime.now(),
        title: 'Rescue on the way!',
        description: '${event.volunteerName} has accepted your request.',
        type: AlertType.accepted,
      ),
      ...value,
    ];
  }

  void addSelfRescueEvent(RescueAcceptedEvent event) {
    value = [
      AlertNotification(
        timestamp: DateTime.now(),
        title: 'Rescue Accepted',
        description: 'You are on your way to help.',
        type: AlertType.accepted,
      ),
      ...value,
    ];
  }

  void addResolvedEvent(SosResolvedEvent event) {
    value = [
      AlertNotification(
        timestamp: DateTime.now(),
        title: 'SOS Resolved',
        description: 'An emergency has been resolved safely.',
        type: AlertType.resolved,
      ),
      ...value,
    ];
  }
}
