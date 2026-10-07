import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

class P2pCryptoService {
  static final P2pCryptoService _instance = P2pCryptoService._internal();
  factory P2pCryptoService() => _instance;
  P2pCryptoService._internal();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final Ed25519 _ed25519 = Ed25519();
  
  SimpleKeyPair? _keyPair;
  String? _publicKeyCache;

  Future<void> init() async {
    try {
      final privateKeyHex = await _secureStorage.read(key: 'p2p_private_key');
      
      if (privateKeyHex == null) {
        _keyPair = await _ed25519.newKeyPair();
        final privateKeyBytes = await _keyPair!.extractPrivateKeyBytes();
        await _secureStorage.write(
          key: 'p2p_private_key', 
          value: base64Encode(privateKeyBytes)
        );
      } else {
        final privateKeyBytes = base64Decode(privateKeyHex);
        _keyPair = await _ed25519.newKeyPairFromSeed(privateKeyBytes);
      }
      
      final pubKey = await _keyPair!.extractPublicKey();
      _publicKeyCache = base64Encode(pubKey.bytes);
      debugPrint('[P2P_CRYPTO] Initialized device cryptographic identity.');
    } catch (e) {
      debugPrint('[P2P_CRYPTO] Failed to initialize crypto service: $e');
    }
  }

  String get publicKey => _publicKeyCache ?? '';

  static String deriveDeviceIdFromKey(String publicKeyBase64) {
    final bytes = base64Decode(publicKeyBase64);
    final hash = sha256.convert(bytes).bytes;
    final hexString = hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
    return 'dev_${hexString.substring(0, 16)}';
  }

  Future<String> signPayload(String payloadString) async {
    if (_keyPair == null) return '';
    try {
      final message = utf8.encode(payloadString);
      final signature = await _ed25519.sign(message, keyPair: _keyPair!);
      return base64Encode(signature.bytes);
    } catch (e) {
      debugPrint('[P2P_CRYPTO] Failed to sign payload: $e');
      return '';
    }
  }

  Future<bool> verifyPayload(String payloadString, String publicKeyBase64, String signatureBase64) async {
    try {
      final message = utf8.encode(payloadString);
      final pubKeyBytes = base64Decode(publicKeyBase64);
      final sigBytes = base64Decode(signatureBase64);
      
      final pubKey = SimplePublicKey(pubKeyBytes, type: KeyPairType.ed25519);
      final signature = Signature(sigBytes, publicKey: pubKey);
      
      return await _ed25519.verify(message, signature: signature);
    } catch (e) {
      debugPrint('[P2P_CRYPTO] Failed to verify payload signature: $e');
      return false;
    }
  }
}
