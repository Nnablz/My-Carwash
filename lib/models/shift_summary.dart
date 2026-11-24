import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/foundation.dart' show immutable, listEquals;

import 'carwash_order.dart';

/// Operational status of a cashier shift session.
enum ShiftStatus {
  open('AKTIF'),
  closed('TUTUP');

  const ShiftStatus(this.label);

  final String label;
}

/// Immutable domain model representing a POS cashier shift and cash drawer.
@immutable
class ShiftSession {
  const ShiftSession({
    required this.id,
    required this.cashierName,
    required this.terminalId,
    required this.bayLabel,
    required this.shiftLabel,
    required this.openedAt,
    this.closedAt,
    required this.openingCash,
    required this.physicalCashCount,
    required this.supervisorNotes,
    required this.status,
  });

  final String id;
  final String cashierName;
  final String terminalId;
  final String bayLabel;
  final String shiftLabel;
  final DateTime openedAt;
  final DateTime? closedAt;
  final int openingCash;
  final int physicalCashCount;
  final String supervisorNotes;
  final ShiftStatus status;

  /// Whether this shift is still open for intake and cash drawer audits.
  bool get isOpen => status == ShiftStatus.open;

  factory ShiftSession.fromFirestore(String id, Map<String, dynamic> data) {
    return ShiftSession(
      id: id,
      cashierName: (data['cashierName'] as String?) ?? 'Kasir',
      terminalId: (data['terminalId'] as String?) ?? 'POS-01',
      bayLabel: (data['bayLabel'] as String?) ?? 'Outlet Utama',
      shiftLabel: (data['shiftLabel'] as String?) ?? 'Shift Aktif',
      openedAt: parseFirestoreTimestamp(data['openedAt']) ?? DateTime.now(),
      closedAt: parseFirestoreTimestamp(data['closedAt']),
      openingCash: (data['openingCash'] as num?)?.toInt() ?? 0,
      physicalCashCount: (data['physicalCashCount'] as num?)?.toInt() ?? 0,
      supervisorNotes: (data['supervisorNotes'] as String?) ?? '',
      status: enumFromName(
        ShiftStatus.values,
        data['status'],
        ShiftStatus.open,
      ),
    );
  }

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'id': id,
      'cashierName': cashierName,
      'terminalId': terminalId,
      'bayLabel': bayLabel,
      'shiftLabel': shiftLabel,
      'openedAt': Timestamp.fromDate(openedAt),
      'closedAt': closedAt != null ? Timestamp.fromDate(closedAt!) : null,
      'openingCash': openingCash,
      'physicalCashCount': physicalCashCount,
      'supervisorNotes': supervisorNotes,
      'status': status.name,
    };
  }

  ShiftSession copyWith({
    String? id,
    String? cashierName,
    String? terminalId,
    String? bayLabel,
    String? shiftLabel,
    DateTime? openedAt,
    DateTime? closedAt,
    bool clearClosedAt = false,
    int? openingCash,
    int? physicalCashCount,
    String? supervisorNotes,
    ShiftStatus? status,
  }) {
    return ShiftSession(
      id: id ?? this.id,
      cashierName: cashierName ?? this.cashierName,
      terminalId: terminalId ?? this.terminalId,
      bayLabel: bayLabel ?? this.bayLabel,
      shiftLabel: shiftLabel ?? this.shiftLabel,
      openedAt: openedAt ?? this.openedAt,
      closedAt: clearClosedAt ? null : (closedAt ?? this.closedAt),
      openingCash: openingCash ?? this.openingCash,
      physicalCashCount: physicalCashCount ?? this.physicalCashCount,
      supervisorNotes: supervisorNotes ?? this.supervisorNotes,
      status: status ?? this.status,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ShiftSession &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            cashierName == other.cashierName &&
            terminalId == other.terminalId &&
            bayLabel == other.bayLabel &&
            shiftLabel == other.shiftLabel &&
            openedAt == other.openedAt &&
            closedAt == other.closedAt &&
            openingCash == other.openingCash &&
            physicalCashCount == other.physicalCashCount &&
            supervisorNotes == other.supervisorNotes &&
            status == other.status;
  }

  @override
  int get hashCode => Object.hash(
    id,
    cashierName,
    terminalId,
    bayLabel,
    shiftLabel,
    openedAt,
    closedAt,
    openingCash,
    physicalCashCount,
    supervisorNotes,
    status,
  );
}

