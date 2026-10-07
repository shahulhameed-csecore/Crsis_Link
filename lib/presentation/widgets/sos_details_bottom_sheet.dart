import 'package:flutter/material.dart';
import '../../core/services/p2p_crypto_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:crsis_link_client/crsis_link_client.dart';
import '../../core/auth/auth_manager.dart';
import '../../core/theme/design_system.dart';
import '../../core/state/map_pins_manager.dart';
import '../../core/state/alerts_manager.dart';
import 'capsule_button.dart';
import 'audio_player_button.dart';
import '../../core/services/offline_mesh_service.dart';
import '../../core/services/rescue_chat_session.dart';

class SosDetailsBottomSheet extends StatefulWidget {
  final dynamic alert;
  final bool isOwnPin;
  final VoidCallback? onIgnore;
  final VoidCallback? onResolve;
  final VoidCallback? onClaimRescue;
  final VoidCallback? onTrack;

  const SosDetailsBottomSheet({
    super.key,
    required this.alert,
    this.isOwnPin = false,
    this.onIgnore,
    this.onResolve,
    this.onClaimRescue,
    this.onTrack,
  });

  @override
  State<SosDetailsBottomSheet> createState() => _SosDetailsBottomSheetState();
}

class _SosDetailsBottomSheetState extends State<SosDetailsBottomSheet> {
  bool isSubmitting = false;
  late final TextEditingController pinController;

  @override
  void initState() {
    super.initState();
    pinController = TextEditingController();
  }

  @override
  void dispose() {
    pinController.dispose();
    super.dispose();
  }

  void setModalState(VoidCallback fn) {
    setState(fn);
  }

