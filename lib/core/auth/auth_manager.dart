import 'package:crsis_link_client/crsis_link_client.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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

    // Initialize Device Identity and Profile
    final prefs = await SharedPreferences.getInstance();
    String? storedId = prefs.getString('device_id');
    if (storedId == null) {
      storedId = 'dev_${const Uuid().v4()}';
      await prefs.setString('device_id', storedId);
    }
    deviceId = storedId;
    debugPrint('MY DEVICE ID: $deviceId');
    
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

