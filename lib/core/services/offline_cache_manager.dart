import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/local_sos_alert.dart';
class OfflineCacheManager {
  static const String _boxName = 'offline_sos_box';
  static const String _notificationsBoxName = 'secure_alerts_history';

  static Future<void> init() async {
    await Hive.initFlutter();
    // In a real app, generate the TypeAdapter via build_runner.
    // For this hackathon implementation without build_runner, we can register manually 
    // or just use dynamic Map if adapter is omitted. We assume adapter is generated.
    try {
      Hive.registerAdapter(LocalSosAlertAdapter());
    } catch (e) {
      // Ignore if already registered
    }

    const secureStorage = FlutterSecureStorage();
    String? encryptionKeyString = await secureStorage.read(key: 'hive_encryption_key');
    if (encryptionKeyString == null) {
      final key = Hive.generateSecureKey();
      await secureStorage.write(
        key: 'hive_encryption_key',
        value: base64UrlEncode(key),
      );
      encryptionKeyString = base64UrlEncode(key);
    }
    
    final encryptionKeyUint8List = base64Url.decode(encryptionKeyString);
    
    await Hive.openBox<LocalSosAlert>(
      _boxName,
      encryptionCipher: HiveAesCipher(encryptionKeyUint8List),
    );
    
    await Hive.openBox<String>(
      _notificationsBoxName,
      encryptionCipher: HiveAesCipher(encryptionKeyUint8List),
    );
  }

  static Box<String> getNotificationsBox() {
    if (!Hive.isBoxOpen(_notificationsBoxName)) {
      throw StateError('Notifications Box is not open.');
    }
    return Hive.box<String>(_notificationsBoxName);
  }

  static Box<LocalSosAlert> get _box {
    if (!Hive.isBoxOpen(_boxName)) {
      throw StateError('OfflineCacheManager not initialized: Box is not open.');
    }
    return Hive.box<LocalSosAlert>(_boxName);
  }
  
  static Box<LocalSosAlert> getBox() => _box;

  static Future<void> saveAlert(LocalSosAlert alert) async {
    try {
      if (!Hive.isBoxOpen(_boxName)) {
        await init();
      }
      if (_box.length >= 1000) {
        final syncedKeys = _box.keys.where((k) {
          final item = _box.get(k);
          return item != null && item.isSynced;
        }).toList();
        if (syncedKeys.isNotEmpty) {
          await _box.delete(syncedKeys.first);
        } else {
          await _box.delete(_box.keys.first);
        }
      }
      await _box.put(alert.id, alert);
    } catch (e) {
      debugPrint('Storage Exhaustion or Hive Error: $e');
    }
  }

  static List<LocalSosAlert> getUnsyncedAlerts() {
    return _box.values.where((alert) => !alert.isSynced).toList();
  }

  static Future<void> markAsSynced(String id) async {
    final alert = _box.get(id);
    if (alert != null) {
      alert.isSynced = true;
      await alert.save();
    }
  }
  
  static bool alertExists(String id) {
    return _box.containsKey(id);
  }

  static LocalSosAlert? getAlert(String id) {
    return _box.get(id);
  }
  
  static Future<void> clearExpiredAlerts(Duration threshold) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final thresholdMs = threshold.inMilliseconds;
    final keysToDelete = <dynamic>[];
    
    for (var key in _box.keys) {
      final alert = _box.get(key);
      if (alert != null) {
        if (now - alert.timestamp > thresholdMs) {
          keysToDelete.add(key);
        }
      }
    }
    
    if (keysToDelete.isNotEmpty) {
      await _box.deleteAll(keysToDelete);
      debugPrint('Reconciliation: Dropped ${keysToDelete.length} expired offline alerts.');
    }
  }

  static Future<void> clearEntireCache() async {
    await _box.clear();
    if (Hive.isBoxOpen(_notificationsBoxName)) {
      await Hive.box<String>(_notificationsBoxName).clear();
    }
  }
}

// Manual Adapter fallback if build_runner is not used for Hackathon
class LocalSosAlertAdapter extends TypeAdapter<LocalSosAlert> {
  @override
  final int typeId = 0;

  @override
  LocalSosAlert read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LocalSosAlert(
      id: fields[0] as String,
      lat: fields[1] as double,
      lng: fields[2] as double,
      message: fields[3] as String,
      timestamp: fields[4] as int,
      isSynced: fields[5] as bool,
      approximateLocationText: fields[7] as String?,
      originalDeviceId: fields[8] as String? ?? 'unknown_device',
      originalSenderName: fields[9] as String? ?? 'Unknown Sender',
    );
  }

  @override
  void write(BinaryWriter writer, LocalSosAlert obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.lat)
      ..writeByte(2)
      ..write(obj.lng)
      ..writeByte(3)
      ..write(obj.message)
      ..writeByte(4)
      ..write(obj.timestamp)
      ..writeByte(5)
      ..write(obj.isSynced)
      ..writeByte(6)
      ..write('') // Legacy victimPhone field stripped
      ..writeByte(7)
      ..write(obj.approximateLocationText)
      ..writeByte(8)
      ..write(obj.originalDeviceId)
      ..writeByte(9)
      ..write(obj.originalSenderName);
  }
}