  @override
  Widget build(BuildContext ctx) {
    final alert = widget.alert;
    final isOwnPin = widget.isOwnPin;
    final bool isClaimed = alert.status == 'CLAIMED';

    return PopScope(
      canPop: !isSubmitting,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) AlertsManager().releaseWakelockEarly();
      },
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
Row(
                children: [
                  Icon(isClaimed ? Icons.check_circle : Icons.emergency, 
                       color: isClaimed ? Colors.green : AppColors.emergencyRed, size: 32),
                  const SizedBox(width: 12),
                  Text(
                    isOwnPin ? 'YOUR SOS' : (isClaimed ? 'RESCUE CLAIMED' : 'SOS ALERT'),
                    style: AppTypography.primaryHeader.copyWith(
                      color: isOwnPin ? Colors.blue : (isClaimed ? Colors.green : AppColors.emergencyRed),
                      fontSize: 22,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Victim: ${alert.senderName}',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                alert.message?.isNotEmpty == true ? alert.message! : 'No additional details provided.',
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              if (alert.photoUrl != null && alert.photoUrl!.isNotEmpty) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 220,
                    width: double.infinity,
                    child: Image.network(
                      alert.photoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.grey, size: 48),
                    ),
                  ),
                ),
              ],
              if (alert.audioUrl != null && alert.audioUrl!.isNotEmpty) ...[
                const SizedBox(height: 16),
                AudioPlayerButton(audioUrl: alert.audioUrl!),
              ],
              if (isOwnPin && isClaimed && alert.verificationPin != null && !alert.isRescuerVerified) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Show this PIN to your rescuer when they arrive.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.green, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        alert.verificationPin!,
                        style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 8),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (isOwnPin)
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.grey,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            ),
                            child: const Text('CANCEL'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isSubmitting ? null : () async {
                              final alertId = alert.id;
                              if (alertId == null || alert.clientAlertId == null) return;
                              setModalState(() => isSubmitting = true);
                              try {
                                final expectedPayload = "resolveSOS_${alert.clientAlertId!}";
                                final signature = await P2pCryptoService().signPayload(expectedPayload);
                                final success = await AuthManager.client.sos.resolveSOS(alert.clientAlertId!, AuthManager.deviceId, signature, P2pCryptoService().publicKey);
                                if (!success) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Failed to resolve: Not found or unauthorized.')));
                                  }
                                  setModalState(() => isSubmitting = false);
                                  return;
                                }
                                if (ctx.mounted) {
                                  AlertsManager().releaseWakelockEarly();
                                  Navigator.pop(ctx);
                                  if (widget.onResolve != null) widget.onResolve!();
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(content: Text('SOS Resolved / Cleared.')),
                                  );
                                }
                              } catch (e) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Failed to resolve: $e')));
                                }
                                setModalState(() => isSubmitting = false);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.emergencyRed,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            ),
                            child: isSubmitting 
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white))
                              : const Text('RESOLVE SOS'),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (!isClaimed)
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              final alertId = alert.id;
                              if (alertId == null) return;
                              if (widget.onIgnore != null) widget.onIgnore!();
                              AlertsManager().releaseWakelockEarly();
                              Navigator.pop(ctx);
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.grey,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            ),
                            child: const Text('DENY / IGNORE'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isSubmitting ? null : () async {
                              final alertId = alert.id;
                              if (alertId == null || alert.clientAlertId == null) return;
                              setModalState(() => isSubmitting = true);
                              try {
                                final expectedPayload = "claimRescue_${alert.clientAlertId!}";
                                final signature = await P2pCryptoService().signPayload(expectedPayload);
                                OfflineMeshService().broadcastClaimRescue(alert.clientAlertId!);
                                await AuthManager.client.sos.claimRescue(AuthManager.deviceId, AuthManager.displayName, alert.clientAlertId!, signature, P2pCryptoService().publicKey).timeout(const Duration(seconds: 10));
                                if (ctx.mounted) {
                                  final updatedAlert = alert.copyWith(
                                    status: 'CLAIMED',
                                    volunteerDeviceId: AuthManager.deviceId,
                                  );
                                  MapPinsManager().addOrUpdatePin(updatedAlert);
                                  
                                  AlertsManager().addSelfRescueEvent(RescueAcceptedEvent(
                                    victimDeviceId: alert.deviceId,
                                    volunteerName: AuthManager.displayName,
                                    volunteerDeviceId: AuthManager.deviceId,
                                  ));
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content: Text('Rescue Claimed Successfully!'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                  if (widget.onClaimRescue != null) widget.onClaimRescue!();
                                  if (widget.onTrack != null) widget.onTrack!();
                                }
                              } catch (e) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: Text('Failed to claim: $e')),
                                  );
                                }
                                setModalState(() => isSubmitting = false);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            ),
                            child: isSubmitting 
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white))
                              : const Text('ACCEPT RESCUE'),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (isClaimed && alert.volunteerDeviceId == AuthManager.deviceId)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!alert.isRescuerVerified) ...[
                      CapsuleButton(
                        text: 'Message Victim',
                        style: CapsuleStyle.secondary,
                        onPressed: () {
                          _showChatDialog(context, alert);
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Search the 200-meter area. Ask the victim for their 4-digit PIN to verify and reveal exact coordinates.',
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: pinController,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          hintText: 'Enter 4-Digit Victim PIN',
                          hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 16, letterSpacing: 0, fontWeight: FontWeight.normal),
                          filled: true,
                          fillColor: Colors.grey.withValues(alpha: 0.1),
                          counterText: '',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      CapsuleButton(
                        text: 'VERIFY PIN',
                        style: CapsuleStyle.primary,
                        isLoading: isSubmitting,
                        onPressed: () async {
                          final alertId = alert.id;
                          if (alertId == null || alert.clientAlertId == null) return;
                          if (pinController.text.length != 4) return;
                          setModalState(() => isSubmitting = true);
                          try {
                            await AuthManager.client.sos.verifyHelperPin(alert.clientAlertId!, pinController.text).timeout(const Duration(seconds: 10));
                            if (ctx.mounted) {
                              alert.isRescuerVerified = true;
                              setModalState(() => isSubmitting = false);
                              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('PIN Verified! Exact location revealed.', style: TextStyle(color: Colors.green))));
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              setModalState(() => isSubmitting = false);
                              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Incorrect PIN. Please verify the 4-digit number with the victim.'), backgroundColor: AppColors.emergencyRed));
                            }
                          }
                        }
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Exact GPS Coordinates:', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('${alert.latitude}, ${alert.longitude}', style: const TextStyle(color: Colors.white, fontSize: 16)),
                            const SizedBox(height: 8),
                            const Text('Street Address:', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            const Text('Verified Victim Location', style: TextStyle(color: Colors.white, fontSize: 16)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      CapsuleButton(
                        text: 'COMPLETE RESCUE',
                        style: CapsuleStyle.primary,
                        isLoading: isSubmitting,
                        onPressed: () async {
                          final alertId = alert.id;
                          if (alertId == null || alert.clientAlertId == null) return;
                          setModalState(() => isSubmitting = true);
                          try {
                            await AuthManager.client.sos.completeRescue(AuthManager.deviceId, alert.clientAlertId!).timeout(const Duration(seconds: 10));
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              if (widget.onResolve != null) widget.onResolve!();
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Rescue Completed Successfully!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Failed to complete: $e')),
                              );
                            }
                            setModalState(() => isSubmitting = false);
                          }
                        },
                      ),
                    ],
                  ],
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showChatDialog(BuildContext context, dynamic alert) {
    final alertId = alert.clientAlertId ?? alert.id.toString();
    final textController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Secure Chat'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: Column(
              children: [
                Expanded(
                  child: ValueListenableBuilder<List<ChatMessage>>(
                    valueListenable: RescueChatSession().messagesNotifier,
                    builder: (context, messages, _) {
                      final chatMsgs = messages.where((m) => m.alertId == alertId).toList();
                      if (chatMsgs.isEmpty) {
                        return const Center(child: Text('No messages yet', style: TextStyle(color: Colors.grey)));
                      }
                      return ListView.builder(
                        itemCount: chatMsgs.length,
                        itemBuilder: (context, index) {
                          final m = chatMsgs[index];
                          final isMe = m.senderId == AuthManager.deviceId;
                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isMe ? Colors.blue.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(m.text),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: textController,
                        decoration: const InputDecoration(hintText: 'Type message...'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: () {
                        if (textController.text.trim().isNotEmpty) {
                          // We pass an empty string for recipient pub key in this basic demo
                          RescueChatSession().sendMessage(alertId, textController.text.trim(), "");
                          textController.clear();
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
