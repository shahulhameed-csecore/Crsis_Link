import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:crsis_link_client/crsis_link_client.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/offline_cache_manager.dart';

enum AlertType { sos, accepted, resolved, ignored }

class AlertNotification {
  final String? clientAlertId;
  final DateTime timestamp;
  final String title;
  final String description;
  final AlertType type;
  final double? latitude;
  final double? longitude;

  AlertNotification({
    this.clientAlertId,
    required this.timestamp,
    required this.title,
    required this.description,
    required this.type,
    this.latitude,
    this.longitude,
  });

  Map<String, dynamic> toJson() {
    return {
      'clientAlertId': clientAlertId,
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
      clientAlertId: json['clientAlertId'] as String?,
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
      final box = OfflineCacheManager.getNotificationsBox();
      final String? jsonListStr = box.get(_prefsKey);
      if (jsonListStr != null) {
        final List<dynamic> rawList = jsonDecode(jsonListStr);
        final List<String> jsonList = rawList.cast<String>();
        value = jsonList.map((str) => AlertNotification.fromJson(jsonDecode(str))).toList();
      } else {
        // Migration: check if legacy unencrypted prefs exist and migrate
        final prefs = await SharedPreferences.getInstance();
        final List<String>? legacyList = prefs.getStringList(_prefsKey);
        if (legacyList != null) {
          value = legacyList.map((str) => AlertNotification.fromJson(jsonDecode(str))).toList();
          await box.put(_prefsKey, jsonEncode(legacyList));
          await prefs.remove(_prefsKey);
        }
      }
    } catch (e) {
      debugPrint('Failed to load alerts history: $e');
    }
  }

  Future<void> _saveToPrefs(List<AlertNotification> list) async {
    try {
      final box = OfflineCacheManager.getNotificationsBox();
      final jsonList = list.map((n) => jsonEncode(n.toJson())).toList();
      await box.put(_prefsKey, jsonEncode(jsonList));
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
    final idx = value.indexWhere((n) => n.clientAlertId != null && n.clientAlertId == alert.clientAlertId);
    final notification = AlertNotification(
      clientAlertId: alert.clientAlertId,
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

  void resolveSosAlert(String clientAlertId) {
    final newList = List<AlertNotification>.from(value);
    newList.removeWhere((n) => n.clientAlertId == clientAlertId);
    
    newList.insert(0, AlertNotification(
      clientAlertId: clientAlertId,
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
    resolveSosAlert(event.clientAlertId);
  }

  void addIgnoredAlert(String clientAlertId, String? senderName) {
    final newList = List<AlertNotification>.from(value);
    // Remove if it's already there as an SOS
    newList.removeWhere((n) => n.clientAlertId == clientAlertId);
    
    newList.insert(0, AlertNotification(
      clientAlertId: clientAlertId,
      timestamp: DateTime.now(),
      title: 'Ignored: ${senderName ?? 'SOS'}',
      description: 'You hid this pin from your map locally.',
      type: AlertType.ignored,
    ));
    
    
    _applyCapAndNotify(newList);
  }

  Future<void> clearAll() async {
    value = [];
    try {
      final box = OfflineCacheManager.getNotificationsBox();
      await box.delete(_prefsKey);
    } catch (_) {}
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
