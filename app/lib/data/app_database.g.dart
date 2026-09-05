// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ShiftScheduleRowsTable extends ShiftScheduleRows
    with TableInfo<$ShiftScheduleRowsTable, ShiftScheduleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ShiftScheduleRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _anchorDateMeta =
      const VerificationMeta('anchorDate');
  @override
  late final GeneratedColumn<DateTime> anchorDate = GeneratedColumn<DateTime>(
      'anchor_date', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _isCurrentMeta =
      const VerificationMeta('isCurrent');
  @override
  late final GeneratedColumn<bool> isCurrent = GeneratedColumn<bool>(
      'is_current', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_current" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _teamCountMeta =
      const VerificationMeta('teamCount');
  @override
  late final GeneratedColumn<int> teamCount = GeneratedColumn<int>(
      'team_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(4));
  static const VerificationMeta _teamNamesMeta =
      const VerificationMeta('teamNames');
  @override
  late final GeneratedColumn<String> teamNames = GeneratedColumn<String>(
      'team_names', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('一班,二班,三班,四班'));
  static const VerificationMeta _ourTeamIndexMeta =
      const VerificationMeta('ourTeamIndex');
  @override
  late final GeneratedColumn<int> ourTeamIndex = GeneratedColumn<int>(
      'our_team_index', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _teamOffsetsMeta =
      const VerificationMeta('teamOffsets');
  @override
  late final GeneratedColumn<String> teamOffsets = GeneratedColumn<String>(
      'team_offsets', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        anchorDate,
        isCurrent,
        teamCount,
        teamNames,
        ourTeamIndex,
        teamOffsets
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shift_schedule_rows';
  @override
  VerificationContext validateIntegrity(Insertable<ShiftScheduleRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('anchor_date')) {
      context.handle(
          _anchorDateMeta,
          anchorDate.isAcceptableOrUnknown(
              data['anchor_date']!, _anchorDateMeta));
    } else if (isInserting) {
      context.missing(_anchorDateMeta);
    }
    if (data.containsKey('is_current')) {
      context.handle(_isCurrentMeta,
          isCurrent.isAcceptableOrUnknown(data['is_current']!, _isCurrentMeta));
    }
    if (data.containsKey('team_count')) {
      context.handle(_teamCountMeta,
          teamCount.isAcceptableOrUnknown(data['team_count']!, _teamCountMeta));
    }
    if (data.containsKey('team_names')) {
      context.handle(_teamNamesMeta,
          teamNames.isAcceptableOrUnknown(data['team_names']!, _teamNamesMeta));
    }
    if (data.containsKey('our_team_index')) {
      context.handle(
          _ourTeamIndexMeta,
          ourTeamIndex.isAcceptableOrUnknown(
              data['our_team_index']!, _ourTeamIndexMeta));
    }
    if (data.containsKey('team_offsets')) {
      context.handle(
          _teamOffsetsMeta,
          teamOffsets.isAcceptableOrUnknown(
              data['team_offsets']!, _teamOffsetsMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ShiftScheduleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ShiftScheduleRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      anchorDate: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}anchor_date'])!,
      isCurrent: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_current'])!,
      teamCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}team_count'])!,
      teamNames: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}team_names'])!,
      ourTeamIndex: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}our_team_index'])!,
      teamOffsets: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}team_offsets'])!,
    );
  }

  @override
  $ShiftScheduleRowsTable createAlias(String alias) {
    return $ShiftScheduleRowsTable(attachedDatabase, alias);
  }
}

class ShiftScheduleRow extends DataClass
    implements Insertable<ShiftScheduleRow> {
  final int id;
  final String name;
  final DateTime anchorDate;
  final bool isCurrent;
  final int teamCount;
  final String teamNames;
  final int ourTeamIndex;
  final String teamOffsets;
  const ShiftScheduleRow(
      {required this.id,
      required this.name,
      required this.anchorDate,
      required this.isCurrent,
      required this.teamCount,
      required this.teamNames,
      required this.ourTeamIndex,
      required this.teamOffsets});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['anchor_date'] = Variable<DateTime>(anchorDate);
    map['is_current'] = Variable<bool>(isCurrent);
    map['team_count'] = Variable<int>(teamCount);
    map['team_names'] = Variable<String>(teamNames);
    map['our_team_index'] = Variable<int>(ourTeamIndex);
    map['team_offsets'] = Variable<String>(teamOffsets);
    return map;
  }

  ShiftScheduleRowsCompanion toCompanion(bool nullToAbsent) {
    return ShiftScheduleRowsCompanion(
      id: Value(id),
      name: Value(name),
      anchorDate: Value(anchorDate),
      isCurrent: Value(isCurrent),
      teamCount: Value(teamCount),
      teamNames: Value(teamNames),
      ourTeamIndex: Value(ourTeamIndex),
      teamOffsets: Value(teamOffsets),
    );
  }

  factory ShiftScheduleRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ShiftScheduleRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      anchorDate: serializer.fromJson<DateTime>(json['anchorDate']),
      isCurrent: serializer.fromJson<bool>(json['isCurrent']),
      teamCount: serializer.fromJson<int>(json['teamCount']),
      teamNames: serializer.fromJson<String>(json['teamNames']),
      ourTeamIndex: serializer.fromJson<int>(json['ourTeamIndex']),
      teamOffsets: serializer.fromJson<String>(json['teamOffsets']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'anchorDate': serializer.toJson<DateTime>(anchorDate),
      'isCurrent': serializer.toJson<bool>(isCurrent),
      'teamCount': serializer.toJson<int>(teamCount),
      'teamNames': serializer.toJson<String>(teamNames),
      'ourTeamIndex': serializer.toJson<int>(ourTeamIndex),
      'teamOffsets': serializer.toJson<String>(teamOffsets),
    };
  }

  ShiftScheduleRow copyWith(
          {int? id,
          String? name,
          DateTime? anchorDate,
          bool? isCurrent,
          int? teamCount,
          String? teamNames,
          int? ourTeamIndex,
          String? teamOffsets}) =>
      ShiftScheduleRow(
        id: id ?? this.id,
        name: name ?? this.name,
        anchorDate: anchorDate ?? this.anchorDate,
        isCurrent: isCurrent ?? this.isCurrent,
        teamCount: teamCount ?? this.teamCount,
        teamNames: teamNames ?? this.teamNames,
        ourTeamIndex: ourTeamIndex ?? this.ourTeamIndex,
        teamOffsets: teamOffsets ?? this.teamOffsets,
      );
  ShiftScheduleRow copyWithCompanion(ShiftScheduleRowsCompanion data) {
    return ShiftScheduleRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      anchorDate:
          data.anchorDate.present ? data.anchorDate.value : this.anchorDate,
      isCurrent: data.isCurrent.present ? data.isCurrent.value : this.isCurrent,
      teamCount: data.teamCount.present ? data.teamCount.value : this.teamCount,
      teamNames: data.teamNames.present ? data.teamNames.value : this.teamNames,
      ourTeamIndex: data.ourTeamIndex.present
          ? data.ourTeamIndex.value
          : this.ourTeamIndex,
      teamOffsets:
          data.teamOffsets.present ? data.teamOffsets.value : this.teamOffsets,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ShiftScheduleRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('anchorDate: $anchorDate, ')
          ..write('isCurrent: $isCurrent, ')
          ..write('teamCount: $teamCount, ')
          ..write('teamNames: $teamNames, ')
          ..write('ourTeamIndex: $ourTeamIndex, ')
          ..write('teamOffsets: $teamOffsets')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, anchorDate, isCurrent, teamCount,
      teamNames, ourTeamIndex, teamOffsets);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ShiftScheduleRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.anchorDate == this.anchorDate &&
          other.isCurrent == this.isCurrent &&
          other.teamCount == this.teamCount &&
          other.teamNames == this.teamNames &&
          other.ourTeamIndex == this.ourTeamIndex &&
          other.teamOffsets == this.teamOffsets);
}

