import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'offline_mesh_service.dart';
import '../auth/auth_manager.dart';
import 'p2p_crypto_service.dart';
import 'package:crypto/crypto.dart';

class ChatMessage {
  final String id;
  final String alertId;
  final String senderId;
  final String text;
  final int timestamp;

  ChatMessage({required this.id, required this.alertId, required this.senderId, required this.text, required this.timestamp});

  Map<String, dynamic> toJson() => {'id': id, 'alertId': alertId, 'senderId': senderId, 'text': text, 'timestamp': timestamp};
  
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'], alertId: json['alertId'], senderId: json['senderId'], text: json['text'], timestamp: json['timestamp']
  );
}

class RescueChatSession {
  static final RescueChatSession _instance = RescueChatSession._internal();
  factory RescueChatSession() => _instance;
  RescueChatSession._internal();

  final ValueNotifier<List<ChatMessage>> messagesNotifier = ValueNotifier([]);
  bool _isInit = false;

  Future<void> init() async {
    if (!_isInit) {
      await Hive.openBox('chat_messages');
      _isInit = true;
    }
  }

  Box get _box => Hive.box('chat_messages');

  List<ChatMessage> getMessages(String alertId) {
    if (!_box.isOpen) return [];
    final raw = _box.get(alertId, defaultValue: '[]');
    final List list = jsonDecode(raw);
    return list.map((e) => ChatMessage.fromJson(e)).toList()..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  Future<void> sendMessage(String alertId, String text, String recipientPubKey) async {
    final msg = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      alertId: alertId,
      senderId: AuthManager.deviceId,
      text: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    _appendMessage(msg);

    // E2EE Mock Implementation: XOR/AES simulation based on shared Ed25519 hash
    final encryptedText = base64Encode(utf8.encode(text)); // Placeholder for actual E2EE

    OfflineMeshService().broadcastChatMessage(alertId, encryptedText, recipientPubKey);
  }

  void _appendMessage(ChatMessage msg) {
    if (!_box.isOpen) return;
    final msgs = getMessages(msg.alertId);
    if (!msgs.any((m) => m.id == msg.id)) {
      msgs.add(msg);
      _box.put(msg.alertId, jsonEncode(msgs.map((e) => e.toJson()).toList()));
      messagesNotifier.value = List.from(msgs);
    }
  }

  void receiveMessagePayload(String alertId, String senderId, String encryptedText) {
    // Decrypt here
    try {
      final decryptedText = utf8.decode(base64Decode(encryptedText)); // Placeholder for actual decryption
      final msg = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        alertId: alertId,
        senderId: senderId,
        text: decryptedText,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      _appendMessage(msg);
    } catch (e) {
      debugPrint('Failed to decrypt incoming chat message: $e');
    }
  }

  Future<void> destroyChatForAlert(String alertId) async {
    if (_box.isOpen) {
      await _box.delete(alertId);
      messagesNotifier.value = [];
    }
  }
}
