import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/foundation.dart' show immutable;

/// Vehicle category supported by ClearWash POS.
enum VehicleType {
  mobil('Mobil'),
  motor('Motor');

  const VehicleType(this.label);

  final String label;
}

/// Vehicle size tier used to determine pricing and wash duration.
enum VehicleSize {
  small('Kecil'),
  medium('Sedang'),
  large('Besar');

  const VehicleSize(this.label);

  final String label;
}

/// Lifecycle state of a carwash order from intake to handover.
enum OrderStatus {
  waiting('Menunggu'),
  washing('Dicuci'),
  ready('Selesai'),
  completed('Diambil'),
  cancelled('Batal');

  const OrderStatus(this.label);

  final String label;
}

/// Payment channel accepted at checkout.
enum PaymentMethod {
  cash('Tunai'),
  qris('QRIS');

  const PaymentMethod(this.label);

  final String label;
}

/// Settlement state of an order payment.
enum PaymentStatus {
  pending('Belum Bayar'),
  paid('Lunas');

  const PaymentStatus(this.label);

  final String label;
}

/// Service catalog entry for a specific vehicle type and size tier.
@immutable
class WashPackage {
  const WashPackage({
    required this.id,
    required this.vehicleType,
    required this.size,
    required this.name,
    required this.description,
    required this.price,
    required this.estimatedMinutes,
  });

  final String id;
  final VehicleType vehicleType;
  final VehicleSize size;
  final String name;
  final String description;
  final int price;
  final int estimatedMinutes;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is WashPackage &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            vehicleType == other.vehicleType &&
            size == other.size &&
            name == other.name &&
            description == other.description &&
            price == other.price &&
            estimatedMinutes == other.estimatedMinutes;
  }

  @override
  int get hashCode => Object.hash(
    id,
    vehicleType,
    size,
    name,
    description,
    price,
    estimatedMinutes,
  );
}

/// Standard ClearWash package catalog covering all car and motorcycle sizes.
const List<WashPackage> defaultWashPackages = [
  WashPackage(
    id: 'pkg_mobil_small',
    vehicleType: VehicleType.mobil,
    size: VehicleSize.small,
    name: 'Cuci Mobil Kecil',
    description: '< 1.200cc (City Car / Hatchback / LCGC)',
    price: 50000,
    estimatedMinutes: 30,
  ),
  WashPackage(
    id: 'pkg_mobil_medium',
    vehicleType: VehicleType.mobil,
    size: VehicleSize.medium,
    name: 'Cuci Mobil Sedang',
    description: '1.200cc - 2.000cc (MPV / Sedan / Crossover)',
    price: 75000,
    estimatedMinutes: 40,
  ),
  WashPackage(
    id: 'pkg_mobil_large',
    vehicleType: VehicleType.mobil,
    size: VehicleSize.large,
    name: 'Cuci Mobil Besar',
    description: '> 2.000cc (Large SUV / Van / Double Cabin)',
    price: 100000,
    estimatedMinutes: 50,
  ),
  WashPackage(
    id: 'pkg_motor_small',
    vehicleType: VehicleType.motor,
    size: VehicleSize.small,
    name: 'Cuci Motor Kecil',
    description: '< 125cc (Skutik Kecil / Bebek)',
    price: 20000,
    estimatedMinutes: 15,
  ),
  WashPackage(
    id: 'pkg_motor_medium',
    vehicleType: VehicleType.motor,
    size: VehicleSize.medium,
    name: 'Cuci Motor Sedang',
    description: '125cc - 250cc (Maxi Skutik / Sport Ringan)',
    price: 30000,
    estimatedMinutes: 20,
  ),
  WashPackage(
    id: 'pkg_motor_large',
    vehicleType: VehicleType.motor,
    size: VehicleSize.large,
    name: 'Cuci Motor Besar',
    description: '> 250cc (Moge / Cruiser / Touring)',
    price: 50000,
    estimatedMinutes: 30,
  ),
];

