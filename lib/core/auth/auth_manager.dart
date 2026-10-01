import 'package:crsis_link_client/crsis_link_client.dart';
import 'package:serverpod_flutter/serverpod_flutter.dart';
import 'package:serverpod_auth_shared_flutter/serverpod_auth_shared_flutter.dart';
import 'package:flutter/foundation.dart';

class AuthManager {
  static late Client client;
  static late SessionManager sessionManager;

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

    client = Client(
      serverUrl,
      authenticationKeyManager: FlutterAuthenticationKeyManager(),
    )..connectivityMonitor = FlutterConnectivityMonitor();

    // The session manager keeps track of the signed-in state of the user.
    sessionManager = SessionManager(
      caller: client.modules.auth,
    );

    await sessionManager.initialize();
  }
}
