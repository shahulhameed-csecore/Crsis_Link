import 'package:crsis_link_client/crsis_link_client.dart';
import 'package:serverpod_auth_shared_flutter/serverpod_auth_shared_flutter.dart';

class SimpleKeyManager extends AuthenticationKeyManager {
  String? _key;
  @override
  Future<String?> get() async => _key;
  @override
  Future<void> put(String key) async => _key = key;
  @override
  Future<void> remove() async => _key = null;
}

void main() async {
  final keyManager = SimpleKeyManager();
  final client = Client(
    'https://crsis-link-api.onrender.com/',
    authenticationKeyManager: keyManager,
  );
  
  final response = await client.demoAuth.demoLogin();
  print('Login Success: ${response.success}');
  await keyManager.put('${response.keyId}:${response.key}');
  
  try {
    final alert = await client.sos.broadcastSos(28.0, 77.0, 'Test Alert');
    print('Broadcast Success: ${alert.id}');
  } catch (e) {
    print('Broadcast Failed: $e');
  }
}
