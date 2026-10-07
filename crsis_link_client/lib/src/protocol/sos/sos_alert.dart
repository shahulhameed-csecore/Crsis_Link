/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters
// ignore_for_file: invalid_use_of_internal_member

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:serverpod_client/serverpod_client.dart' as _i1;

abstract class SosAlert implements _i1.SerializableModel {
  SosAlert._({
    this.id,
    required this.deviceId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.message,
    required this.isActive,
    required this.status,
    required this.senderName,
    this.volunteerDeviceId,
    this.audioUrl,
    this.verificationPin,
    bool? isRescuerVerified,
    bool? isVisuallyVerified,
    this.photoUrl,
    this.approximateLocationText,
    required this.clientAlertId,
    this.pinAttempts,
    this.pinLockedUntil,
  }) : isRescuerVerified = isRescuerVerified ?? false,
       isVisuallyVerified = isVisuallyVerified ?? false;

  factory SosAlert({
    int? id,
    required String deviceId,
    required double latitude,
    required double longitude,
    required DateTime timestamp,
    String? message,
    required bool isActive,
    required String status,
    required String senderName,
    String? volunteerDeviceId,
    String? audioUrl,
    String? verificationPin,
    bool? isRescuerVerified,
    bool? isVisuallyVerified,
    String? photoUrl,
    String? approximateLocationText,
    required String clientAlertId,
    int? pinAttempts,
    DateTime? pinLockedUntil,
  }) = _SosAlertImpl;

