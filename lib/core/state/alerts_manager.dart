import 'package:flutter/foundation.dart';
import 'package:crsis_link_client/crsis_link_client.dart';

enum AlertType { sos, accepted, resolved }

class AlertNotification {
  final DateTime timestamp;
  final String title;
  final String description;
  final AlertType type;
  final double? latitude;
  final double? longitude;

  AlertNotification({
    required this.timestamp,
    required this.title,
    required this.description,
    required this.type,
    this.latitude,
    this.longitude,
  });
}

class AlertsManager extends ChangeNotifier {
  static final AlertsManager _instance = AlertsManager._internal();
  factory AlertsManager() => _instance;
  AlertsManager._internal();

  final List<AlertNotification> _notifications = [];

  List<AlertNotification> get notifications => List.unmodifiable(_notifications);

  void addSosAlert(SosAlert alert) {
    _notifications.insert(0, AlertNotification(
      timestamp: DateTime.now(),
      title: 'SOS Alert: ${alert.senderName}',
      description: alert.message ?? 'Needs emergency assistance.',
      type: AlertType.sos,
      latitude: alert.latitude,
      longitude: alert.longitude,
    ));
    notifyListeners();
  }

  void addRescueEvent(RescueAcceptedEvent event) {
    _notifications.insert(0, AlertNotification(
      timestamp: DateTime.now(),
      title: 'Rescue on the way!',
      description: '${event.volunteerName} has accepted your request.',
      type: AlertType.accepted,
    ));
    notifyListeners();
  }

  void addResolvedEvent(SosResolvedEvent event) {
    _notifications.insert(0, AlertNotification(
      timestamp: DateTime.now(),
      title: 'SOS Resolved',
      description: 'An emergency has been resolved safely.',
      type: AlertType.resolved,
    ));
    notifyListeners();
  }
}