class ShiftScheduleRowsCompanion extends UpdateCompanion<ShiftScheduleRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<DateTime> anchorDate;
  final Value<bool> isCurrent;
  final Value<int> teamCount;
  final Value<String> teamNames;
  final Value<int> ourTeamIndex;
  final Value<String> teamOffsets;
  const ShiftScheduleRowsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.anchorDate = const Value.absent(),
    this.isCurrent = const Value.absent(),
    this.teamCount = const Value.absent(),
    this.teamNames = const Value.absent(),
    this.ourTeamIndex = const Value.absent(),
    this.teamOffsets = const Value.absent(),
  });
  ShiftScheduleRowsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required DateTime anchorDate,
    this.isCurrent = const Value.absent(),
    this.teamCount = const Value.absent(),
    this.teamNames = const Value.absent(),
    this.ourTeamIndex = const Value.absent(),
    this.teamOffsets = const Value.absent(),
  })  : name = Value(name),
        anchorDate = Value(anchorDate);
  static Insertable<ShiftScheduleRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<DateTime>? anchorDate,
    Expression<bool>? isCurrent,
    Expression<int>? teamCount,
    Expression<String>? teamNames,
    Expression<int>? ourTeamIndex,
    Expression<String>? teamOffsets,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (anchorDate != null) 'anchor_date': anchorDate,
      if (isCurrent != null) 'is_current': isCurrent,
      if (teamCount != null) 'team_count': teamCount,
      if (teamNames != null) 'team_names': teamNames,
      if (ourTeamIndex != null) 'our_team_index': ourTeamIndex,
      if (teamOffsets != null) 'team_offsets': teamOffsets,
    });
  }

  ShiftScheduleRowsCompanion copyWith(
      {Value<int>? id,
      Value<String>? name,
      Value<DateTime>? anchorDate,
      Value<bool>? isCurrent,
      Value<int>? teamCount,
      Value<String>? teamNames,
      Value<int>? ourTeamIndex,
      Value<String>? teamOffsets}) {
    return ShiftScheduleRowsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      anchorDate: anchorDate ?? this.anchorDate,
      isCurrent: isCurrent ?? this.isCurrent,
      teamCount: teamCount ?? this.teamCount,
      teamNames: teamNames ?? this.teamNames,
      ourTeamIndex: ourTeamIndex ?? this.ourTeamIndex,
      teamOffsets: teamOffsets ?? this.teamOffsets,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (anchorDate.present) {
      map['anchor_date'] = Variable<DateTime>(anchorDate.value);
    }
    if (isCurrent.present) {
      map['is_current'] = Variable<bool>(isCurrent.value);
    }
    if (teamCount.present) {
      map['team_count'] = Variable<int>(teamCount.value);
    }
    if (teamNames.present) {
      map['team_names'] = Variable<String>(teamNames.value);
    }
    if (ourTeamIndex.present) {
      map['our_team_index'] = Variable<int>(ourTeamIndex.value);
    }
    if (teamOffsets.present) {
      map['team_offsets'] = Variable<String>(teamOffsets.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ShiftScheduleRowsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('anchorDate: $anchorDate, ')
          ..write('isCurrent: $isCurrent, ')
          ..write('teamCount: $teamCount, ')
          ..write('teamNames: $teamNames, ')
          ..write('ourTeamIndex: $ourTeamIndex, ')
          ..write('teamOffsets: $teamOffsets')
          ..write(')'))
        .toString();
  }
}

class $ShiftTypeRowsTable extends ShiftTypeRows
    with TableInfo<$ShiftTypeRowsTable, ShiftTypeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ShiftTypeRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _scheduleIdMeta =
      const VerificationMeta('scheduleId');
  @override
  late final GeneratedColumn<int> scheduleId = GeneratedColumn<int>(
      'schedule_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _orderMeta = const VerificationMeta('order');
  @override
  late final GeneratedColumn<int> order = GeneratedColumn<int>(
      'order', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _startMinuteMeta =
      const VerificationMeta('startMinute');
  @override
  late final GeneratedColumn<int> startMinute = GeneratedColumn<int>(
      'start_minute', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _endMinuteMeta =
      const VerificationMeta('endMinute');
  @override
  late final GeneratedColumn<int> endMinute = GeneratedColumn<int>(
      'end_minute', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _isRestMeta = const VerificationMeta('isRest');
  @override
  late final GeneratedColumn<bool> isRest = GeneratedColumn<bool>(
      'is_rest', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_rest" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<int> color = GeneratedColumn<int>(
      'color', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0xFF5B7FFF));
  static const VerificationMeta _alarmEnabledMeta =
      const VerificationMeta('alarmEnabled');
  @override
  late final GeneratedColumn<bool> alarmEnabled = GeneratedColumn<bool>(
      'alarm_enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("alarm_enabled" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _alarmMinuteMeta =
      const VerificationMeta('alarmMinute');
  @override
  late final GeneratedColumn<int> alarmMinute = GeneratedColumn<int>(
      'alarm_minute', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        scheduleId,
        order,
        name,
        startMinute,
        endMinute,
        isRest,
        color,
        alarmEnabled,
        alarmMinute
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shift_type_rows';
  @override
  VerificationContext validateIntegrity(Insertable<ShiftTypeRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('schedule_id')) {
      context.handle(
          _scheduleIdMeta,
          scheduleId.isAcceptableOrUnknown(
              data['schedule_id']!, _scheduleIdMeta));
    } else if (isInserting) {
      context.missing(_scheduleIdMeta);
    }
    if (data.containsKey('order')) {
      context.handle(
          _orderMeta, order.isAcceptableOrUnknown(data['order']!, _orderMeta));
    } else if (isInserting) {
      context.missing(_orderMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('start_minute')) {
      context.handle(
          _startMinuteMeta,
          startMinute.isAcceptableOrUnknown(
              data['start_minute']!, _startMinuteMeta));
    }
    if (data.containsKey('end_minute')) {
      context.handle(_endMinuteMeta,
          endMinute.isAcceptableOrUnknown(data['end_minute']!, _endMinuteMeta));
    }
    if (data.containsKey('is_rest')) {
      context.handle(_isRestMeta,
          isRest.isAcceptableOrUnknown(data['is_rest']!, _isRestMeta));
    }
    if (data.containsKey('color')) {
      context.handle(
          _colorMeta, color.isAcceptableOrUnknown(data['color']!, _colorMeta));
    }
    if (data.containsKey('alarm_enabled')) {
      context.handle(
          _alarmEnabledMeta,
          alarmEnabled.isAcceptableOrUnknown(
              data['alarm_enabled']!, _alarmEnabledMeta));
    }
    if (data.containsKey('alarm_minute')) {
      context.handle(
          _alarmMinuteMeta,
          alarmMinute.isAcceptableOrUnknown(
              data['alarm_minute']!, _alarmMinuteMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ShiftTypeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ShiftTypeRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      scheduleId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}schedule_id'])!,
      order: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}order'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      startMinute: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}start_minute']),
      endMinute: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}end_minute']),
      isRest: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_rest'])!,
      color: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}color'])!,
      alarmEnabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}alarm_enabled'])!,
      alarmMinute: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}alarm_minute']),
    );
  }

  @override
  $ShiftTypeRowsTable createAlias(String alias) {
    return $ShiftTypeRowsTable(attachedDatabase, alias);
  }
}

