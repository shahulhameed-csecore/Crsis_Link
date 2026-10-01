import 'package:flutter/foundation.dart';
import 'package:crsis_link_client/crsis_link_client.dart';

class AlertNotification {
  final DateTime timestamp;
  final String title;
  final String description;
  final bool isRescue;

  AlertNotification({
    required this.timestamp,
    required this.title,
    required this.description,
    this.isRescue = false,
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
      isRescue: false,
    ));
    notifyListeners();
  }

  void addRescueEvent(RescueAcceptedEvent event) {
    _notifications.insert(0, AlertNotification(
      timestamp: DateTime.now(),
      title: 'Rescue on the way!',
      description: '${event.volunteerName} has accepted your request.',
      isRescue: true,
    ));
    notifyListeners();
  }
}