  factory SosAlert.fromJson(Map<String, dynamic> jsonSerialization) {
    return SosAlert(
      id: jsonSerialization['id'] as int?,
      deviceId: jsonSerialization['deviceId'] as String,
      latitude: (jsonSerialization['latitude'] as num).toDouble(),
      longitude: (jsonSerialization['longitude'] as num).toDouble(),
      timestamp: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['timestamp'],
      ),
      message: jsonSerialization['message'] as String?,
      isActive: _i1.BoolJsonExtension.fromJson(jsonSerialization['isActive']),
      status: jsonSerialization['status'] as String,
      senderName: jsonSerialization['senderName'] as String,
      volunteerDeviceId: jsonSerialization['volunteerDeviceId'] as String?,
      audioUrl: jsonSerialization['audioUrl'] as String?,
      verificationPin: jsonSerialization['verificationPin'] as String?,
      isRescuerVerified: jsonSerialization['isRescuerVerified'] == null
          ? null
          : _i1.BoolJsonExtension.fromJson(
              jsonSerialization['isRescuerVerified'],
            ),
      isVisuallyVerified: jsonSerialization['isVisuallyVerified'] == null
          ? null
          : _i1.BoolJsonExtension.fromJson(
              jsonSerialization['isVisuallyVerified'],
            ),
      photoUrl: jsonSerialization['photoUrl'] as String?,
      approximateLocationText:
          jsonSerialization['approximateLocationText'] as String?,
      clientAlertId: jsonSerialization['clientAlertId'] as String,
      pinAttempts: jsonSerialization['pinAttempts'] as int?,
      pinLockedUntil: jsonSerialization['pinLockedUntil'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(
              jsonSerialization['pinLockedUntil'],
            ),
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  int? id;

  String deviceId;

  double latitude;

  double longitude;

  DateTime timestamp;

  String? message;

  bool isActive;

  String status;

  String senderName;

  String? volunteerDeviceId;

  String? audioUrl;

  String? verificationPin;

  bool isRescuerVerified;

  bool isVisuallyVerified;

  String? photoUrl;

  String? approximateLocationText;

  String clientAlertId;

  int? pinAttempts;

  DateTime? pinLockedUntil;

  /// Returns a shallow copy of this [SosAlert]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  SosAlert copyWith({
    int? id,
    String? deviceId,
    double? latitude,
    double? longitude,
    DateTime? timestamp,
    String? message,
    bool? isActive,
    String? status,
    String? senderName,
    String? volunteerDeviceId,
    String? audioUrl,
    String? verificationPin,
    bool? isRescuerVerified,
    bool? isVisuallyVerified,
    String? photoUrl,
    String? approximateLocationText,
    String? clientAlertId,
    int? pinAttempts,
    DateTime? pinLockedUntil,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'SosAlert',
      if (id != null) 'id': id,
      'deviceId': deviceId,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toJson(),
      if (message != null) 'message': message,
      'isActive': isActive,
      'status': status,
      'senderName': senderName,
      if (volunteerDeviceId != null) 'volunteerDeviceId': volunteerDeviceId,
      if (audioUrl != null) 'audioUrl': audioUrl,
      if (verificationPin != null) 'verificationPin': verificationPin,
      'isRescuerVerified': isRescuerVerified,
      'isVisuallyVerified': isVisuallyVerified,
      if (photoUrl != null) 'photoUrl': photoUrl,
      if (approximateLocationText != null)
        'approximateLocationText': approximateLocationText,
      'clientAlertId': clientAlertId,
      if (pinAttempts != null) 'pinAttempts': pinAttempts,
      if (pinLockedUntil != null) 'pinLockedUntil': pinLockedUntil?.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _SosAlertImpl extends SosAlert {
  _SosAlertImpl({
    int? id,
    required String deviceId,
    required double latitude,
    required double longitude,
    required DateTime timestamp,
    String? message,
    required bool isActive,
    required String status,
    required String senderName,
    String? volunteerDeviceId,
    String? audioUrl,
    String? verificationPin,
    bool? isRescuerVerified,
    bool? isVisuallyVerified,
    String? photoUrl,
    String? approximateLocationText,
    required String clientAlertId,
    int? pinAttempts,
    DateTime? pinLockedUntil,
  }) : super._(
         id: id,
         deviceId: deviceId,
         latitude: latitude,
         longitude: longitude,
         timestamp: timestamp,
         message: message,
         isActive: isActive,
         status: status,
         senderName: senderName,
         volunteerDeviceId: volunteerDeviceId,
         audioUrl: audioUrl,
         verificationPin: verificationPin,
         isRescuerVerified: isRescuerVerified,
         isVisuallyVerified: isVisuallyVerified,
         photoUrl: photoUrl,
         approximateLocationText: approximateLocationText,
         clientAlertId: clientAlertId,
         pinAttempts: pinAttempts,
         pinLockedUntil: pinLockedUntil,
       );

  /// Returns a shallow copy of this [SosAlert]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  SosAlert copyWith({
    Object? id = _Undefined,
    String? deviceId,
    double? latitude,
    double? longitude,
    DateTime? timestamp,
    Object? message = _Undefined,
    bool? isActive,
    String? status,
    String? senderName,
    Object? volunteerDeviceId = _Undefined,
    Object? audioUrl = _Undefined,
    Object? verificationPin = _Undefined,
    bool? isRescuerVerified,
    bool? isVisuallyVerified,
    Object? photoUrl = _Undefined,
    Object? approximateLocationText = _Undefined,
    String? clientAlertId,
    Object? pinAttempts = _Undefined,
    Object? pinLockedUntil = _Undefined,
  }) {
    return SosAlert(
      id: id is int? ? id : this.id,
      deviceId: deviceId ?? this.deviceId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timestamp: timestamp ?? this.timestamp,
      message: message is String? ? message : this.message,
      isActive: isActive ?? this.isActive,
      status: status ?? this.status,
      senderName: senderName ?? this.senderName,
      volunteerDeviceId: volunteerDeviceId is String?
          ? volunteerDeviceId
          : this.volunteerDeviceId,
      audioUrl: audioUrl is String? ? audioUrl : this.audioUrl,
      verificationPin: verificationPin is String?
          ? verificationPin
          : this.verificationPin,
      isRescuerVerified: isRescuerVerified ?? this.isRescuerVerified,
      isVisuallyVerified: isVisuallyVerified ?? this.isVisuallyVerified,
      photoUrl: photoUrl is String? ? photoUrl : this.photoUrl,
      approximateLocationText: approximateLocationText is String?
          ? approximateLocationText
          : this.approximateLocationText,
      clientAlertId: clientAlertId ?? this.clientAlertId,
      pinAttempts: pinAttempts is int? ? pinAttempts : this.pinAttempts,
      pinLockedUntil: pinLockedUntil is DateTime?
          ? pinLockedUntil
          : this.pinLockedUntil,
    );
  }
}
