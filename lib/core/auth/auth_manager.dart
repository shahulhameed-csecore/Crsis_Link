import 'package:crsis_link_client/crsis_link_client.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class AuthManager {
  static late Client client;
  static late String deviceId;

  static Future<void> initialize() async {
    // Toggle this to true when building for production (Render)
    const bool isProduction = true; 

    // Default to localhost for local testing (use 10.0.2.2 for Android emulator)
    String serverUrl = 'http://localhost:8080/';
    
    if (isProduction) {
      serverUrl = 'https://crsis-link-api.onrender.com/';
    } else if (kIsWeb) {
      serverUrl = 'http://localhost:8080/';
    }

    client = Client(serverUrl);

    // Initialize Device Identity
    final prefs = await SharedPreferences.getInstance();
    String? storedId = prefs.getString('device_id');
    if (storedId == null) {
      storedId = 'dev_${const Uuid().v4()}';
      await prefs.setString('device_id', storedId);
    }
    deviceId = storedId;
    
    // Open streaming connection for WebSocket
    client.openStreamingConnection();
  }
}

