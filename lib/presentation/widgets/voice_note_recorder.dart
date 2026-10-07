import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:record/record.dart';
import 'package:crsis_link_client/crsis_link_client.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/auth/auth_manager.dart';
import '../../core/theme/design_system.dart';

class VoiceNoteRecorder extends StatefulWidget {
  final void Function(String audioUrl) onRecorded;

  const VoiceNoteRecorder({super.key, required this.onRecorded});

  @override
  State<VoiceNoteRecorder> createState() => _VoiceNoteRecorderState();
}

class _VoiceNoteRecorderState extends State<VoiceNoteRecorder>
    with SingleTickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();
  
  bool _isRecording = false;
  bool _isUploading = false;
  bool _isRecorded = false;
  String? _recordedFilePath;
  int _secondsElapsed = 0;
  Timer? _timer;
  String? _uploadedUrl;
  bool _isPendingStart = false;
  DateTime? _recordingStartTime;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    // LEAK-P3-03 FIX: Stop the animation before disposing to prevent
    // native assertion crashes when the modal is dismissed during active recording.
    if (_pulseController.isAnimating) _pulseController.stop();
    _pulseController.dispose();
    // Stop any active recording session before disposing the native audio engine.
    if (_isRecording) _recorder.stop();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    _isPendingStart = true;
    
    if (!(await Permission.microphone.request().isGranted)) {
      _isPendingStart = false;
      if (mounted) {
        setState(() {
          _isRecording = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission denied.'),
            backgroundColor: AppColors.emergencyRed,
          ),
        );
      }
      return;
    }
    
    if (!_isPendingStart) return;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission denied.'),
            backgroundColor: AppColors.emergencyRed,
          ),
        );
      }
      return;
    }

    final dir = await getTemporaryDirectory();
    final fileName = 'sos_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
    _recordedFilePath = '${dir.path}/$fileName';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100),
      path: _recordedFilePath!,
    );

    if (!_isPendingStart) {
      await _recorder.stop();
      return;
    }

    _recordingStartTime = DateTime.now();

    setState(() {
      _isRecording = true;
      _isRecorded = false;
      _secondsElapsed = 0;
      _uploadedUrl = null;
    });

    _pulseController.repeat(reverse: true);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _secondsElapsed++);
      if (_secondsElapsed >= 10) {
        timer.cancel();
        _isPendingStart = false;
        if (_isRecording) _stopRecording();
      }
    });
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    _pulseController.stop();
    await _recorder.stop();

    if (_recordingStartTime != null) {
      final duration = DateTime.now().difference(_recordingStartTime!).inMilliseconds;
      _recordingStartTime = null;
      if (duration < 1500) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Hold to record'),
              duration: Duration(seconds: 1),
            ),
          );
        }
        _discardRecording();
        return;
      }
    }

    if (mounted) {
      setState(() {
        _isRecording = false;
        _isRecorded = _recordedFilePath != null;
      });

      if (_isRecorded) {
        await _uploadAudio();
      }
    }
  }

  Future<void> _uploadAudio() async {
    if (_recordedFilePath == null) return;

    setState(() => _isUploading = true);

    try {
      final file = File(_recordedFilePath!);
      final fileName = 'sos_${AuthManager.deviceId}_${DateTime.now().millisecondsSinceEpoch}.m4a';

      // Step 1: Get signed upload URL from Serverpod
      String uploadDescription = await AuthManager.client.audio.getUploadDescription(fileName);
      
      final baseUri = Uri.parse(dotenv.env['API_URL'] ?? 'http://localhost:8080');
      final apiHost = baseUri.host;

      // Replace Serverpod's placeholder with the actual host
      // Handle both unencoded and URL-encoded versions of ${public_host}
      uploadDescription = uploadDescription
          .replaceAll('\${public_host}', apiHost)
          .replaceAll('\$%7Bpublic_host%7D', apiHost);

      // Step 2: Upload the file
      final bytes = await file.readAsBytes();
      
      // We must use ByteData for FileUploader
      final byteData = ByteData.view(bytes.buffer);
      
      final uploader = FileUploader(uploadDescription);
      final success = await uploader.uploadByteData(byteData);

      if (!success) {
        throw Exception('File upload failed.');
      }

      // Step 3: Verify and get public URL
      String publicUrl = await AuthManager.client.audio.verifyUpload(fileName);
      publicUrl = publicUrl
          .replaceAll('\${public_host}', apiHost)
          .replaceAll('\$%7Bpublic_host%7D', apiHost);

      if (!mounted) return;

      setState(() {
        _uploadedUrl = publicUrl;
        _isUploading = false;
      });

      widget.onRecorded(publicUrl);
    } catch (e) {
      debugPrint('Audio upload error: $e');
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: AppColors.emergencyRed,
          ),
        );
      }
    }
  }

  void _discardRecording() {
    _pulseController.stop();
    setState(() {
      _isRecording = false;
      _isRecorded = false;
      _uploadedUrl = null;
      _recordedFilePath = null;
      _secondsElapsed = 0;
    });
    widget.onRecorded(''); // Signal cleared to parent
  }

  String get _timerLabel {
    final remaining = 10 - _secondsElapsed;
    return _isRecording ? '${remaining}s remaining' : '${_secondsElapsed}s recorded';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.pitchBlack.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isRecording
              ? AppColors.emergencyRed
              : (_uploadedUrl != null ? Colors.green : Colors.grey.shade300),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.mic,
                color: _isRecording
                    ? AppColors.emergencyRed
                    : (_uploadedUrl != null ? Colors.green : Colors.grey),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Voice Note (max 10s)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              if (_uploadedUrl != null) ...[
                const Spacer(),
                GestureDetector(
                  onTap: _discardRecording,
                  child: const Icon(Icons.close, size: 16, color: Colors.grey),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (_uploadedUrl != null)
            // Recorded & uploaded state
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 16),
                  SizedBox(width: 8),
                  Text('Voice note attached ✓', style: TextStyle(color: Colors.green, fontSize: 13)),
                ],
              ),
            )
          else if (_isUploading)
            const Row(
              children: [
                SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.emergencyRed)),
                SizedBox(width: 12),
                Text('Uploading voice note...', style: TextStyle(fontSize: 13, color: Colors.grey)),
              ],
            )
          else
            // Record button
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please hold the button while speaking.'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                onLongPressDown: (_) {
                  HapticFeedback.mediumImpact();
                  _startRecording();
                },
                onLongPressEnd: (_) { 
                  _isPendingStart = false;
                  if (_isRecording) _stopRecording(); 
                },
                onLongPressCancel: () { 
                  _isPendingStart = false;
                  if (_isRecording) _stopRecording(); 
                },
                child: AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _isRecording ? _pulseAnimation.value : 1.0,
                      child: child,
                    );
                  },
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: _isRecording ? AppColors.emergencyRed : AppColors.pitchBlack,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isRecording ? Icons.stop : Icons.mic,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isRecording
                              ? '● REC — $_timerLabel'
                              : (_isRecorded ? 'Hold to Re-record' : 'Hold to Record, Release to Send'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_isRecording) ...[
            const SizedBox(height: 8),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _secondsElapsed / 10.0,
                backgroundColor: Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.emergencyRed),
                minHeight: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