class ShiftTypeRow extends DataClass implements Insertable<ShiftTypeRow> {
  final int id;
  final int scheduleId;
  final int order;
  final String name;
  final int? startMinute;
  final int? endMinute;
  final bool isRest;
  final int color;
  final bool alarmEnabled;
  final int? alarmMinute;
  const ShiftTypeRow(
      {required this.id,
      required this.scheduleId,
      required this.order,
      required this.name,
      this.startMinute,
      this.endMinute,
      required this.isRest,
      required this.color,
      required this.alarmEnabled,
      this.alarmMinute});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['schedule_id'] = Variable<int>(scheduleId);
    map['order'] = Variable<int>(order);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || startMinute != null) {
      map['start_minute'] = Variable<int>(startMinute);
    }
    if (!nullToAbsent || endMinute != null) {
      map['end_minute'] = Variable<int>(endMinute);
    }
    map['is_rest'] = Variable<bool>(isRest);
    map['color'] = Variable<int>(color);
    map['alarm_enabled'] = Variable<bool>(alarmEnabled);
    if (!nullToAbsent || alarmMinute != null) {
      map['alarm_minute'] = Variable<int>(alarmMinute);
    }
    return map;
  }

  ShiftTypeRowsCompanion toCompanion(bool nullToAbsent) {
    return ShiftTypeRowsCompanion(
      id: Value(id),
      scheduleId: Value(scheduleId),
      order: Value(order),
      name: Value(name),
      startMinute: startMinute == null && nullToAbsent
          ? const Value.absent()
          : Value(startMinute),
      endMinute: endMinute == null && nullToAbsent
          ? const Value.absent()
          : Value(endMinute),
      isRest: Value(isRest),
      color: Value(color),
      alarmEnabled: Value(alarmEnabled),
      alarmMinute: alarmMinute == null && nullToAbsent
          ? const Value.absent()
          : Value(alarmMinute),
    );
  }

  factory ShiftTypeRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ShiftTypeRow(
      id: serializer.fromJson<int>(json['id']),
      scheduleId: serializer.fromJson<int>(json['scheduleId']),
      order: serializer.fromJson<int>(json['order']),
      name: serializer.fromJson<String>(json['name']),
      startMinute: serializer.fromJson<int?>(json['startMinute']),
      endMinute: serializer.fromJson<int?>(json['endMinute']),
      isRest: serializer.fromJson<bool>(json['isRest']),
      color: serializer.fromJson<int>(json['color']),
      alarmEnabled: serializer.fromJson<bool>(json['alarmEnabled']),
      alarmMinute: serializer.fromJson<int?>(json['alarmMinute']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'scheduleId': serializer.toJson<int>(scheduleId),
      'order': serializer.toJson<int>(order),
      'name': serializer.toJson<String>(name),
      'startMinute': serializer.toJson<int?>(startMinute),
      'endMinute': serializer.toJson<int?>(endMinute),
      'isRest': serializer.toJson<bool>(isRest),
      'color': serializer.toJson<int>(color),
      'alarmEnabled': serializer.toJson<bool>(alarmEnabled),
      'alarmMinute': serializer.toJson<int?>(alarmMinute),
    };
  }

  ShiftTypeRow copyWith(
          {int? id,
          int? scheduleId,
          int? order,
          String? name,
          Value<int?> startMinute = const Value.absent(),
          Value<int?> endMinute = const Value.absent(),
          bool? isRest,
          int? color,
          bool? alarmEnabled,
          Value<int?> alarmMinute = const Value.absent()}) =>
      ShiftTypeRow(
        id: id ?? this.id,
        scheduleId: scheduleId ?? this.scheduleId,
        order: order ?? this.order,
        name: name ?? this.name,
        startMinute: startMinute.present ? startMinute.value : this.startMinute,
        endMinute: endMinute.present ? endMinute.value : this.endMinute,
        isRest: isRest ?? this.isRest,
        color: color ?? this.color,
        alarmEnabled: alarmEnabled ?? this.alarmEnabled,
        alarmMinute: alarmMinute.present ? alarmMinute.value : this.alarmMinute,
      );
  ShiftTypeRow copyWithCompanion(ShiftTypeRowsCompanion data) {
    return ShiftTypeRow(
      id: data.id.present ? data.id.value : this.id,
      scheduleId:
          data.scheduleId.present ? data.scheduleId.value : this.scheduleId,
      order: data.order.present ? data.order.value : this.order,
      name: data.name.present ? data.name.value : this.name,
      startMinute:
          data.startMinute.present ? data.startMinute.value : this.startMinute,
      endMinute: data.endMinute.present ? data.endMinute.value : this.endMinute,
      isRest: data.isRest.present ? data.isRest.value : this.isRest,
      color: data.color.present ? data.color.value : this.color,
      alarmEnabled: data.alarmEnabled.present
          ? data.alarmEnabled.value
          : this.alarmEnabled,
      alarmMinute:
          data.alarmMinute.present ? data.alarmMinute.value : this.alarmMinute,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ShiftTypeRow(')
          ..write('id: $id, ')
          ..write('scheduleId: $scheduleId, ')
          ..write('order: $order, ')
          ..write('name: $name, ')
          ..write('startMinute: $startMinute, ')
          ..write('endMinute: $endMinute, ')
          ..write('isRest: $isRest, ')
          ..write('color: $color, ')
          ..write('alarmEnabled: $alarmEnabled, ')
          ..write('alarmMinute: $alarmMinute')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, scheduleId, order, name, startMinute,
      endMinute, isRest, color, alarmEnabled, alarmMinute);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ShiftTypeRow &&
          other.id == this.id &&
          other.scheduleId == this.scheduleId &&
          other.order == this.order &&
          other.name == this.name &&
          other.startMinute == this.startMinute &&
          other.endMinute == this.endMinute &&
          other.isRest == this.isRest &&
          other.color == this.color &&
          other.alarmEnabled == this.alarmEnabled &&
          other.alarmMinute == this.alarmMinute);
}