/// Revenue aggregation for a single wash package within a shift.
@immutable
class ServiceBreakdownItem {
  const ServiceBreakdownItem({
    required this.packageName,
    required this.count,
    required this.totalRevenue,
    required this.percentage,
  });

  final String packageName;
  final int count;
  final int totalRevenue;

  /// Revenue share percentage in the range `0.0`–`100.0`.
  final double percentage;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ServiceBreakdownItem &&
            runtimeType == other.runtimeType &&
            packageName == other.packageName &&
            count == other.count &&
            totalRevenue == other.totalRevenue &&
            percentage == other.percentage;
  }

  @override
  int get hashCode => Object.hash(packageName, count, totalRevenue, percentage);
}

/// Computed end-of-shift operational summary and cash drawer reconciliation.
@immutable
class ShiftReport {
  const ShiftReport({
    required this.shift,
    required this.totalRevenue,
    required this.cashRevenue,
    required this.cashCount,
    required this.qrisRevenue,
    required this.qrisCount,
    required this.totalVehicles,
    required this.averageWashMinutes,
    required this.carCount,
    required this.carSmallCount,
    required this.carMediumCount,
    required this.carLargeCount,
    required this.motorCount,
    required this.motorSmallCount,
    required this.motorMediumCount,
    required this.motorLargeCount,
    required this.serviceBreakdowns,
    required this.expectedCashInDrawer,
    required this.cashVariance,
  });

  final ShiftSession shift;
  final int totalRevenue;
  final int cashRevenue;
  final int cashCount;
  final int qrisRevenue;
  final int qrisCount;
  final int totalVehicles;
  final int averageWashMinutes;
  final int carCount;
  final int carSmallCount;
  final int carMediumCount;
  final int carLargeCount;
  final int motorCount;
  final int motorSmallCount;
  final int motorMediumCount;
  final int motorLargeCount;
  final List<ServiceBreakdownItem> serviceBreakdowns;
  final int expectedCashInDrawer;
  final int cashVariance;

  /// Whether the counted physical drawer cash matches expected drawer cash.
  bool get isCashBalanced => cashVariance == 0;

