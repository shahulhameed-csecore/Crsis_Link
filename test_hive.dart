// ignore_for_file: avoid_print
import 'package:hive/hive.dart';
import 'package:crsis_link/core/models/local_sos_alert.dart';
import 'package:crsis_link/core/services/offline_cache_manager.dart';
import 'dart:io';

void main() async {
  Hive.init(Directory.current.path);
  Hive.registerAdapter(LocalSosAlertAdapter());
  var box = await Hive.openBox<LocalSosAlert>('test_box');
  var alert = LocalSosAlert(
    id: '123',
    lat: 10.0,
    lng: 10.0,
    message: 'test',
    approximateLocationText: null,
    originalDeviceId: '123',
    originalSenderName: 'test',
    timestamp: 123,
  );
  print('Putting...');
  await box.put(alert.id, alert);
  print('Done putting.');
  var readAlert = box.get('123');
  print('Read: ${readAlert?.id}');
  exit(0);
}