class ShiftTypeRowsCompanion extends UpdateCompanion<ShiftTypeRow> {
  final Value<int> id;
  final Value<int> scheduleId;
  final Value<int> order;
  final Value<String> name;
  final Value<int?> startMinute;
  final Value<int?> endMinute;
  final Value<bool> isRest;
  final Value<int> color;
  final Value<bool> alarmEnabled;
  final Value<int?> alarmMinute;
  const ShiftTypeRowsCompanion({
    this.id = const Value.absent(),
    this.scheduleId = const Value.absent(),
    this.order = const Value.absent(),
    this.name = const Value.absent(),
    this.startMinute = const Value.absent(),
    this.endMinute = const Value.absent(),
    this.isRest = const Value.absent(),
    this.color = const Value.absent(),
    this.alarmEnabled = const Value.absent(),
    this.alarmMinute = const Value.absent(),
  });
  ShiftTypeRowsCompanion.insert({
    this.id = const Value.absent(),
    required int scheduleId,
    required int order,
    required String name,
    this.startMinute = const Value.absent(),
    this.endMinute = const Value.absent(),
    this.isRest = const Value.absent(),
    this.color = const Value.absent(),
    this.alarmEnabled = const Value.absent(),
    this.alarmMinute = const Value.absent(),
  })  : scheduleId = Value(scheduleId),
        order = Value(order),
        name = Value(name);
  static Insertable<ShiftTypeRow> custom({
    Expression<int>? id,
    Expression<int>? scheduleId,
    Expression<int>? order,
    Expression<String>? name,
    Expression<int>? startMinute,
    Expression<int>? endMinute,
    Expression<bool>? isRest,
    Expression<int>? color,
    Expression<bool>? alarmEnabled,
    Expression<int>? alarmMinute,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (scheduleId != null) 'schedule_id': scheduleId,
      if (order != null) 'order': order,
      if (name != null) 'name': name,
      if (startMinute != null) 'start_minute': startMinute,
      if (endMinute != null) 'end_minute': endMinute,
      if (isRest != null) 'is_rest': isRest,
      if (color != null) 'color': color,
      if (alarmEnabled != null) 'alarm_enabled': alarmEnabled,
      if (alarmMinute != null) 'alarm_minute': alarmMinute,
    });
  }

  ShiftTypeRowsCompanion copyWith(
      {Value<int>? id,
      Value<int>? scheduleId,
      Value<int>? order,
      Value<String>? name,
      Value<int?>? startMinute,
      Value<int?>? endMinute,
      Value<bool>? isRest,
      Value<int>? color,
      Value<bool>? alarmEnabled,
      Value<int?>? alarmMinute}) {
    return ShiftTypeRowsCompanion(
      id: id ?? this.id,
      scheduleId: scheduleId ?? this.scheduleId,
      order: order ?? this.order,
      name: name ?? this.name,
      startMinute: startMinute ?? this.startMinute,
      endMinute: endMinute ?? this.endMinute,
      isRest: isRest ?? this.isRest,
      color: color ?? this.color,
      alarmEnabled: alarmEnabled ?? this.alarmEnabled,
      alarmMinute: alarmMinute ?? this.alarmMinute,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (scheduleId.present) {
      map['schedule_id'] = Variable<int>(scheduleId.value);
    }
    if (order.present) {
      map['order'] = Variable<int>(order.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (startMinute.present) {
      map['start_minute'] = Variable<int>(startMinute.value);
    }
    if (endMinute.present) {
      map['end_minute'] = Variable<int>(endMinute.value);
    }
    if (isRest.present) {
      map['is_rest'] = Variable<bool>(isRest.value);
    }
    if (color.present) {
      map['color'] = Variable<int>(color.value);
    }
    if (alarmEnabled.present) {
      map['alarm_enabled'] = Variable<bool>(alarmEnabled.value);
    }
    if (alarmMinute.present) {
      map['alarm_minute'] = Variable<int>(alarmMinute.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ShiftTypeRowsCompanion(')
          ..write('id: $id, ')
          ..write('scheduleId: $scheduleId, ')
          ..write('order: $order, ')
          ..write('name: $name, ')
          ..write('startMinute: $startMinute, ')
          ..write('endMinute: $endMinute, ')
          ..write('isRest: $isRest, ')
          ..write('color: $color, ')
          ..write('alarmEnabled: $alarmEnabled, ')
          ..write('alarmMinute: $alarmMinute')
          ..write(')'))
        .toString();
  }
}

class $ScheduleEventsTable extends ScheduleEvents
    with TableInfo<$ScheduleEventsTable, ScheduleEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ScheduleEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
      'date', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _timeMinuteMeta =
      const VerificationMeta('timeMinute');
  @override
  late final GeneratedColumn<int> timeMinute = GeneratedColumn<int>(
      'time_minute', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _advanceRemindMinutesMeta =
      const VerificationMeta('advanceRemindMinutes');
  @override
  late final GeneratedColumn<int> advanceRemindMinutes = GeneratedColumn<int>(
      'advance_remind_minutes', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _isCompletedMeta =
      const VerificationMeta('isCompleted');
  @override
  late final GeneratedColumn<bool> isCompleted = GeneratedColumn<bool>(
      'is_completed', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_completed" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        title,
        date,
        timeMinute,
        advanceRemindMinutes,
        isCompleted,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'schedule_events';
  @override
  VerificationContext validateIntegrity(Insertable<ScheduleEvent> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
          _dateMeta, date.isAcceptableOrUnknown(data['date']!, _dateMeta));
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('time_minute')) {
      context.handle(
          _timeMinuteMeta,
          timeMinute.isAcceptableOrUnknown(
              data['time_minute']!, _timeMinuteMeta));
    }
    if (data.containsKey('advance_remind_minutes')) {
      context.handle(
          _advanceRemindMinutesMeta,
          advanceRemindMinutes.isAcceptableOrUnknown(
              data['advance_remind_minutes']!, _advanceRemindMinutesMeta));
    }
    if (data.containsKey('is_completed')) {
      context.handle(
          _isCompletedMeta,
          isCompleted.isAcceptableOrUnknown(
              data['is_completed']!, _isCompletedMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ScheduleEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ScheduleEvent(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      date: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}date'])!,
      timeMinute: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}time_minute']),
      advanceRemindMinutes: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}advance_remind_minutes']),
      isCompleted: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_completed'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $ScheduleEventsTable createAlias(String alias) {
    return $ScheduleEventsTable(attachedDatabase, alias);
  }
}

class ScheduleEvent extends DataClass implements Insertable<ScheduleEvent> {
  final int id;
  final String title;
  final DateTime date;
  final int? timeMinute;
  final int? advanceRemindMinutes;
  final bool isCompleted;
  final DateTime createdAt;
  const ScheduleEvent(
      {required this.id,
      required this.title,
      required this.date,
      this.timeMinute,
      this.advanceRemindMinutes,
      required this.isCompleted,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    map['date'] = Variable<DateTime>(date);
    if (!nullToAbsent || timeMinute != null) {
      map['time_minute'] = Variable<int>(timeMinute);
    }
    if (!nullToAbsent || advanceRemindMinutes != null) {
      map['advance_remind_minutes'] = Variable<int>(advanceRemindMinutes);
    }
    map['is_completed'] = Variable<bool>(isCompleted);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ScheduleEventsCompanion toCompanion(bool nullToAbsent) {
    return ScheduleEventsCompanion(
      id: Value(id),
      title: Value(title),
      date: Value(date),
      timeMinute: timeMinute == null && nullToAbsent
          ? const Value.absent()
          : Value(timeMinute),
      advanceRemindMinutes: advanceRemindMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(advanceRemindMinutes),
      isCompleted: Value(isCompleted),
      createdAt: Value(createdAt),
    );
  }

  factory ScheduleEvent.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ScheduleEvent(
      id: serializer.fromJson<int>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      date: serializer.fromJson<DateTime>(json['date']),
      timeMinute: serializer.fromJson<int?>(json['timeMinute']),
      advanceRemindMinutes:
          serializer.fromJson<int?>(json['advanceRemindMinutes']),
      isCompleted: serializer.fromJson<bool>(json['isCompleted']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'date': serializer.toJson<DateTime>(date),
      'timeMinute': serializer.toJson<int?>(timeMinute),
      'advanceRemindMinutes': serializer.toJson<int?>(advanceRemindMinutes),
      'isCompleted': serializer.toJson<bool>(isCompleted),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ScheduleEvent copyWith(
          {int? id,
          String? title,
          DateTime? date,
          Value<int?> timeMinute = const Value.absent(),
          Value<int?> advanceRemindMinutes = const Value.absent(),
          bool? isCompleted,
          DateTime? createdAt}) =>
      ScheduleEvent(
        id: id ?? this.id,
        title: title ?? this.title,
        date: date ?? this.date,
        timeMinute: timeMinute.present ? timeMinute.value : this.timeMinute,
        advanceRemindMinutes: advanceRemindMinutes.present
            ? advanceRemindMinutes.value
            : this.advanceRemindMinutes,
        isCompleted: isCompleted ?? this.isCompleted,
        createdAt: createdAt ?? this.createdAt,
      );
  ScheduleEvent copyWithCompanion(ScheduleEventsCompanion data) {
    return ScheduleEvent(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      date: data.date.present ? data.date.value : this.date,
      timeMinute:
          data.timeMinute.present ? data.timeMinute.value : this.timeMinute,
      advanceRemindMinutes: data.advanceRemindMinutes.present
          ? data.advanceRemindMinutes.value
          : this.advanceRemindMinutes,
      isCompleted:
          data.isCompleted.present ? data.isCompleted.value : this.isCompleted,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ScheduleEvent(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('date: $date, ')
          ..write('timeMinute: $timeMinute, ')
          ..write('advanceRemindMinutes: $advanceRemindMinutes, ')
          ..write('isCompleted: $isCompleted, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, title, date, timeMinute,
      advanceRemindMinutes, isCompleted, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleEvent &&
          other.id == this.id &&
          other.title == this.title &&
          other.date == this.date &&
          other.timeMinute == this.timeMinute &&
          other.advanceRemindMinutes == this.advanceRemindMinutes &&
          other.isCompleted == this.isCompleted &&
          other.createdAt == this.createdAt);
}

class ScheduleEventsCompanion extends UpdateCompanion<ScheduleEvent> {
  final Value<int> id;
  final Value<String> title;
  final Value<DateTime> date;
  final Value<int?> timeMinute;
  final Value<int?> advanceRemindMinutes;
  final Value<bool> isCompleted;
  final Value<DateTime> createdAt;
  const ScheduleEventsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.date = const Value.absent(),
    this.timeMinute = const Value.absent(),
    this.advanceRemindMinutes = const Value.absent(),
    this.isCompleted = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ScheduleEventsCompanion.insert({
    this.id = const Value.absent(),
    required String title,
    required DateTime date,
    this.timeMinute = const Value.absent(),
    this.advanceRemindMinutes = const Value.absent(),
    this.isCompleted = const Value.absent(),
    required DateTime createdAt,
  })  : title = Value(title),
        date = Value(date),
        createdAt = Value(createdAt);
  static Insertable<ScheduleEvent> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<DateTime>? date,
    Expression<int>? timeMinute,
    Expression<int>? advanceRemindMinutes,
    Expression<bool>? isCompleted,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (date != null) 'date': date,
      if (timeMinute != null) 'time_minute': timeMinute,
      if (advanceRemindMinutes != null)
        'advance_remind_minutes': advanceRemindMinutes,
      if (isCompleted != null) 'is_completed': isCompleted,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ScheduleEventsCompanion copyWith(
      {Value<int>? id,
      Value<String>? title,
      Value<DateTime>? date,
      Value<int?>? timeMinute,
      Value<int?>? advanceRemindMinutes,
      Value<bool>? isCompleted,
      Value<DateTime>? createdAt}) {
    return ScheduleEventsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      date: date ?? this.date,
      timeMinute: timeMinute ?? this.timeMinute,
      advanceRemindMinutes: advanceRemindMinutes ?? this.advanceRemindMinutes,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (timeMinute.present) {
      map['time_minute'] = Variable<int>(timeMinute.value);
    }
    if (advanceRemindMinutes.present) {
      map['advance_remind_minutes'] = Variable<int>(advanceRemindMinutes.value);
    }
    if (isCompleted.present) {
      map['is_completed'] = Variable<bool>(isCompleted.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScheduleEventsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('date: $date, ')
          ..write('timeMinute: $timeMinute, ')
          ..write('advanceRemindMinutes: $advanceRemindMinutes, ')
          ..write('isCompleted: $isCompleted, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $CustomAlarmsTable extends CustomAlarms
    with TableInfo<$CustomAlarmsTable, CustomAlarm> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CustomAlarmsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _hourMeta = const VerificationMeta('hour');
  @override
  late final GeneratedColumn<int> hour = GeneratedColumn<int>(
      'hour', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _minuteMeta = const VerificationMeta('minute');
  @override
  late final GeneratedColumn<int> minute = GeneratedColumn<int>(
      'minute', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _repeatTypeMeta =
      const VerificationMeta('repeatType');
  @override
  late final GeneratedColumn<int> repeatType = GeneratedColumn<int>(
      'repeat_type', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _onceDateMeta =
      const VerificationMeta('onceDate');
  @override
  late final GeneratedColumn<DateTime> onceDate = GeneratedColumn<DateTime>(
      'once_date', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _weekdaysMeta =
      const VerificationMeta('weekdays');
  @override
  late final GeneratedColumn<int> weekdays = GeneratedColumn<int>(
      'weekdays', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _enabledMeta =
      const VerificationMeta('enabled');
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
      'enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("enabled" IN (0, 1))'),
      defaultValue: const Constant(true));
  @override
  List<GeneratedColumn> get $columns =>
      [id, hour, minute, repeatType, onceDate, weekdays, enabled];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'custom_alarms';
  @override
  VerificationContext validateIntegrity(Insertable<CustomAlarm> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('hour')) {
      context.handle(
          _hourMeta, hour.isAcceptableOrUnknown(data['hour']!, _hourMeta));
    } else if (isInserting) {
      context.missing(_hourMeta);
    }
    if (data.containsKey('minute')) {
      context.handle(_minuteMeta,
          minute.isAcceptableOrUnknown(data['minute']!, _minuteMeta));
    } else if (isInserting) {
      context.missing(_minuteMeta);
    }
    if (data.containsKey('repeat_type')) {
      context.handle(
          _repeatTypeMeta,
          repeatType.isAcceptableOrUnknown(
              data['repeat_type']!, _repeatTypeMeta));
    }
    if (data.containsKey('once_date')) {
      context.handle(_onceDateMeta,
          onceDate.isAcceptableOrUnknown(data['once_date']!, _onceDateMeta));
    }
    if (data.containsKey('weekdays')) {
      context.handle(_weekdaysMeta,
          weekdays.isAcceptableOrUnknown(data['weekdays']!, _weekdaysMeta));
    }
    if (data.containsKey('enabled')) {
      context.handle(_enabledMeta,
          enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CustomAlarm map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CustomAlarm(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      hour: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}hour'])!,
      minute: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}minute'])!,
      repeatType: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}repeat_type'])!,
      onceDate: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}once_date']),
      weekdays: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}weekdays'])!,
      enabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}enabled'])!,
    );
  }

  @override
  $CustomAlarmsTable createAlias(String alias) {
    return $CustomAlarmsTable(attachedDatabase, alias);
  }
}

class CustomAlarm extends DataClass implements Insertable<CustomAlarm> {
  final int id;
  final int hour;
  final int minute;

  /// 0=一次性，1=每天，2=每周。
  final int repeatType;

  /// 一次性闹钟的日期（repeatType=0 时用）。
  final DateTime? onceDate;

  /// 每周重复的星期几位掩码（1<<(weekday-1)），repeatType=2 时用。
  final int weekdays;
  final bool enabled;
  const CustomAlarm(
      {required this.id,
      required this.hour,
      required this.minute,
      required this.repeatType,
      this.onceDate,
      required this.weekdays,
      required this.enabled});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['hour'] = Variable<int>(hour);
    map['minute'] = Variable<int>(minute);
    map['repeat_type'] = Variable<int>(repeatType);
    if (!nullToAbsent || onceDate != null) {
      map['once_date'] = Variable<DateTime>(onceDate);
    }
    map['weekdays'] = Variable<int>(weekdays);
    map['enabled'] = Variable<bool>(enabled);
    return map;
  }

  CustomAlarmsCompanion toCompanion(bool nullToAbsent) {
    return CustomAlarmsCompanion(
      id: Value(id),
      hour: Value(hour),
      minute: Value(minute),
      repeatType: Value(repeatType),
      onceDate: onceDate == null && nullToAbsent
          ? const Value.absent()
          : Value(onceDate),
      weekdays: Value(weekdays),
      enabled: Value(enabled),
    );
  }

  factory CustomAlarm.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CustomAlarm(
      id: serializer.fromJson<int>(json['id']),
      hour: serializer.fromJson<int>(json['hour']),
      minute: serializer.fromJson<int>(json['minute']),
      repeatType: serializer.fromJson<int>(json['repeatType']),
      onceDate: serializer.fromJson<DateTime?>(json['onceDate']),
      weekdays: serializer.fromJson<int>(json['weekdays']),
      enabled: serializer.fromJson<bool>(json['enabled']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'hour': serializer.toJson<int>(hour),
      'minute': serializer.toJson<int>(minute),
      'repeatType': serializer.toJson<int>(repeatType),
      'onceDate': serializer.toJson<DateTime?>(onceDate),
      'weekdays': serializer.toJson<int>(weekdays),
      'enabled': serializer.toJson<bool>(enabled),
    };
  }

  CustomAlarm copyWith(
          {int? id,
          int? hour,
          int? minute,
          int? repeatType,
          Value<DateTime?> onceDate = const Value.absent(),
          int? weekdays,
          bool? enabled}) =>
      CustomAlarm(
        id: id ?? this.id,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        repeatType: repeatType ?? this.repeatType,
        onceDate: onceDate.present ? onceDate.value : this.onceDate,
        weekdays: weekdays ?? this.weekdays,
        enabled: enabled ?? this.enabled,
      );
  CustomAlarm copyWithCompanion(CustomAlarmsCompanion data) {
    return CustomAlarm(
      id: data.id.present ? data.id.value : this.id,
      hour: data.hour.present ? data.hour.value : this.hour,
      minute: data.minute.present ? data.minute.value : this.minute,
      repeatType:
          data.repeatType.present ? data.repeatType.value : this.repeatType,
      onceDate: data.onceDate.present ? data.onceDate.value : this.onceDate,
      weekdays: data.weekdays.present ? data.weekdays.value : this.weekdays,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CustomAlarm(')
          ..write('id: $id, ')
          ..write('hour: $hour, ')
          ..write('minute: $minute, ')
          ..write('repeatType: $repeatType, ')
          ..write('onceDate: $onceDate, ')
          ..write('weekdays: $weekdays, ')
          ..write('enabled: $enabled')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, hour, minute, repeatType, onceDate, weekdays, enabled);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CustomAlarm &&
          other.id == this.id &&
          other.hour == this.hour &&
          other.minute == this.minute &&
          other.repeatType == this.repeatType &&
          other.onceDate == this.onceDate &&
          other.weekdays == this.weekdays &&
          other.enabled == this.enabled);
}

class CustomAlarmsCompanion extends UpdateCompanion<CustomAlarm> {
  final Value<int> id;
  final Value<int> hour;
  final Value<int> minute;
  final Value<int> repeatType;
  final Value<DateTime?> onceDate;
  final Value<int> weekdays;
  final Value<bool> enabled;
  const CustomAlarmsCompanion({
    this.id = const Value.absent(),
    this.hour = const Value.absent(),
    this.minute = const Value.absent(),
    this.repeatType = const Value.absent(),
    this.onceDate = const Value.absent(),
    this.weekdays = const Value.absent(),
    this.enabled = const Value.absent(),
  });
  CustomAlarmsCompanion.insert({
    this.id = const Value.absent(),
    required int hour,
    required int minute,
    this.repeatType = const Value.absent(),
    this.onceDate = const Value.absent(),
    this.weekdays = const Value.absent(),
    this.enabled = const Value.absent(),
  })  : hour = Value(hour),
        minute = Value(minute);
  static Insertable<CustomAlarm> custom({
    Expression<int>? id,
    Expression<int>? hour,
    Expression<int>? minute,
    Expression<int>? repeatType,
    Expression<DateTime>? onceDate,
    Expression<int>? weekdays,
    Expression<bool>? enabled,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (hour != null) 'hour': hour,
      if (minute != null) 'minute': minute,
      if (repeatType != null) 'repeat_type': repeatType,
      if (onceDate != null) 'once_date': onceDate,
      if (weekdays != null) 'weekdays': weekdays,
      if (enabled != null) 'enabled': enabled,
    });
  }

  CustomAlarmsCompanion copyWith(
      {Value<int>? id,
      Value<int>? hour,
      Value<int>? minute,
      Value<int>? repeatType,
      Value<DateTime?>? onceDate,
      Value<int>? weekdays,
      Value<bool>? enabled}) {
    return CustomAlarmsCompanion(
      id: id ?? this.id,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      repeatType: repeatType ?? this.repeatType,
      onceDate: onceDate ?? this.onceDate,
      weekdays: weekdays ?? this.weekdays,
      enabled: enabled ?? this.enabled,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (hour.present) {
      map['hour'] = Variable<int>(hour.value);
    }
    if (minute.present) {
      map['minute'] = Variable<int>(minute.value);
    }
    if (repeatType.present) {
      map['repeat_type'] = Variable<int>(repeatType.value);
    }
    if (onceDate.present) {
      map['once_date'] = Variable<DateTime>(onceDate.value);
    }
    if (weekdays.present) {
      map['weekdays'] = Variable<int>(weekdays.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CustomAlarmsCompanion(')
          ..write('id: $id, ')
          ..write('hour: $hour, ')
          ..write('minute: $minute, ')
          ..write('repeatType: $repeatType, ')
          ..write('onceDate: $onceDate, ')
          ..write('weekdays: $weekdays, ')
          ..write('enabled: $enabled')
          ..write(')'))
        .toString();
  }
}

class $ShiftAlarmOverridesTable extends ShiftAlarmOverrides
    with TableInfo<$ShiftAlarmOverridesTable, ShiftAlarmOverride> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ShiftAlarmOverridesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dayMeta = const VerificationMeta('day');
  @override
  late final GeneratedColumn<int> day = GeneratedColumn<int>(
      'day', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _enabledMeta =
      const VerificationMeta('enabled');
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
      'enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("enabled" IN (0, 1))'),
      defaultValue: const Constant(true));
  @override
  List<GeneratedColumn> get $columns => [day, enabled];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shift_alarm_overrides';
  @override
  VerificationContext validateIntegrity(Insertable<ShiftAlarmOverride> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('day')) {
      context.handle(
          _dayMeta, day.isAcceptableOrUnknown(data['day']!, _dayMeta));
    }
    if (data.containsKey('enabled')) {
      context.handle(_enabledMeta,
          enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {day};
  @override
  ShiftAlarmOverride map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ShiftAlarmOverride(
      day: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}day'])!,
      enabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}enabled'])!,
    );
  }

  @override
  $ShiftAlarmOverridesTable createAlias(String alias) {
    return $ShiftAlarmOverridesTable(attachedDatabase, alias);
  }
}

class ShiftAlarmOverride extends DataClass
    implements Insertable<ShiftAlarmOverride> {
  final int day;
  final bool enabled;
  const ShiftAlarmOverride({required this.day, required this.enabled});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['day'] = Variable<int>(day);
    map['enabled'] = Variable<bool>(enabled);
    return map;
  }

  ShiftAlarmOverridesCompanion toCompanion(bool nullToAbsent) {
    return ShiftAlarmOverridesCompanion(
      day: Value(day),
      enabled: Value(enabled),
    );
  }

  factory ShiftAlarmOverride.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ShiftAlarmOverride(
      day: serializer.fromJson<int>(json['day']),
      enabled: serializer.fromJson<bool>(json['enabled']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'day': serializer.toJson<int>(day),
      'enabled': serializer.toJson<bool>(enabled),
    };
  }

  ShiftAlarmOverride copyWith({int? day, bool? enabled}) => ShiftAlarmOverride(
        day: day ?? this.day,
        enabled: enabled ?? this.enabled,
      );
  ShiftAlarmOverride copyWithCompanion(ShiftAlarmOverridesCompanion data) {
    return ShiftAlarmOverride(
      day: data.day.present ? data.day.value : this.day,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ShiftAlarmOverride(')
          ..write('day: $day, ')
          ..write('enabled: $enabled')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(day, enabled);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ShiftAlarmOverride &&
          other.day == this.day &&
          other.enabled == this.enabled);
}

class ShiftAlarmOverridesCompanion extends UpdateCompanion<ShiftAlarmOverride> {
  final Value<int> day;
  final Value<bool> enabled;
  const ShiftAlarmOverridesCompanion({
    this.day = const Value.absent(),
    this.enabled = const Value.absent(),
  });
  ShiftAlarmOverridesCompanion.insert({
    this.day = const Value.absent(),
    this.enabled = const Value.absent(),
  });
  static Insertable<ShiftAlarmOverride> custom({
    Expression<int>? day,
    Expression<bool>? enabled,
  }) {
    return RawValuesInsertable({
      if (day != null) 'day': day,
      if (enabled != null) 'enabled': enabled,
    });
  }

  ShiftAlarmOverridesCompanion copyWith(
      {Value<int>? day, Value<bool>? enabled}) {
    return ShiftAlarmOverridesCompanion(
      day: day ?? this.day,
      enabled: enabled ?? this.enabled,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (day.present) {
      map['day'] = Variable<int>(day.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ShiftAlarmOverridesCompanion(')
          ..write('day: $day, ')
          ..write('enabled: $enabled')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ShiftScheduleRowsTable shiftScheduleRows =
      $ShiftScheduleRowsTable(this);
  late final $ShiftTypeRowsTable shiftTypeRows = $ShiftTypeRowsTable(this);
  late final $ScheduleEventsTable scheduleEvents = $ScheduleEventsTable(this);
  late final $CustomAlarmsTable customAlarms = $CustomAlarmsTable(this);
  late final $ShiftAlarmOverridesTable shiftAlarmOverrides =
      $ShiftAlarmOverridesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        shiftScheduleRows,
        shiftTypeRows,
        scheduleEvents,
        customAlarms,
        shiftAlarmOverrides
      ];
}

typedef $$ShiftScheduleRowsTableCreateCompanionBuilder
    = ShiftScheduleRowsCompanion Function({
  Value<int> id,
  required String name,
  required DateTime anchorDate,
  Value<bool> isCurrent,
  Value<int> teamCount,
  Value<String> teamNames,
  Value<int> ourTeamIndex,
  Value<String> teamOffsets,
});
typedef $$ShiftScheduleRowsTableUpdateCompanionBuilder
    = ShiftScheduleRowsCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<DateTime> anchorDate,
  Value<bool> isCurrent,
  Value<int> teamCount,
  Value<String> teamNames,
  Value<int> ourTeamIndex,
  Value<String> teamOffsets,
});

class $$ShiftScheduleRowsTableFilterComposer
    extends Composer<_$AppDatabase, $ShiftScheduleRowsTable> {
  $$ShiftScheduleRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get anchorDate => $composableBuilder(
      column: $table.anchorDate, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isCurrent => $composableBuilder(
      column: $table.isCurrent, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get teamCount => $composableBuilder(
      column: $table.teamCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get teamNames => $composableBuilder(
      column: $table.teamNames, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get ourTeamIndex => $composableBuilder(
      column: $table.ourTeamIndex, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get teamOffsets => $composableBuilder(
      column: $table.teamOffsets, builder: (column) => ColumnFilters(column));
}

class $$ShiftScheduleRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $ShiftScheduleRowsTable> {
  $$ShiftScheduleRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get anchorDate => $composableBuilder(
      column: $table.anchorDate, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isCurrent => $composableBuilder(
      column: $table.isCurrent, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get teamCount => $composableBuilder(
      column: $table.teamCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get teamNames => $composableBuilder(
      column: $table.teamNames, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get ourTeamIndex => $composableBuilder(
      column: $table.ourTeamIndex,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get teamOffsets => $composableBuilder(
      column: $table.teamOffsets, builder: (column) => ColumnOrderings(column));
}

class $$ShiftScheduleRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ShiftScheduleRowsTable> {
  $$ShiftScheduleRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get anchorDate => $composableBuilder(
      column: $table.anchorDate, builder: (column) => column);

  GeneratedColumn<bool> get isCurrent =>
      $composableBuilder(column: $table.isCurrent, builder: (column) => column);

  GeneratedColumn<int> get teamCount =>
      $composableBuilder(column: $table.teamCount, builder: (column) => column);

  GeneratedColumn<String> get teamNames =>
      $composableBuilder(column: $table.teamNames, builder: (column) => column);

  GeneratedColumn<int> get ourTeamIndex => $composableBuilder(
      column: $table.ourTeamIndex, builder: (column) => column);

  GeneratedColumn<String> get teamOffsets => $composableBuilder(
      column: $table.teamOffsets, builder: (column) => column);
}

class $$ShiftScheduleRowsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ShiftScheduleRowsTable,
    ShiftScheduleRow,
    $$ShiftScheduleRowsTableFilterComposer,
    $$ShiftScheduleRowsTableOrderingComposer,
    $$ShiftScheduleRowsTableAnnotationComposer,
    $$ShiftScheduleRowsTableCreateCompanionBuilder,
    $$ShiftScheduleRowsTableUpdateCompanionBuilder,
    (
      ShiftScheduleRow,
      BaseReferences<_$AppDatabase, $ShiftScheduleRowsTable, ShiftScheduleRow>
    ),
    ShiftScheduleRow,
    PrefetchHooks Function()> {
  $$ShiftScheduleRowsTableTableManager(
      _$AppDatabase db, $ShiftScheduleRowsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ShiftScheduleRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ShiftScheduleRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ShiftScheduleRowsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<DateTime> anchorDate = const Value.absent(),
            Value<bool> isCurrent = const Value.absent(),
            Value<int> teamCount = const Value.absent(),
            Value<String> teamNames = const Value.absent(),
            Value<int> ourTeamIndex = const Value.absent(),
            Value<String> teamOffsets = const Value.absent(),
          }) =>
              ShiftScheduleRowsCompanion(
            id: id,
            name: name,
            anchorDate: anchorDate,
            isCurrent: isCurrent,
            teamCount: teamCount,
            teamNames: teamNames,
            ourTeamIndex: ourTeamIndex,
            teamOffsets: teamOffsets,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String name,
            required DateTime anchorDate,
            Value<bool> isCurrent = const Value.absent(),
            Value<int> teamCount = const Value.absent(),
            Value<String> teamNames = const Value.absent(),
            Value<int> ourTeamIndex = const Value.absent(),
            Value<String> teamOffsets = const Value.absent(),
          }) =>
              ShiftScheduleRowsCompanion.insert(
            id: id,
            name: name,
            anchorDate: anchorDate,
            isCurrent: isCurrent,
            teamCount: teamCount,
            teamNames: teamNames,
            ourTeamIndex: ourTeamIndex,
            teamOffsets: teamOffsets,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ShiftScheduleRowsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ShiftScheduleRowsTable,
    ShiftScheduleRow,
    $$ShiftScheduleRowsTableFilterComposer,
    $$ShiftScheduleRowsTableOrderingComposer,
    $$ShiftScheduleRowsTableAnnotationComposer,
    $$ShiftScheduleRowsTableCreateCompanionBuilder,
    $$ShiftScheduleRowsTableUpdateCompanionBuilder,
    (
      ShiftScheduleRow,
      BaseReferences<_$AppDatabase, $ShiftScheduleRowsTable, ShiftScheduleRow>
    ),
    ShiftScheduleRow,
    PrefetchHooks Function()>;
typedef $$ShiftTypeRowsTableCreateCompanionBuilder = ShiftTypeRowsCompanion
    Function({
  Value<int> id,
  required int scheduleId,
  required int order,
  required String name,
  Value<int?> startMinute,
  Value<int?> endMinute,
  Value<bool> isRest,
  Value<int> color,
  Value<bool> alarmEnabled,
  Value<int?> alarmMinute,
});
typedef $$ShiftTypeRowsTableUpdateCompanionBuilder = ShiftTypeRowsCompanion
    Function({
  Value<int> id,
  Value<int> scheduleId,
  Value<int> order,
  Value<String> name,
  Value<int?> startMinute,
  Value<int?> endMinute,
  Value<bool> isRest,
  Value<int> color,
  Value<bool> alarmEnabled,
  Value<int?> alarmMinute,
});

class $$ShiftTypeRowsTableFilterComposer
    extends Composer<_$AppDatabase, $ShiftTypeRowsTable> {
  $$ShiftTypeRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get scheduleId => $composableBuilder(
      column: $table.scheduleId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get order => $composableBuilder(
      column: $table.order, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get startMinute => $composableBuilder(
      column: $table.startMinute, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get endMinute => $composableBuilder(
      column: $table.endMinute, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isRest => $composableBuilder(
      column: $table.isRest, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get color => $composableBuilder(
      column: $table.color, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get alarmEnabled => $composableBuilder(
      column: $table.alarmEnabled, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get alarmMinute => $composableBuilder(
      column: $table.alarmMinute, builder: (column) => ColumnFilters(column));
}

class $$ShiftTypeRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $ShiftTypeRowsTable> {
  $$ShiftTypeRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get scheduleId => $composableBuilder(
      column: $table.scheduleId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get order => $composableBuilder(
      column: $table.order, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get startMinute => $composableBuilder(
      column: $table.startMinute, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get endMinute => $composableBuilder(
      column: $table.endMinute, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isRest => $composableBuilder(
      column: $table.isRest, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get color => $composableBuilder(
      column: $table.color, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get alarmEnabled => $composableBuilder(
      column: $table.alarmEnabled,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get alarmMinute => $composableBuilder(
      column: $table.alarmMinute, builder: (column) => ColumnOrderings(column));
}

class $$ShiftTypeRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ShiftTypeRowsTable> {
  $$ShiftTypeRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get scheduleId => $composableBuilder(
      column: $table.scheduleId, builder: (column) => column);

  GeneratedColumn<int> get order =>
      $composableBuilder(column: $table.order, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get startMinute => $composableBuilder(
      column: $table.startMinute, builder: (column) => column);

  GeneratedColumn<int> get endMinute =>
      $composableBuilder(column: $table.endMinute, builder: (column) => column);

  GeneratedColumn<bool> get isRest =>
      $composableBuilder(column: $table.isRest, builder: (column) => column);

  GeneratedColumn<int> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<bool> get alarmEnabled => $composableBuilder(
      column: $table.alarmEnabled, builder: (column) => column);

  GeneratedColumn<int> get alarmMinute => $composableBuilder(
      column: $table.alarmMinute, builder: (column) => column);
}

class $$ShiftTypeRowsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ShiftTypeRowsTable,
    ShiftTypeRow,
    $$ShiftTypeRowsTableFilterComposer,
    $$ShiftTypeRowsTableOrderingComposer,
    $$ShiftTypeRowsTableAnnotationComposer,
    $$ShiftTypeRowsTableCreateCompanionBuilder,
    $$ShiftTypeRowsTableUpdateCompanionBuilder,
    (
      ShiftTypeRow,
      BaseReferences<_$AppDatabase, $ShiftTypeRowsTable, ShiftTypeRow>
    ),
    ShiftTypeRow,
    PrefetchHooks Function()> {
  $$ShiftTypeRowsTableTableManager(_$AppDatabase db, $ShiftTypeRowsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ShiftTypeRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ShiftTypeRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ShiftTypeRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> scheduleId = const Value.absent(),
            Value<int> order = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<int?> startMinute = const Value.absent(),
            Value<int?> endMinute = const Value.absent(),
            Value<bool> isRest = const Value.absent(),
            Value<int> color = const Value.absent(),
            Value<bool> alarmEnabled = const Value.absent(),
            Value<int?> alarmMinute = const Value.absent(),
          }) =>
              ShiftTypeRowsCompanion(
            id: id,
            scheduleId: scheduleId,
            order: order,
            name: name,
            startMinute: startMinute,
            endMinute: endMinute,
            isRest: isRest,
            color: color,
            alarmEnabled: alarmEnabled,
            alarmMinute: alarmMinute,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int scheduleId,
            required int order,
            required String name,
            Value<int?> startMinute = const Value.absent(),
            Value<int?> endMinute = const Value.absent(),
            Value<bool> isRest = const Value.absent(),
            Value<int> color = const Value.absent(),
            Value<bool> alarmEnabled = const Value.absent(),
            Value<int?> alarmMinute = const Value.absent(),
          }) =>
              ShiftTypeRowsCompanion.insert(
            id: id,
            scheduleId: scheduleId,
            order: order,
            name: name,
            startMinute: startMinute,
            endMinute: endMinute,
            isRest: isRest,
            color: color,
            alarmEnabled: alarmEnabled,
            alarmMinute: alarmMinute,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ShiftTypeRowsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ShiftTypeRowsTable,
    ShiftTypeRow,
    $$ShiftTypeRowsTableFilterComposer,
    $$ShiftTypeRowsTableOrderingComposer,
    $$ShiftTypeRowsTableAnnotationComposer,
    $$ShiftTypeRowsTableCreateCompanionBuilder,
    $$ShiftTypeRowsTableUpdateCompanionBuilder,
    (
      ShiftTypeRow,
      BaseReferences<_$AppDatabase, $ShiftTypeRowsTable, ShiftTypeRow>
    ),
    ShiftTypeRow,
    PrefetchHooks Function()>;
typedef $$ScheduleEventsTableCreateCompanionBuilder = ScheduleEventsCompanion
    Function({
  Value<int> id,
  required String title,
  required DateTime date,
  Value<int?> timeMinute,
  Value<int?> advanceRemindMinutes,
  Value<bool> isCompleted,
  required DateTime createdAt,
});
typedef $$ScheduleEventsTableUpdateCompanionBuilder = ScheduleEventsCompanion
    Function({
  Value<int> id,
  Value<String> title,
  Value<DateTime> date,
  Value<int?> timeMinute,
  Value<int?> advanceRemindMinutes,
  Value<bool> isCompleted,
  Value<DateTime> createdAt,
});

class $$ScheduleEventsTableFilterComposer
    extends Composer<_$AppDatabase, $ScheduleEventsTable> {
  $$ScheduleEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get date => $composableBuilder(
      column: $table.date, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get timeMinute => $composableBuilder(
      column: $table.timeMinute, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get advanceRemindMinutes => $composableBuilder(
      column: $table.advanceRemindMinutes,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isCompleted => $composableBuilder(
      column: $table.isCompleted, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$ScheduleEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $ScheduleEventsTable> {
  $$ScheduleEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get date => $composableBuilder(
      column: $table.date, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get timeMinute => $composableBuilder(
      column: $table.timeMinute, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get advanceRemindMinutes => $composableBuilder(
      column: $table.advanceRemindMinutes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isCompleted => $composableBuilder(
      column: $table.isCompleted, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$ScheduleEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ScheduleEventsTable> {
  $$ScheduleEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get timeMinute => $composableBuilder(
      column: $table.timeMinute, builder: (column) => column);

  GeneratedColumn<int> get advanceRemindMinutes => $composableBuilder(
      column: $table.advanceRemindMinutes, builder: (column) => column);

  GeneratedColumn<bool> get isCompleted => $composableBuilder(
      column: $table.isCompleted, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ScheduleEventsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ScheduleEventsTable,
    ScheduleEvent,
    $$ScheduleEventsTableFilterComposer,
    $$ScheduleEventsTableOrderingComposer,
    $$ScheduleEventsTableAnnotationComposer,
    $$ScheduleEventsTableCreateCompanionBuilder,
    $$ScheduleEventsTableUpdateCompanionBuilder,
    (
      ScheduleEvent,
      BaseReferences<_$AppDatabase, $ScheduleEventsTable, ScheduleEvent>
    ),
    ScheduleEvent,
    PrefetchHooks Function()> {
  $$ScheduleEventsTableTableManager(
      _$AppDatabase db, $ScheduleEventsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ScheduleEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ScheduleEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ScheduleEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<DateTime> date = const Value.absent(),
            Value<int?> timeMinute = const Value.absent(),
            Value<int?> advanceRemindMinutes = const Value.absent(),
            Value<bool> isCompleted = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              ScheduleEventsCompanion(
            id: id,
            title: title,
            date: date,
            timeMinute: timeMinute,
            advanceRemindMinutes: advanceRemindMinutes,
            isCompleted: isCompleted,
            createdAt: createdAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String title,
            required DateTime date,
            Value<int?> timeMinute = const Value.absent(),
            Value<int?> advanceRemindMinutes = const Value.absent(),
            Value<bool> isCompleted = const Value.absent(),
            required DateTime createdAt,
          }) =>
              ScheduleEventsCompanion.insert(
            id: id,
            title: title,
            date: date,
            timeMinute: timeMinute,
            advanceRemindMinutes: advanceRemindMinutes,
            isCompleted: isCompleted,
            createdAt: createdAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ScheduleEventsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ScheduleEventsTable,
    ScheduleEvent,
    $$ScheduleEventsTableFilterComposer,
    $$ScheduleEventsTableOrderingComposer,
    $$ScheduleEventsTableAnnotationComposer,
    $$ScheduleEventsTableCreateCompanionBuilder,
    $$ScheduleEventsTableUpdateCompanionBuilder,
    (
      ScheduleEvent,
      BaseReferences<_$AppDatabase, $ScheduleEventsTable, ScheduleEvent>
    ),
    ScheduleEvent,
    PrefetchHooks Function()>;
typedef $$CustomAlarmsTableCreateCompanionBuilder = CustomAlarmsCompanion
    Function({
  Value<int> id,
  required int hour,
  required int minute,
  Value<int> repeatType,
  Value<DateTime?> onceDate,
  Value<int> weekdays,
  Value<bool> enabled,
});
typedef $$CustomAlarmsTableUpdateCompanionBuilder = CustomAlarmsCompanion
    Function({
  Value<int> id,
  Value<int> hour,
  Value<int> minute,
  Value<int> repeatType,
  Value<DateTime?> onceDate,
  Value<int> weekdays,
  Value<bool> enabled,
});

class $$CustomAlarmsTableFilterComposer
    extends Composer<_$AppDatabase, $CustomAlarmsTable> {
  $$CustomAlarmsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get hour => $composableBuilder(
      column: $table.hour, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get minute => $composableBuilder(
      column: $table.minute, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get repeatType => $composableBuilder(
      column: $table.repeatType, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get onceDate => $composableBuilder(
      column: $table.onceDate, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get weekdays => $composableBuilder(
      column: $table.weekdays, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnFilters(column));
}

class $$CustomAlarmsTableOrderingComposer
    extends Composer<_$AppDatabase, $CustomAlarmsTable> {
  $$CustomAlarmsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get hour => $composableBuilder(
      column: $table.hour, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get minute => $composableBuilder(
      column: $table.minute, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get repeatType => $composableBuilder(
      column: $table.repeatType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get onceDate => $composableBuilder(
      column: $table.onceDate, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get weekdays => $composableBuilder(
      column: $table.weekdays, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnOrderings(column));
}

class $$CustomAlarmsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CustomAlarmsTable> {
  $$CustomAlarmsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get hour =>
      $composableBuilder(column: $table.hour, builder: (column) => column);

  GeneratedColumn<int> get minute =>
      $composableBuilder(column: $table.minute, builder: (column) => column);

  GeneratedColumn<int> get repeatType => $composableBuilder(
      column: $table.repeatType, builder: (column) => column);

  GeneratedColumn<DateTime> get onceDate =>
      $composableBuilder(column: $table.onceDate, builder: (column) => column);

  GeneratedColumn<int> get weekdays =>
      $composableBuilder(column: $table.weekdays, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);
}

class $$CustomAlarmsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CustomAlarmsTable,
    CustomAlarm,
    $$CustomAlarmsTableFilterComposer,
    $$CustomAlarmsTableOrderingComposer,
    $$CustomAlarmsTableAnnotationComposer,
    $$CustomAlarmsTableCreateCompanionBuilder,
    $$CustomAlarmsTableUpdateCompanionBuilder,
    (
      CustomAlarm,
      BaseReferences<_$AppDatabase, $CustomAlarmsTable, CustomAlarm>
    ),
    CustomAlarm,
    PrefetchHooks Function()> {
  $$CustomAlarmsTableTableManager(_$AppDatabase db, $CustomAlarmsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CustomAlarmsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CustomAlarmsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CustomAlarmsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> hour = const Value.absent(),
            Value<int> minute = const Value.absent(),
            Value<int> repeatType = const Value.absent(),
            Value<DateTime?> onceDate = const Value.absent(),
            Value<int> weekdays = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
          }) =>
              CustomAlarmsCompanion(
            id: id,
            hour: hour,
            minute: minute,
            repeatType: repeatType,
            onceDate: onceDate,
            weekdays: weekdays,
            enabled: enabled,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int hour,
            required int minute,
            Value<int> repeatType = const Value.absent(),
            Value<DateTime?> onceDate = const Value.absent(),
            Value<int> weekdays = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
          }) =>
              CustomAlarmsCompanion.insert(
            id: id,
            hour: hour,
            minute: minute,
            repeatType: repeatType,
            onceDate: onceDate,
            weekdays: weekdays,
            enabled: enabled,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CustomAlarmsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CustomAlarmsTable,
    CustomAlarm,
    $$CustomAlarmsTableFilterComposer,
    $$CustomAlarmsTableOrderingComposer,
    $$CustomAlarmsTableAnnotationComposer,
    $$CustomAlarmsTableCreateCompanionBuilder,
    $$CustomAlarmsTableUpdateCompanionBuilder,
    (
      CustomAlarm,
      BaseReferences<_$AppDatabase, $CustomAlarmsTable, CustomAlarm>
    ),
    CustomAlarm,
    PrefetchHooks Function()>;
typedef $$ShiftAlarmOverridesTableCreateCompanionBuilder
    = ShiftAlarmOverridesCompanion Function({
  Value<int> day,
  Value<bool> enabled,
});
typedef $$ShiftAlarmOverridesTableUpdateCompanionBuilder
    = ShiftAlarmOverridesCompanion Function({
  Value<int> day,
  Value<bool> enabled,
});

class $$ShiftAlarmOverridesTableFilterComposer
    extends Composer<_$AppDatabase, $ShiftAlarmOverridesTable> {
  $$ShiftAlarmOverridesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get day => $composableBuilder(
      column: $table.day, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnFilters(column));
}

class $$ShiftAlarmOverridesTableOrderingComposer
    extends Composer<_$AppDatabase, $ShiftAlarmOverridesTable> {
  $$ShiftAlarmOverridesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get day => $composableBuilder(
      column: $table.day, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnOrderings(column));
}

class $$ShiftAlarmOverridesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ShiftAlarmOverridesTable> {
  $$ShiftAlarmOverridesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get day =>
      $composableBuilder(column: $table.day, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);
}

class $$ShiftAlarmOverridesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ShiftAlarmOverridesTable,
    ShiftAlarmOverride,
    $$ShiftAlarmOverridesTableFilterComposer,
    $$ShiftAlarmOverridesTableOrderingComposer,
    $$ShiftAlarmOverridesTableAnnotationComposer,
    $$ShiftAlarmOverridesTableCreateCompanionBuilder,
    $$ShiftAlarmOverridesTableUpdateCompanionBuilder,
    (
      ShiftAlarmOverride,
      BaseReferences<_$AppDatabase, $ShiftAlarmOverridesTable,
          ShiftAlarmOverride>
    ),
    ShiftAlarmOverride,
    PrefetchHooks Function()> {
  $$ShiftAlarmOverridesTableTableManager(
      _$AppDatabase db, $ShiftAlarmOverridesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ShiftAlarmOverridesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ShiftAlarmOverridesTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ShiftAlarmOverridesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> day = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
          }) =>
              ShiftAlarmOverridesCompanion(
            day: day,
            enabled: enabled,
          ),
          createCompanionCallback: ({
            Value<int> day = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
          }) =>
              ShiftAlarmOverridesCompanion.insert(
            day: day,
            enabled: enabled,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ShiftAlarmOverridesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ShiftAlarmOverridesTable,
    ShiftAlarmOverride,
    $$ShiftAlarmOverridesTableFilterComposer,
    $$ShiftAlarmOverridesTableOrderingComposer,
    $$ShiftAlarmOverridesTableAnnotationComposer,
    $$ShiftAlarmOverridesTableCreateCompanionBuilder,
    $$ShiftAlarmOverridesTableUpdateCompanionBuilder,
    (
      ShiftAlarmOverride,
      BaseReferences<_$AppDatabase, $ShiftAlarmOverridesTable,
          ShiftAlarmOverride>
    ),
    ShiftAlarmOverride,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ShiftScheduleRowsTableTableManager get shiftScheduleRows =>
      $$ShiftScheduleRowsTableTableManager(_db, _db.shiftScheduleRows);
  $$ShiftTypeRowsTableTableManager get shiftTypeRows =>
      $$ShiftTypeRowsTableTableManager(_db, _db.shiftTypeRows);
  $$ScheduleEventsTableTableManager get scheduleEvents =>
      $$ScheduleEventsTableTableManager(_db, _db.scheduleEvents);
  $$CustomAlarmsTableTableManager get customAlarms =>
      $$CustomAlarmsTableTableManager(_db, _db.customAlarms);
  $$ShiftAlarmOverridesTableTableManager get shiftAlarmOverrides =>
      $$ShiftAlarmOverridesTableTableManager(_db, _db.shiftAlarmOverrides);
}
