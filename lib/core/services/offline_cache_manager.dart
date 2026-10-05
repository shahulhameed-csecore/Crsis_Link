import 'package:hive_flutter/hive_flutter.dart';
import '../models/local_sos_alert.dart';

class OfflineCacheManager {
  static const String _boxName = 'offline_sos_box';

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
    await Hive.openBox<LocalSosAlert>(_boxName);
  }

  static Box<LocalSosAlert> get _box => Hive.box<LocalSosAlert>(_boxName);

  static Future<void> saveAlert(LocalSosAlert alert) async {
    await _box.put(alert.id, alert);
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
      victimPhone: fields[6] as String? ?? 'URGENT-NO-NUMBER',
      approximateLocationText: fields[7] as String?,
      originalDeviceId: fields[8] as String? ?? 'unknown_device',
      originalSenderName: fields[9] as String? ?? 'Unknown Sender',
    );
  }

  @override
  void write(BinaryWriter writer, LocalSosAlert obj) {
    writer
      ..writeByte(10)
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
      ..write(obj.victimPhone)
      ..writeByte(7)
      ..write(obj.approximateLocationText)
      ..writeByte(8)
      ..write(obj.originalDeviceId)
      ..writeByte(9)
      ..write(obj.originalSenderName);
  }
}