/// Common car brands encountered in Indonesian carwash outlets.
const List<String> carBrands = [
  'Toyota',
  'Honda',
  'Mitsubishi',
  'Daihatsu',
  'Suzuki',
  'Wuling',
  'Hyundai',
  'Nissan',
  'Mazda',
  'Kia',
  'BMW',
  'Mercedes-Benz',
  'Lainnya',
];

/// Common motorcycle brands encountered in Indonesian carwash outlets.
const List<String> motorBrands = [
  'Honda',
  'Yamaha',
  'Suzuki',
  'Kawasaki',
  'Vespa',
  'Piaggio',
  'BMW Motorrad',
  'Ducati',
  'Lainnya',
];

/// Converts a [DateTime] into an operational `'YYYY-MM-DD'` Firestore date key.
String toDateKey(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

/// Formats a clock time as zero-padded `HH:mm`.
String formatClock(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// Formats a timestamp as `dd/MM/yyyy HH:mm`.
String formatDateTime(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year.toString().padLeft(4, '0');
  return '$day/$month/$year ${formatClock(date)}';
}

/// Extracts trailing digits from a ticket code (e.g. `'CW-007'` -> `'007'`).
String? extractQueueDigits(String queueNumber) =>
    RegExp(r'(\d+)$').firstMatch(queueNumber.trim())?.group(1);

/// Formats an integer IDR [amount] into Indonesian Rupiah (e.g. `Rp 75.000`).
String formatRupiah(int amount) {
  final isNegative = amount < 0;
  final digits = amount.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final remaining = digits.length - i;
    if (i > 0 && remaining % 3 == 0) {
      buffer.write('.');
    }
    buffer.write(digits[i]);
  }
  return isNegative ? '-Rp $buffer' : 'Rp $buffer';
}

/// Resolves an enum value by [Enum.name], returning [fallback] if unmatched.
T enumFromName<T extends Enum>(List<T> values, Object? raw, T fallback) =>
    raw is String ? (values.asNameMap()[raw] ?? fallback) : fallback;

/// Parses a Firestore [Timestamp], [DateTime], ISO-8601 string, or epoch ms.
DateTime? parseFirestoreTimestamp(Object? raw) {
  if (raw == null) {
    return null;
  }
  if (raw is Timestamp) {
    return raw.toDate();
  }
  if (raw is DateTime) {
    return raw;
  }
  if (raw is String) {
    return DateTime.tryParse(raw);
  }
  if (raw is int) {
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }
  return null;
}

/// Immutable domain model representing a single ClearWash POS order.
@immutable
class CarwashOrder {
  const CarwashOrder({
    required this.id,
    required this.queueNumber,
    required this.outletId,
    required this.shiftId,
    required this.vehicleType,
    required this.vehicleSize,
    required this.brand,
    required this.model,
    required this.licensePlate,
    required this.packageId,
    required this.packageName,
    required this.price,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.cashTendered,
    required this.changeAmount,
    this.qrisProofFileName,
    required this.status,
    this.bayId,
    this.bayName,
    this.operatorName,
    required this.pickupDisplay,
    required this.estimatedReadyAt,
    this.startedWashingAt,
    this.finishedAt,
    this.completedAt,
    required this.createdAt,
    required this.dateKey,
  });

  final String id;
  final String queueNumber;
  final String outletId;
  final String shiftId;
  final VehicleType vehicleType;
  final VehicleSize vehicleSize;
  final String brand;
  final String model;
  final String licensePlate;
  final String packageId;
  final String packageName;
  final int price;
  final PaymentMethod paymentMethod;
  final PaymentStatus paymentStatus;
  final int cashTendered;
  final int changeAmount;
  final String? qrisProofFileName;
  final OrderStatus status;
  final String? bayId;
  final String? bayName;
  final String? operatorName;
  final String pickupDisplay;
  final DateTime estimatedReadyAt;
  final DateTime? startedWashingAt;
  final DateTime? finishedAt;
  final DateTime? completedAt;
  final DateTime createdAt;
  final String dateKey;

  /// Combined display label for vehicle make and model.
  String get vehicleTitle => '$brand $model'.trim();

  /// Actual wash duration in whole minutes when both start and finish exist.
  int? get washDurationMinutes {
    final start = startedWashingAt;
    final finish = finishedAt;
    if (start == null || finish == null) {
      return null;
    }
    final minutes = finish.difference(start).inMinutes;
    return minutes < 0 ? 0 : minutes;
  }

  /// Whether this order is still active in the intake, wash, or pickup lane.
  bool get isActive =>
      status == OrderStatus.waiting ||
      status == OrderStatus.washing ||
      status == OrderStatus.ready;

  factory CarwashOrder.fromFirestore(String id, Map<String, dynamic> data) {
    final createdAt =
        parseFirestoreTimestamp(data['createdAt']) ?? DateTime.now();
    final estimatedReadyAt =
        parseFirestoreTimestamp(data['estimatedReadyAt']) ??
        createdAt.add(const Duration(minutes: 45));

    return CarwashOrder(
      id: id,
      queueNumber: (data['queueNumber'] as String?) ?? 'CW-000',
      outletId: (data['outletId'] as String?) ?? '',
      shiftId: (data['shiftId'] as String?) ?? '',
      vehicleType: enumFromName(
        VehicleType.values,
        data['vehicleType'],
        VehicleType.mobil,
      ),
      vehicleSize: enumFromName(
        VehicleSize.values,
        data['vehicleSize'],
        VehicleSize.medium,
      ),
      brand: (data['brand'] as String?) ?? '',
      model: (data['model'] as String?) ?? '',
      licensePlate: (data['licensePlate'] as String?) ?? '',
      packageId: (data['packageId'] as String?) ?? '',
      packageName: (data['packageName'] as String?) ?? '',
      price: (data['price'] as num?)?.toInt() ?? 0,
      paymentMethod: enumFromName(
        PaymentMethod.values,
        data['paymentMethod'],
        PaymentMethod.cash,
      ),
      paymentStatus: enumFromName(
        PaymentStatus.values,
        data['paymentStatus'],
        PaymentStatus.pending,
      ),
      cashTendered: (data['cashTendered'] as num?)?.toInt() ?? 0,
      changeAmount: (data['changeAmount'] as num?)?.toInt() ?? 0,
      qrisProofFileName: data['qrisProofFileName'] as String?,
      status: enumFromName(
        OrderStatus.values,
        data['status'],
        OrderStatus.waiting,
      ),
      bayId: data['bayId'] as String?,
      bayName: data['bayName'] as String?,
      operatorName: data['operatorName'] as String?,
      pickupDisplay: (data['pickupDisplay'] as String?) ?? 'Sesuai Antrian',
      estimatedReadyAt: estimatedReadyAt,
      startedWashingAt: parseFirestoreTimestamp(data['startedWashingAt']),
      finishedAt: parseFirestoreTimestamp(data['finishedAt']),
      completedAt: parseFirestoreTimestamp(data['completedAt']),
      createdAt: createdAt,
      dateKey: (data['dateKey'] as String?) ?? toDateKey(createdAt),
    );
  }

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'id': id,
      'queueNumber': queueNumber,
      'outletId': outletId,
      'shiftId': shiftId,
      'vehicleType': vehicleType.name,
      'vehicleSize': vehicleSize.name,
      'brand': brand,
      'model': model,
      'licensePlate': licensePlate,
      'packageId': packageId,
      'packageName': packageName,
      'price': price,
      'paymentMethod': paymentMethod.name,
      'paymentStatus': paymentStatus.name,
      'cashTendered': cashTendered,
      'changeAmount': changeAmount,
      'qrisProofFileName': qrisProofFileName,
      'status': status.name,
      'bayId': bayId,
      'bayName': bayName,
      'operatorName': operatorName,
      'pickupDisplay': pickupDisplay,
      'estimatedReadyAt': Timestamp.fromDate(estimatedReadyAt),
      'startedWashingAt': startedWashingAt != null
          ? Timestamp.fromDate(startedWashingAt!)
          : null,
      'finishedAt': finishedAt != null ? Timestamp.fromDate(finishedAt!) : null,
      'completedAt': completedAt != null
          ? Timestamp.fromDate(completedAt!)
          : null,
      'createdAt': Timestamp.fromDate(createdAt),
      'dateKey': dateKey,
    };
  }

  CarwashOrder copyWith({
    String? id,
    String? queueNumber,
    String? outletId,
    String? shiftId,
    VehicleType? vehicleType,
    VehicleSize? vehicleSize,
    String? brand,
    String? model,
    String? licensePlate,
    String? packageId,
    String? packageName,
    int? price,
    PaymentMethod? paymentMethod,
    PaymentStatus? paymentStatus,
    int? cashTendered,
    int? changeAmount,
    String? qrisProofFileName,
    bool clearQrisProof = false,
    OrderStatus? status,
    String? bayId,
    String? bayName,
    String? operatorName,
    bool clearBay = false,
    String? pickupDisplay,
    DateTime? estimatedReadyAt,
    DateTime? startedWashingAt,
    DateTime? finishedAt,
    DateTime? completedAt,
    DateTime? createdAt,
    String? dateKey,
  }) {
    return CarwashOrder(
      id: id ?? this.id,
      queueNumber: queueNumber ?? this.queueNumber,
      outletId: outletId ?? this.outletId,
      shiftId: shiftId ?? this.shiftId,
      vehicleType: vehicleType ?? this.vehicleType,
      vehicleSize: vehicleSize ?? this.vehicleSize,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      licensePlate: licensePlate ?? this.licensePlate,
      packageId: packageId ?? this.packageId,
      packageName: packageName ?? this.packageName,
      price: price ?? this.price,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      cashTendered: cashTendered ?? this.cashTendered,
      changeAmount: changeAmount ?? this.changeAmount,
      qrisProofFileName: clearQrisProof
          ? null
          : (qrisProofFileName ?? this.qrisProofFileName),
      status: status ?? this.status,
      bayId: clearBay ? null : (bayId ?? this.bayId),
      bayName: clearBay ? null : (bayName ?? this.bayName),
      operatorName: clearBay ? null : (operatorName ?? this.operatorName),
      pickupDisplay: pickupDisplay ?? this.pickupDisplay,
      estimatedReadyAt: estimatedReadyAt ?? this.estimatedReadyAt,
      startedWashingAt: startedWashingAt ?? this.startedWashingAt,
      finishedAt: finishedAt ?? this.finishedAt,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
      dateKey: dateKey ?? this.dateKey,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CarwashOrder &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            queueNumber == other.queueNumber &&
            outletId == other.outletId &&
            shiftId == other.shiftId &&
            vehicleType == other.vehicleType &&
            vehicleSize == other.vehicleSize &&
            brand == other.brand &&
            model == other.model &&
            licensePlate == other.licensePlate &&
            packageId == other.packageId &&
            packageName == other.packageName &&
            price == other.price &&
            paymentMethod == other.paymentMethod &&
            paymentStatus == other.paymentStatus &&
            cashTendered == other.cashTendered &&
            changeAmount == other.changeAmount &&
            qrisProofFileName == other.qrisProofFileName &&
            status == other.status &&
            bayId == other.bayId &&
            bayName == other.bayName &&
            operatorName == other.operatorName &&
            pickupDisplay == other.pickupDisplay &&
            estimatedReadyAt == other.estimatedReadyAt &&
            startedWashingAt == other.startedWashingAt &&
            finishedAt == other.finishedAt &&
            completedAt == other.completedAt &&
            createdAt == other.createdAt &&
            dateKey == other.dateKey;
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    queueNumber,
    outletId,
    shiftId,
    vehicleType,
    vehicleSize,
    brand,
    model,
    licensePlate,
    packageId,
    packageName,
    price,
    paymentMethod,
    paymentStatus,
    cashTendered,
    changeAmount,
    qrisProofFileName,
    status,
    bayId,
    bayName,
    operatorName,
    pickupDisplay,
    estimatedReadyAt,
    startedWashingAt,
    finishedAt,
    completedAt,
    createdAt,
    dateKey,
  ]);
}
