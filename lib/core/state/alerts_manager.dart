import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:crsis_link_client/crsis_link_client.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AlertType { sos, accepted, resolved, ignored }

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

  Map<String, dynamic> toJson() {
    return {
      'sosId': sosId,
      'timestamp': timestamp.toIso8601String(),
      'title': title,
      'description': description,
      'type': type.name,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  factory AlertNotification.fromJson(Map<String, dynamic> json) {
    return AlertNotification(
      sosId: json['sosId'] as int?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      title: json['title'] as String,
      description: json['description'] as String,
      type: AlertType.values.firstWhere((e) => e.name == json['type'], orElse: () => AlertType.sos),
      latitude: json['latitude'] as double?,
      longitude: json['longitude'] as double?,
    );
  }
}

class AlertsManager extends ValueNotifier<List<AlertNotification>> {
  static const int _maxAlertHistory = 100;
  static const String _prefsKey = 'alertsHistory';

  static final AlertsManager _instance = AlertsManager._internal();
  factory AlertsManager() => _instance;
  AlertsManager._internal() : super([]) {
    _loadFromPrefs();
  }

  List<AlertNotification> get notifications => value;

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? jsonList = prefs.getStringList(_prefsKey);
      if (jsonList != null) {
        value = jsonList.map((str) => AlertNotification.fromJson(jsonDecode(str))).toList();
      }
    } catch (e) {
      debugPrint('Failed to load alerts history: $e');
    }
  }

  Future<void> _saveToPrefs(List<AlertNotification> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = list.map((n) => jsonEncode(n.toJson())).toList();
      await prefs.setStringList(_prefsKey, jsonList);
    } catch (e) {
      debugPrint('Failed to save alerts history: $e');
    }
  }

  void _applyCapAndNotify(List<AlertNotification> newList) {
    if (newList.length > _maxAlertHistory) {
      newList.removeRange(_maxAlertHistory, newList.length);
    }
    value = newList;
    _saveToPrefs(newList);
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
    WakelockPlus.enable();
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

    if (!newList.any((n) => n.type == AlertType.sos)) {
      WakelockPlus.disable();
    }
  }

  void addResolvedEvent(SosResolvedEvent event) {
    resolveSosAlert(event.sosId);
  }

  void addIgnoredAlert(int sosId, String? senderName) {
    final newList = List<AlertNotification>.from(value);
    // Remove if it's already there as an SOS
    newList.removeWhere((n) => n.sosId == sosId);
    
    newList.insert(0, AlertNotification(
      sosId: sosId,
      timestamp: DateTime.now(),
      title: 'Ignored: ${senderName ?? 'SOS'}',
      description: 'You hid this pin from your map locally.',
      type: AlertType.ignored,
    ));
    
    
    _applyCapAndNotify(newList);
  }

  Future<void> clearAll() async {
    value = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
