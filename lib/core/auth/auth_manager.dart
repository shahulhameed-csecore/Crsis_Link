import 'package:crsis_link_client/crsis_link_client.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthManager {
  static late Client client;
  static late String deviceId;
  static late String displayName;

  static Future<void> initialize() async {
    // Load env securely
    try {
      await dotenv.load(fileName: ".env");
    } catch (e) {
      debugPrint('No .env file found, using defaults.');
    }
    String serverUrl = dotenv.env['API_URL'] ?? 'http://localhost:8080/';

    client = Client(serverUrl);

    // Initialize Secure Device Identity and Profile
    const secureStorage = FlutterSecureStorage();
    final prefs = await SharedPreferences.getInstance();
    
    // Secure Storage for deviceId (Threat Vector 4)
    String? storedId = await secureStorage.read(key: 'secure_device_id');
    if (storedId == null) {
      if (prefs.containsKey('device_id')) {
        storedId = prefs.getString('device_id');
        await prefs.remove('device_id'); // Clear legacy insecure ID
      } else {
        storedId = 'dev_${const Uuid().v4()}';
      }
      await secureStorage.write(key: 'secure_device_id', value: storedId!);
    }
    deviceId = storedId;
    debugPrint('MY DEVICE ID: $deviceId');
    
    // Non-sensitive data can stay in SharedPreferences
    String? storedName = prefs.getString('display_name');
    if (storedName == null) {
      storedName = 'Citizen';
      await prefs.setString('display_name', storedName);
    }
    displayName = storedName;
    
    // Open streaming connection for WebSocket
    // ignore: deprecated_member_use
    client.openStreamingConnection();
  }
  
  static Future<void> updateDisplayName(String newName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('display_name', newName);
    displayName = newName;
  }
}

