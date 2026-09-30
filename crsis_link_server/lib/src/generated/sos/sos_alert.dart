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
// ignore_for_file: unnecessary_null_comparison

import 'package:serverpod/serverpod.dart' as _i1;
import 'package:serverpod_auth_server/serverpod_auth_server.dart' as _i2;
import 'package:crsis_link_server/src/generated/protocol.dart' as _i3;

abstract class SosAlert
    implements _i1.TableRow<int?>, _i1.ProtocolSerialization {
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

  static final t = SosAlertTable();

  static const db = SosAlertRepository._();

  @override
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

  @override
  _i1.Table<int?> get table => t;

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
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'SosAlert',
      if (id != null) 'id': id,
      'userInfoId': userInfoId,
      if (userInfo != null) 'userInfo': userInfo?.toJsonForProtocol(),
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toJson(),
      if (message != null) 'message': message,
      'isActive': isActive,
      'status': status,
      if (volunteerId != null) 'volunteerId': volunteerId,
    };
  }

  static SosAlertInclude include({_i2.UserInfoInclude? userInfo}) {
    return SosAlertInclude._(userInfo: userInfo);
  }

  static SosAlertIncludeList includeList({
    _i1.WhereExpressionBuilder<SosAlertTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<SosAlertTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<SosAlertTable>? orderByList,
    SosAlertInclude? include,
  }) {
    return SosAlertIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(SosAlert.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(SosAlert.t),
      include: include,
    );
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

class SosAlertUpdateTable extends _i1.UpdateTable<SosAlertTable> {
  SosAlertUpdateTable(super.table);

  _i1.ColumnValue<int, int> userInfoId(int value) => _i1.ColumnValue(
    table.userInfoId,
    value,
  );

  _i1.ColumnValue<double, double> latitude(double value) => _i1.ColumnValue(
    table.latitude,
    value,
  );

  _i1.ColumnValue<double, double> longitude(double value) => _i1.ColumnValue(
    table.longitude,
    value,
  );

  _i1.ColumnValue<DateTime, DateTime> timestamp(DateTime value) =>
      _i1.ColumnValue(
        table.timestamp,
        value,
      );

  _i1.ColumnValue<String, String> message(String? value) => _i1.ColumnValue(
    table.message,
    value,
  );

  _i1.ColumnValue<bool, bool> isActive(bool value) => _i1.ColumnValue(
    table.isActive,
    value,
  );

  _i1.ColumnValue<String, String> status(String value) => _i1.ColumnValue(
    table.status,
    value,
  );

  _i1.ColumnValue<int, int> volunteerId(int? value) => _i1.ColumnValue(
    table.volunteerId,
    value,
  );
}

class SosAlertTable extends _i1.Table<int?> {
  SosAlertTable({super.tableRelation}) : super(tableName: 'sos_alert') {
    updateTable = SosAlertUpdateTable(this);
    userInfoId = _i1.ColumnInt(
      'userInfoId',
      this,
    );
    latitude = _i1.ColumnDouble(
      'latitude',
      this,
    );
    longitude = _i1.ColumnDouble(
      'longitude',
      this,
    );
    timestamp = _i1.ColumnDateTime(
      'timestamp',
      this,
    );
    message = _i1.ColumnString(
      'message',
      this,
    );
    isActive = _i1.ColumnBool(
      'isActive',
      this,
    );
    status = _i1.ColumnString(
      'status',
      this,
    );
    volunteerId = _i1.ColumnInt(
      'volunteerId',
      this,
    );
  }

  late final SosAlertUpdateTable updateTable;

  late final _i1.ColumnInt userInfoId;

  _i2.UserInfoTable? _userInfo;

  late final _i1.ColumnDouble latitude;

  late final _i1.ColumnDouble longitude;

  late final _i1.ColumnDateTime timestamp;

  late final _i1.ColumnString message;

  late final _i1.ColumnBool isActive;

  late final _i1.ColumnString status;

  late final _i1.ColumnInt volunteerId;

  _i2.UserInfoTable get userInfo {
    if (_userInfo != null) return _userInfo!;
    _userInfo = _i1.createRelationTable(
      relationFieldName: 'userInfo',
      field: SosAlert.t.userInfoId,
      foreignField: _i2.UserInfo.t.id,
      tableRelation: tableRelation,
      createTable: (foreignTableRelation) =>
          _i2.UserInfoTable(tableRelation: foreignTableRelation),
    );
    return _userInfo!;
  }

  @override
  List<_i1.Column> get columns => [
    id,
    userInfoId,
    latitude,
    longitude,
    timestamp,
    message,
    isActive,
    status,
    volunteerId,
  ];

  @override
  _i1.Table? getRelationTable(String relationField) {
    if (relationField == 'userInfo') {
      return userInfo;
    }
    return null;
  }
}

class SosAlertInclude extends _i1.IncludeObject {
  SosAlertInclude._({_i2.UserInfoInclude? userInfo}) {
    _userInfo = userInfo;
  }

  _i2.UserInfoInclude? _userInfo;

  @override
  Map<String, _i1.Include?> get includes => {'userInfo': _userInfo};

  @override
  _i1.Table<int?> get table => SosAlert.t;
}

class SosAlertIncludeList extends _i1.IncludeList {
  SosAlertIncludeList._({
    _i1.WhereExpressionBuilder<SosAlertTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(SosAlert.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<int?> get table => SosAlert.t;
}

class SosAlertRepository {
  const SosAlertRepository._();

  final attachRow = const SosAlertAttachRowRepository._();

  /// Returns a list of [SosAlert]s matching the given query parameters.
  ///
  /// Use [where] to specify which items to include in the return value.
  /// If none is specified, all items will be returned.
  ///
  /// To specify the order of the items use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// The maximum number of items can be set by [limit]. If no limit is set,
  /// all items matching the query will be returned.
  ///
  /// [offset] defines how many items to skip, after which [limit] (or all)
  /// items are read from the database.
  ///
  /// ```dart
  /// var persons = await Persons.db.find(
  ///   session,
  ///   where: (t) => t.lastName.equals('Jones'),
  ///   orderBy: (t) => t.firstName,
  ///   limit: 100,
  /// );
  /// ```
  Future<List<SosAlert>> find(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<SosAlertTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<SosAlertTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<SosAlertTable>? orderByList,
    _i1.Transaction? transaction,
    SosAlertInclude? include,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<SosAlert>(
      where: where?.call(SosAlert.t),
      orderBy: orderBy?.call(SosAlert.t),
      orderByList: orderByList?.call(SosAlert.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
      include: include,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [SosAlert] matching the given query parameters.
  ///
  /// Use [where] to specify which items to include in the return value.
  /// If none is specified, all items will be returned.
  ///
  /// To specify the order use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// [offset] defines how many items to skip, after which the next one will be picked.
  ///
  /// ```dart
  /// var youngestPerson = await Persons.db.findFirstRow(
  ///   session,
  ///   where: (t) => t.lastName.equals('Jones'),
  ///   orderBy: (t) => t.age,
  /// );
  /// ```
  Future<SosAlert?> findFirstRow(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<SosAlertTable>? where,
    int? offset,
    _i1.OrderByBuilder<SosAlertTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<SosAlertTable>? orderByList,
    _i1.Transaction? transaction,
    SosAlertInclude? include,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<SosAlert>(
      where: where?.call(SosAlert.t),
      orderBy: orderBy?.call(SosAlert.t),
      orderByList: orderByList?.call(SosAlert.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
      include: include,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [SosAlert] by its [id] or null if no such row exists.
  Future<SosAlert?> findById(
    _i1.DatabaseSession session,
    int id, {
    _i1.Transaction? transaction,
    SosAlertInclude? include,
    _i1.LockMode? lockMode,
    _i1.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<SosAlert>(
      id,
      transaction: transaction,
      include: include,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [SosAlert]s in the list and returns the inserted rows.
  ///
  /// The returned [SosAlert]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  Future<List<SosAlert>> insert(
    _i1.DatabaseSession session,
    List<SosAlert> rows, {
    _i1.Transaction? transaction,
    bool ignoreConflicts = false,
  }) async {
    return session.db.insert<SosAlert>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
    );
  }

  /// Inserts a single [SosAlert] and returns the inserted row.
  ///
  /// The returned [SosAlert] will have its `id` field set.
  Future<SosAlert> insertRow(
    _i1.DatabaseSession session,
    SosAlert row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<SosAlert>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [SosAlert]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<SosAlert>> update(
    _i1.DatabaseSession session,
    List<SosAlert> rows, {
    _i1.ColumnSelections<SosAlertTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<SosAlert>(
      rows,
      columns: columns?.call(SosAlert.t),
      transaction: transaction,
    );
  }

  /// Updates a single [SosAlert]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<SosAlert> updateRow(
    _i1.DatabaseSession session,
    SosAlert row, {
    _i1.ColumnSelections<SosAlertTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<SosAlert>(
      row,
      columns: columns?.call(SosAlert.t),
      transaction: transaction,
    );
  }

  /// Updates a single [SosAlert] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<SosAlert?> updateById(
    _i1.DatabaseSession session,
    int id, {
    required _i1.ColumnValueListBuilder<SosAlertUpdateTable> columnValues,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateById<SosAlert>(
      id,
      columnValues: columnValues(SosAlert.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [SosAlert]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  Future<List<SosAlert>> updateWhere(
    _i1.DatabaseSession session, {
    required _i1.ColumnValueListBuilder<SosAlertUpdateTable> columnValues,
    required _i1.WhereExpressionBuilder<SosAlertTable> where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<SosAlertTable>? orderBy,
    _i1.OrderByListBuilder<SosAlertTable>? orderByList,
    bool orderDescending = false,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateWhere<SosAlert>(
      columnValues: columnValues(SosAlert.t.updateTable),
      where: where(SosAlert.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(SosAlert.t),
      orderByList: orderByList?.call(SosAlert.t),
      orderDescending: orderDescending,
      transaction: transaction,
    );
  }

  /// Deletes all [SosAlert]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<SosAlert>> delete(
    _i1.DatabaseSession session,
    List<SosAlert> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<SosAlert>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [SosAlert].
  Future<SosAlert> deleteRow(
    _i1.DatabaseSession session,
    SosAlert row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<SosAlert>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<SosAlert>> deleteWhere(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<SosAlertTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<SosAlert>(
      where: where(SosAlert.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.DatabaseSession session, {
    _i1.WhereExpressionBuilder<SosAlertTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<SosAlert>(
      where: where?.call(SosAlert.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [SosAlert] rows matching the [where] expression.
  Future<void> lockRows(
    _i1.DatabaseSession session, {
    required _i1.WhereExpressionBuilder<SosAlertTable> where,
    required _i1.LockMode lockMode,
    required _i1.Transaction transaction,
    _i1.LockBehavior lockBehavior = _i1.LockBehavior.wait,
  }) async {
    return session.db.lockRows<SosAlert>(
      where: where(SosAlert.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}

class SosAlertAttachRowRepository {
  const SosAlertAttachRowRepository._();

  /// Creates a relation between the given [SosAlert] and [UserInfo]
  /// by setting the [SosAlert]'s foreign key `userInfoId` to refer to the [UserInfo].
  Future<void> userInfo(
    _i1.DatabaseSession session,
    SosAlert sosAlert,
    _i2.UserInfo userInfo, {
    _i1.Transaction? transaction,
  }) async {
    if (sosAlert.id == null) {
      throw ArgumentError.notNull('sosAlert.id');
    }
    if (userInfo.id == null) {
      throw ArgumentError.notNull('userInfo.id');
    }

    var $sosAlert = sosAlert.copyWith(userInfoId: userInfo.id);
    await session.db.updateRow<SosAlert>(
      $sosAlert,
      columns: [SosAlert.t.userInfoId],
      transaction: transaction,
    );
  }
}
