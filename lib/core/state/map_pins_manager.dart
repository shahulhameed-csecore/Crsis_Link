import 'package:flutter/foundation.dart';
import 'package:crsis_link_client/crsis_link_client.dart';

class MapPinsManager extends ValueNotifier<List<SosAlert>> {
  static final MapPinsManager _instance = MapPinsManager._internal();
  factory MapPinsManager() => _instance;
  MapPinsManager._internal() : super([]);

  List<SosAlert> get pins => value;

  void setPins(List<SosAlert> newPins) {
    value = newPins;
  }

  void addOrUpdatePin(SosAlert alert) {
    final idx = value.indexWhere((a) => a.clientAlertId == alert.clientAlertId);
    final newList = List<SosAlert>.from(value);
    if (idx >= 0) {
      newList[idx] = alert;
    } else {
      newList.add(alert);
    }
    value = newList;
  }

  void removePin(String clientAlertId) {
    final newList = List<SosAlert>.from(value);
    newList.removeWhere((a) => a.clientAlertId == clientAlertId);
    value = newList;
  }
}
