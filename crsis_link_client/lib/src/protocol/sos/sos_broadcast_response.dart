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
import '../sos/sos_alert.dart' as _i2;
import 'package:crsis_link_client/src/protocol/protocol.dart' as _i3;

abstract class SosBroadcastResponse implements _i1.SerializableModel {
  SosBroadcastResponse._({
    required this.alert,
    required this.notifiedCount,
  });

  factory SosBroadcastResponse({
    required _i2.SosAlert alert,
    required int notifiedCount,
  }) = _SosBroadcastResponseImpl;

  factory SosBroadcastResponse.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return SosBroadcastResponse(
      alert: _i3.Protocol().deserialize<_i2.SosAlert>(
        jsonSerialization['alert'],
      ),
      notifiedCount: jsonSerialization['notifiedCount'] as int,
    );
  }

  _i2.SosAlert alert;

  int notifiedCount;

  /// Returns a shallow copy of this [SosBroadcastResponse]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  SosBroadcastResponse copyWith({
    _i2.SosAlert? alert,
    int? notifiedCount,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'SosBroadcastResponse',
      'alert': alert.toJson(),
      'notifiedCount': notifiedCount,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _SosBroadcastResponseImpl extends SosBroadcastResponse {
  _SosBroadcastResponseImpl({
    required _i2.SosAlert alert,
    required int notifiedCount,
  }) : super._(
         alert: alert,
         notifiedCount: notifiedCount,
       );

  /// Returns a shallow copy of this [SosBroadcastResponse]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  SosBroadcastResponse copyWith({
    _i2.SosAlert? alert,
    int? notifiedCount,
  }) {
    return SosBroadcastResponse(
      alert: alert ?? this.alert.copyWith(),
      notifiedCount: notifiedCount ?? this.notifiedCount,
    );
  }
}
