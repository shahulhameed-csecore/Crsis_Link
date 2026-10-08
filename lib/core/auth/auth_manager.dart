import 'package:crsis_link_client/crsis_link_client.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/p2p_crypto_service.dart';

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
    String serverUrl = dotenv.env['API_URL'] ?? 'https://crsis-link-api.onrender.com/';
    if (serverUrl.isEmpty || serverUrl.contains('localhost')) {
      serverUrl = 'https://crsis-link-api.onrender.com/';
    }

    client = Client(serverUrl);

    // Ensure Crypto Service is ready
    await P2pCryptoService().init();
    
    final prefs = await SharedPreferences.getInstance();
    
    // Secure Identity Binding (Threat Vector P2P-02)
    // The device identity is mathematically bound to the private key
    deviceId = P2pCryptoService.deriveDeviceIdFromKey(P2pCryptoService().publicKey);
    debugPrint('MY CRYPTOGRAPHIC DEVICE ID: $deviceId');
    
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

