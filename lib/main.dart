import 'package:flutter/material.dart';
import 'core/theme/design_system.dart';
import 'presentation/screens/main_navigation.dart';
import 'core/error/global_error_handler.dart';
import 'core/auth/auth_manager.dart';
import 'core/services/offline_cache_manager.dart';
import 'core/services/network_sync_manager.dart';

import 'package:flutter/services.dart';

import 'dart:ui';
import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'core/services/offline_mesh_service.dart';
import 'core/services/p2p_crypto_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

final GlobalKey<ScaffoldMessengerState> globalMessengerKey = GlobalKey<ScaffoldMessengerState>();


@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  
  try {
    const secureStorage = FlutterSecureStorage();
    String? storedId = await secureStorage.read(key: 'secure_device_id');
    if (storedId == null) {
      final prefs = await SharedPreferences.getInstance();
      storedId = prefs.getString('device_id') ?? 'dev_unknown_bg';
    }
    AuthManager.deviceId = storedId;
  } catch (e) {
    AuthManager.deviceId = 'dev_unknown_bg';
  }

  await P2pCryptoService().init();
  await OfflineCacheManager.init();

  OfflineMeshService().startMesh(isBackground: true); 
  
  service.on('stopService').listen((event) {
    OfflineMeshService().toggleOfflineMode(false);
    service.stopSelf();
  });
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      initialNotificationTitle: 'Crsis_Link Mesh Active',
      initialNotificationContent: 'Relaying emergency alerts in the background',
      notificationChannelId: 'mesh_background_channel',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Warning: .env file not found.");
  }
  
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    )
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  GlobalErrorHandler.initialize();
  await AuthManager.initialize();
  await P2pCryptoService().init();
  await OfflineCacheManager.init();
  NetworkSyncManager().init();
  NetworkSyncManager().uploadPendingAlerts();
  
  await initializeService();
  runZonedGuarded(() {
    runApp(const CrsisLinkApp());
  }, (error, stack) {
    GlobalErrorHandler.recordError(error, stack);
  });
}

class CrsisLinkApp extends StatelessWidget {
  const CrsisLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crsis Link',
      scaffoldMessengerKey: globalMessengerKey,
      theme: AppTheme.lightTheme,
      home: MainNavigation(key: globalNavKey),
      builder: (context, widget) {
        return widget ?? const SizedBox();
      },
    );
  }
}

