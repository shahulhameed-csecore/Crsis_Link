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
  static const int _maxAlertHistory = 100;

  static final AlertsManager _instance = AlertsManager._internal();
  factory AlertsManager() => _instance;
  AlertsManager._internal() : super([]);

  List<AlertNotification> get notifications => value;

  void _applyCapAndNotify(List<AlertNotification> newList) {
    if (newList.length > _maxAlertHistory) {
      newList.removeRange(_maxAlertHistory, newList.length);
    }
    value = newList;
  }

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
      _applyCapAndNotify(newList);
    } else {
      _applyCapAndNotify([notification, ...value]);
    }
  }

  void addRescueEvent(RescueAcceptedEvent event) {
    _applyCapAndNotify([
      AlertNotification(
        timestamp: DateTime.now(),
        title: 'Rescue on the way!',
        description: '${event.volunteerName} has accepted your request.',
        type: AlertType.accepted,
      ),
      ...value,
    ]);
  }

  void addSelfRescueEvent(RescueAcceptedEvent event) {
    _applyCapAndNotify([
      AlertNotification(
        timestamp: DateTime.now(),
        title: 'Rescue Accepted',
        description: 'You are on your way to help.',
        type: AlertType.accepted,
      ),
      ...value,
    ]);
  }

  void resolveSosAlert(int sosId) {
    final newList = List<AlertNotification>.from(value);
    newList.removeWhere((n) => n.sosId == sosId);
    
    newList.insert(0, AlertNotification(
      sosId: sosId,
      timestamp: DateTime.now(),
      title: 'SOS Resolved',
      description: 'An emergency has been resolved safely.',
      type: AlertType.resolved,
    ));
    
    _applyCapAndNotify(newList);
  }

  void addResolvedEvent(SosResolvedEvent event) {
    resolveSosAlert(event.sosId);
  }
}
