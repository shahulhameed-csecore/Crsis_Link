import 'package:serverpod/serverpod.dart';

/// Endpoint for handling audio file operations for SOS voice notes.
class AudioEndpoint extends Endpoint {

  /// Generates a pre-signed upload URL for an SOS audio file.
  /// Returns a JSON-encoded upload description string.
  Future<String> getUploadDescription(Session session, String fileName) async {
    session.log('Generating upload URL for audio file: $fileName', level: LogLevel.info);

    try {
      final uploadDescription = await session.storage.createDirectFileUploadDescription(
        storageId: 'public',
        path: 'sos_audio/$fileName',
      );
      return uploadDescription ?? '';
    } catch (e) {
      session.log('Failed to create upload description: $e', level: LogLevel.error);
      throw Exception('Failed to generate upload URL: $e');
    }
  }

  /// Verifies the upload completed and returns the public URL of the audio file.
  Future<String> verifyUpload(Session session, String fileName) async {
    session.log('Verifying upload for: $fileName', level: LogLevel.info);

    try {
      final verified = await session.storage.verifyDirectFileUpload(
        storageId: 'public',
        path: 'sos_audio/$fileName',
      );

      if (!verified) {
        throw Exception('Upload verification failed - file not found in storage.');
      }

      final publicUrl = await session.storage.getPublicUrl(
        storageId: 'public',
        path: 'sos_audio/$fileName',
      );

      if (publicUrl == null) {
        throw Exception('Failed to get public URL after upload.');
      }

      return publicUrl.toString();
    } catch (e) {
      session.log('Upload verification error: $e', level: LogLevel.error);
      throw Exception('Verification failed: $e');
    }
  }
}
