import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/foundation.dart' show immutable;

import 'carwash_order.dart';

/// Availability status of a physical washing bay.
enum BayStatus {
  available('Kosong'),
  occupied('Terisi'),
  maintenance('Perbaikan');

  const BayStatus(this.label);

  final String label;
}

/// Immutable domain model representing a physical carwash/motorcycle bay.
@immutable
class WashBay {
  const WashBay({
    required this.id,
    required this.name,
    this.supportedType,
    required this.status,
    this.currentOrderId,
    this.currentPlate,
    this.operatorName,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final VehicleType? supportedType;
  final BayStatus status;
  final String? currentOrderId;
  final String? currentPlate;
  final String? operatorName;
  final DateTime updatedAt;

  /// Whether this bay accepts vehicles of [type].
  bool supportsVehicleType(VehicleType type) =>
      supportedType == null || supportedType == type;

  /// Whether this bay is currently free for immediate allocation.
  bool get isAvailable => status == BayStatus.available;

  factory WashBay.fromFirestore(String id, Map<String, dynamic> data) {
    final rawType = data['supportedType'];
    return WashBay(
      id: id,
      name: (data['name'] as String?) ?? id,
      supportedType: rawType is String
          ? VehicleType.values.asNameMap()[rawType]
          : null,
      status: enumFromName(
        BayStatus.values,
        data['status'],
        BayStatus.available,
      ),
      currentOrderId: data['currentOrderId'] as String?,
      currentPlate: data['currentPlate'] as String?,
      operatorName: data['operatorName'] as String?,
      updatedAt: parseFirestoreTimestamp(data['updatedAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'supportedType': supportedType?.name,
      'status': status.name,
      'currentOrderId': currentOrderId,
      'currentPlate': currentPlate,
      'operatorName': operatorName,
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  WashBay copyWith({
    String? id,
    String? name,
    VehicleType? supportedType,
    bool clearSupportedType = false,
    BayStatus? status,
    String? currentOrderId,
    String? currentPlate,
    String? operatorName,
    bool clearAssignment = false,
    DateTime? updatedAt,
  }) {
    return WashBay(
      id: id ?? this.id,
      name: name ?? this.name,
      supportedType: clearSupportedType
          ? null
          : (supportedType ?? this.supportedType),
      status: status ?? this.status,
      currentOrderId: clearAssignment
          ? null
          : (currentOrderId ?? this.currentOrderId),
      currentPlate: clearAssignment
          ? null
          : (currentPlate ?? this.currentPlate),
      operatorName: clearAssignment
          ? null
          : (operatorName ?? this.operatorName),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is WashBay &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            name == other.name &&
            supportedType == other.supportedType &&
            status == other.status &&
            currentOrderId == other.currentOrderId &&
            currentPlate == other.currentPlate &&
            operatorName == other.operatorName &&
            updatedAt == other.updatedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    supportedType,
    status,
    currentOrderId,
    currentPlate,
    operatorName,
    updatedAt,
  );
}