  /// Builds a [ShiftReport] by aggregating non-cancelled [orders] for [shift].
  factory ShiftReport.fromOrders({
    required ShiftSession shift,
    required List<CarwashOrder> orders,
  }) {
    var totalRevenue = 0;
    var cashRevenue = 0;
    var cashCount = 0;
    var qrisRevenue = 0;
    var qrisCount = 0;

    var totalVehicles = 0;
    var carCount = 0;
    var carSmallCount = 0;
    var carMediumCount = 0;
    var carLargeCount = 0;
    var motorCount = 0;
    var motorSmallCount = 0;
    var motorMediumCount = 0;
    var motorLargeCount = 0;

    var totalWashMinutes = 0;
    var timedOrdersCount = 0;

    final packageTotals = <String, _PackageAccumulator>{};

    for (final order in orders) {
      if (order.shiftId != shift.id || order.status == OrderStatus.cancelled) {
        continue;
      }

      totalVehicles++;
      switch (order.vehicleType) {
        case VehicleType.mobil:
          carCount++;
          switch (order.vehicleSize) {
            case VehicleSize.small:
              carSmallCount++;
            case VehicleSize.medium:
              carMediumCount++;
            case VehicleSize.large:
              carLargeCount++;
          }
        case VehicleType.motor:
          motorCount++;
          switch (order.vehicleSize) {
            case VehicleSize.small:
              motorSmallCount++;
            case VehicleSize.medium:
              motorMediumCount++;
            case VehicleSize.large:
              motorLargeCount++;
          }
      }

      final durationMinutes = order.washDurationMinutes;
      if (durationMinutes != null) {
        totalWashMinutes += durationMinutes;
        timedOrdersCount++;
      }

      if (order.paymentStatus == PaymentStatus.paid) {
        totalRevenue += order.price;
        switch (order.paymentMethod) {
          case PaymentMethod.cash:
            cashRevenue += order.price;
            cashCount++;
          case PaymentMethod.qris:
            qrisRevenue += order.price;
            qrisCount++;
        }

        final accumulator = packageTotals.putIfAbsent(
          order.packageName,
          () => _PackageAccumulator(),
        );
        accumulator.count++;
        accumulator.revenue += order.price;
      }
    }

    final averageWashMinutes = timedOrdersCount > 0
        ? (totalWashMinutes / timedOrdersCount).round()
        : 0;

    final breakdowns =
        packageTotals.entries.map((entry) {
          final share = totalRevenue > 0
              ? (entry.value.revenue / totalRevenue) * 100.0
              : 0.0;
          return ServiceBreakdownItem(
            packageName: entry.key,
            count: entry.value.count,
            totalRevenue: entry.value.revenue,
            percentage: share,
          );
        }).toList()..sort((a, b) {
          final revenueCmp = b.totalRevenue.compareTo(a.totalRevenue);
          if (revenueCmp != 0) {
            return revenueCmp;
          }
          final countCmp = b.count.compareTo(a.count);
          if (countCmp != 0) {
            return countCmp;
          }
          return a.packageName.compareTo(b.packageName);
        });

    final expectedCashInDrawer = shift.openingCash + cashRevenue;
    final cashVariance = shift.physicalCashCount - expectedCashInDrawer;

    return ShiftReport(
      shift: shift,
      totalRevenue: totalRevenue,
      cashRevenue: cashRevenue,
      cashCount: cashCount,
      qrisRevenue: qrisRevenue,
      qrisCount: qrisCount,
      totalVehicles: totalVehicles,
      averageWashMinutes: averageWashMinutes,
      carCount: carCount,
      carSmallCount: carSmallCount,
      carMediumCount: carMediumCount,
      carLargeCount: carLargeCount,
      motorCount: motorCount,
      motorSmallCount: motorSmallCount,
      motorMediumCount: motorMediumCount,
      motorLargeCount: motorLargeCount,
      serviceBreakdowns: List<ServiceBreakdownItem>.unmodifiable(breakdowns),
      expectedCashInDrawer: expectedCashInDrawer,
      cashVariance: cashVariance,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ShiftReport &&
            runtimeType == other.runtimeType &&
            shift == other.shift &&
            totalRevenue == other.totalRevenue &&
            cashRevenue == other.cashRevenue &&
            cashCount == other.cashCount &&
            qrisRevenue == other.qrisRevenue &&
            qrisCount == other.qrisCount &&
            totalVehicles == other.totalVehicles &&
            averageWashMinutes == other.averageWashMinutes &&
            carCount == other.carCount &&
            carSmallCount == other.carSmallCount &&
            carMediumCount == other.carMediumCount &&
            carLargeCount == other.carLargeCount &&
            motorCount == other.motorCount &&
            motorSmallCount == other.motorSmallCount &&
            motorMediumCount == other.motorMediumCount &&
            motorLargeCount == other.motorLargeCount &&
            listEquals(serviceBreakdowns, other.serviceBreakdowns) &&
            expectedCashInDrawer == other.expectedCashInDrawer &&
            cashVariance == other.cashVariance;
  }

  @override
  int get hashCode => Object.hashAll([
    shift,
    totalRevenue,
    cashRevenue,
    cashCount,
    qrisRevenue,
    qrisCount,
    totalVehicles,
    averageWashMinutes,
    carCount,
    carSmallCount,
    carMediumCount,
    carLargeCount,
    motorCount,
    motorSmallCount,
    motorMediumCount,
    motorLargeCount,
    Object.hashAll(serviceBreakdowns),
    expectedCashInDrawer,
    cashVariance,
  ]);
}

class _PackageAccumulator {
  int count = 0;
  int revenue = 0;
}
