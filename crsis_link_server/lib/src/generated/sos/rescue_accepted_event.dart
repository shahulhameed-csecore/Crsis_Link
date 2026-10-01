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

import 'package:serverpod/serverpod.dart' as _i1;

abstract class RescueAcceptedEvent
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  RescueAcceptedEvent._({
    required this.victimDeviceId,
    required this.volunteerName,
  });

  factory RescueAcceptedEvent({
    required String victimDeviceId,
    required String volunteerName,
  }) = _RescueAcceptedEventImpl;

  factory RescueAcceptedEvent.fromJson(Map<String, dynamic> jsonSerialization) {
    return RescueAcceptedEvent(
      victimDeviceId: jsonSerialization['victimDeviceId'] as String,
      volunteerName: jsonSerialization['volunteerName'] as String,
    );
  }

  String victimDeviceId;

  String volunteerName;

  /// Returns a shallow copy of this [RescueAcceptedEvent]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  RescueAcceptedEvent copyWith({
    String? victimDeviceId,
    String? volunteerName,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'RescueAcceptedEvent',
      'victimDeviceId': victimDeviceId,
      'volunteerName': volunteerName,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'RescueAcceptedEvent',
      'victimDeviceId': victimDeviceId,
      'volunteerName': volunteerName,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _RescueAcceptedEventImpl extends RescueAcceptedEvent {
  _RescueAcceptedEventImpl({
    required String victimDeviceId,
    required String volunteerName,
  }) : super._(
         victimDeviceId: victimDeviceId,
         volunteerName: volunteerName,
       );

  /// Returns a shallow copy of this [RescueAcceptedEvent]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  RescueAcceptedEvent copyWith({
    String? victimDeviceId,
    String? volunteerName,
  }) {
    return RescueAcceptedEvent(
      victimDeviceId: victimDeviceId ?? this.victimDeviceId,
      volunteerName: volunteerName ?? this.volunteerName,
    );
  }
}
