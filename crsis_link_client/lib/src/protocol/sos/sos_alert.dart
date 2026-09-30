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
import 'package:serverpod_auth_client/serverpod_auth_client.dart' as _i2;
import 'package:crsis_link_client/src/protocol/protocol.dart' as _i3;

abstract class SosAlert implements _i1.SerializableModel {
  SosAlert._({
    this.id,
    required this.userInfoId,
    this.userInfo,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.message,
    required this.isActive,
    required this.status,
    this.volunteerId,
  });

  factory SosAlert({
    int? id,
    required int userInfoId,
    _i2.UserInfo? userInfo,
    required double latitude,
    required double longitude,
    required DateTime timestamp,
    String? message,
    required bool isActive,
    required String status,
    int? volunteerId,
  }) = _SosAlertImpl;

  factory SosAlert.fromJson(Map<String, dynamic> jsonSerialization) {
    return SosAlert(
      id: jsonSerialization['id'] as int?,
      userInfoId: jsonSerialization['userInfoId'] as int,
      userInfo: jsonSerialization['userInfo'] == null
          ? null
          : _i3.Protocol().deserialize<_i2.UserInfo>(
              jsonSerialization['userInfo'],
            ),
      latitude: (jsonSerialization['latitude'] as num).toDouble(),
      longitude: (jsonSerialization['longitude'] as num).toDouble(),
      timestamp: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['timestamp'],
      ),
      message: jsonSerialization['message'] as String?,
      isActive: _i1.BoolJsonExtension.fromJson(jsonSerialization['isActive']),
      status: jsonSerialization['status'] as String,
      volunteerId: jsonSerialization['volunteerId'] as int?,
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  int? id;

  int userInfoId;

  _i2.UserInfo? userInfo;

  double latitude;

  double longitude;

  DateTime timestamp;

  String? message;

  bool isActive;

  String status;

  int? volunteerId;

  /// Returns a shallow copy of this [SosAlert]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  SosAlert copyWith({
    int? id,
    int? userInfoId,
    _i2.UserInfo? userInfo,
    double? latitude,
    double? longitude,
    DateTime? timestamp,
    String? message,
    bool? isActive,
    String? status,
    int? volunteerId,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'SosAlert',
      if (id != null) 'id': id,
      'userInfoId': userInfoId,
      if (userInfo != null) 'userInfo': userInfo?.toJson(),
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toJson(),
      if (message != null) 'message': message,
      'isActive': isActive,
      'status': status,
      if (volunteerId != null) 'volunteerId': volunteerId,
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
    required int userInfoId,
    _i2.UserInfo? userInfo,
    required double latitude,
    required double longitude,
    required DateTime timestamp,
    String? message,
    required bool isActive,
    required String status,
    int? volunteerId,
  }) : super._(
         id: id,
         userInfoId: userInfoId,
         userInfo: userInfo,
         latitude: latitude,
         longitude: longitude,
         timestamp: timestamp,
         message: message,
         isActive: isActive,
         status: status,
         volunteerId: volunteerId,
       );

  /// Returns a shallow copy of this [SosAlert]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  SosAlert copyWith({
    Object? id = _Undefined,
    int? userInfoId,
    Object? userInfo = _Undefined,
    double? latitude,
    double? longitude,
    DateTime? timestamp,
    Object? message = _Undefined,
    bool? isActive,
    String? status,
    Object? volunteerId = _Undefined,
  }) {
    return SosAlert(
      id: id is int? ? id : this.id,
      userInfoId: userInfoId ?? this.userInfoId,
      userInfo: userInfo is _i2.UserInfo?
          ? userInfo
          : this.userInfo?.copyWith(),
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timestamp: timestamp ?? this.timestamp,
      message: message is String? ? message : this.message,
      isActive: isActive ?? this.isActive,
      status: status ?? this.status,
      volunteerId: volunteerId is int? ? volunteerId : this.volunteerId,
    );
  }
}
