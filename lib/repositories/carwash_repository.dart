import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart'
    show
        DocumentReference,
        DocumentSnapshot,
        FirebaseFirestore,
        SetOptions,
        Timestamp,
        Transaction;

import '../models/carwash_order.dart';
import '../models/shift_summary.dart';
import '../models/wash_bay.dart';

/// Contract for ClearWash POS operational persistence and real-time streams.
abstract interface class CarwashRepository {
  Stream<List<CarwashOrder>> watchTodayOrders();
  Stream<List<WashBay>> watchBays();
  Stream<ShiftSession> watchActiveShift();

  Future<CarwashOrder> createOrder({
    required VehicleType vehicleType,
    required VehicleSize vehicleSize,
    required String brand,
    required String model,
    required String licensePlate,
    required WashPackage package,
    required PaymentMethod paymentMethod,
    required int cashTendered,
    required String pickupDisplay,
    required DateTime estimatedReadyAt,
    String? qrisProofFileName,
  });

  Future<void> startWash({
    required String orderId,
    required String bayId,
    required String operatorName,
  });

  Future<void> markReadyForPickup(String orderId);
  Future<void> completeHandover(String orderId);
  Future<void> cancelOrder(String orderId);

  Future<void> updateShiftAudit({
    required int physicalCashCount,
    required String supervisorNotes,
  });

  Future<void> closeShift({
    required int physicalCashCount,
    required String supervisorNotes,
  });

  Future<void> reopenDemoShift();
}

const String _defaultOutletId = 'clearwash-main';
const String _defaultOutletName = 'ClearWash Outlet Utama';
const int _defaultOpeningCash = 200000;

CarwashOrder _buildValidatedOrder({
  required String id,
  required String queueNumber,
  required String outletId,
  required String shiftId,
  required VehicleType vehicleType,
  required VehicleSize vehicleSize,
  required String brand,
  required String model,
  required String licensePlate,
  required WashPackage package,
  required PaymentMethod paymentMethod,
  required int cashTendered,
  required String pickupDisplay,
  required DateTime estimatedReadyAt,
  required DateTime createdAt,
  String? qrisProofFileName,
}) {
  final cleanBrand = brand.trim();
  final cleanModel = model.trim();
  final cleanPlate = licensePlate.trim().toUpperCase();
  final cleanPickup = pickupDisplay.trim();
  final cleanProof = qrisProofFileName?.trim();

  if (cleanBrand.isEmpty) {
    throw ArgumentError.value(brand, 'brand', 'Merek kendaraan wajib diisi.');
  }
  if (cleanModel.isEmpty) {
    throw ArgumentError.value(model, 'model', 'Model kendaraan wajib diisi.');
  }
  if (cleanPlate.isEmpty) {
    throw ArgumentError.value(
      licensePlate,
      'licensePlate',
      'Plat nomor wajib diisi.',
    );
  }
  if (cleanPickup.isEmpty) {
    throw ArgumentError.value(
      pickupDisplay,
      'pickupDisplay',
      'Estimasi pengambilan wajib diisi.',
    );
  }
  if (cashTendered < 0) {
    throw ArgumentError.value(
      cashTendered,
      'cashTendered',
      'Nominal tunai tidak boleh negatif.',
    );
  }

  late final PaymentStatus paymentStatus;
  late final int effectiveCashTendered;
  late final int changeAmount;

  switch (paymentMethod) {
    case PaymentMethod.cash:
      if (cashTendered == 0) {
        paymentStatus = PaymentStatus.pending;
        effectiveCashTendered = 0;
        changeAmount = 0;
      } else if (cashTendered < package.price) {
        throw ArgumentError.value(
          cashTendered,
          'cashTendered',
          'Nominal tunai kurang dari harga paket (${formatRupiah(package.price)}).',
        );
      } else {
        paymentStatus = PaymentStatus.paid;
        effectiveCashTendered = cashTendered;
        changeAmount = cashTendered - package.price;
      }
    case PaymentMethod.qris:
      paymentStatus = PaymentStatus.paid;
      effectiveCashTendered = 0;
      changeAmount = 0;
  }

  return CarwashOrder(
    id: id,
    queueNumber: queueNumber,
    outletId: outletId,
    shiftId: shiftId,
    vehicleType: vehicleType,
    vehicleSize: vehicleSize,
    brand: cleanBrand,
    model: cleanModel,
    licensePlate: cleanPlate,
    packageId: package.id,
    packageName: package.name,
    price: package.price,
    paymentMethod: paymentMethod,
    paymentStatus: paymentStatus,
    cashTendered: effectiveCashTendered,
    changeAmount: changeAmount,
    qrisProofFileName: cleanProof == null || cleanProof.isEmpty
        ? null
        : cleanProof,
    status: OrderStatus.waiting,
    pickupDisplay: cleanPickup,
    estimatedReadyAt: estimatedReadyAt,
    createdAt: createdAt,
    dateKey: toDateKey(createdAt),
  );
}

ShiftSession _createFreshShift({
  required String id,
  required DateTime openedAt,
  String cashierName = 'Andi Wijaya',
  String terminalId = 'POS-SUNMI-01',
  String bayLabel = 'Outlet Utama - 4 Bay',
  String shiftLabel = 'Shift Pagi (08:00 - 16:00)',
  int openingCash = _defaultOpeningCash,
  int? physicalCashCount,
}) {
  return ShiftSession(
    id: id,
    cashierName: cashierName,
    terminalId: terminalId,
    bayLabel: bayLabel,
    shiftLabel: shiftLabel,
    openedAt: openedAt,
    openingCash: openingCash,
    physicalCashCount: physicalCashCount ?? openingCash,
    supervisorNotes: '',
    status: ShiftStatus.open,
  );
}

/// Cloud Firestore implementation of [CarwashRepository] using atomic transactions.
class FirestoreCarwashRepository implements CarwashRepository {
  FirestoreCarwashRepository({
    FirebaseFirestore? firestore,
    this.outletId = _defaultOutletId,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final String outletId;

  String get _outletPath => 'outlets/$outletId';

  late final _outletDoc = _firestore.doc(_outletPath);
  late final _baysCol = _outletDoc.collection('bays');
  late final _ordersCol = _outletDoc.collection('orders');
  late final _shiftsCol = _outletDoc.collection('shifts');

  @override
  Stream<List<CarwashOrder>> watchTodayOrders() {
    final todayKey = toDateKey(DateTime.now());
    return _ordersCol
        .where('dateKey', isEqualTo: todayKey)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => CarwashOrder.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  @override
  Stream<List<WashBay>> watchBays() {
    return _baysCol
        .orderBy('name')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => WashBay.fromFirestore(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  @override
  Stream<ShiftSession> watchActiveShift() {
    return _shiftsCol
        .orderBy('openedAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) {
            return _createFreshShift(
              id: 'shift_${toDateKey(DateTime.now())}_1',
              openedAt: DateTime.now(),
            );
          }
          final doc = snapshot.docs.first;
          return ShiftSession.fromFirestore(doc.id, doc.data());
        });
  }

  Future<String> _resolveOrProvisionActiveShiftId() async {
    final query = await _shiftsCol
        .orderBy('openedAt', descending: true)
        .limit(1)
        .get();
    if (query.docs.isNotEmpty) {
      return query.docs.first.id;
    }
    final now = DateTime.now();
    final ref = _shiftsCol.doc('shift_${toDateKey(now)}_1');
    final initialShift = _createFreshShift(id: ref.id, openedAt: now);
    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(ref);
      if (!existing.exists) {
        transaction.set(ref, initialShift.toFirestore());
      }
    });
    return ref.id;
  }

  @override
  Future<CarwashOrder> createOrder({
    required VehicleType vehicleType,
    required VehicleSize vehicleSize,
    required String brand,
    required String model,
    required String licensePlate,
    required WashPackage package,
    required PaymentMethod paymentMethod,
    required int cashTendered,
    required String pickupDisplay,
    required DateTime estimatedReadyAt,
    String? qrisProofFileName,
  }) async {
    final shiftId = await _resolveOrProvisionActiveShiftId();
    final shiftRef = _shiftsCol.doc(shiftId);
    final orderRef = _ordersCol.doc();

    return _firestore.runTransaction((transaction) async {
      final outletSnap = await transaction.get(_outletDoc);
      final shiftSnap = await transaction.get(shiftRef);

      if (!shiftSnap.exists || shiftSnap.data() == null) {
        throw StateError('Shift aktif tidak ditemukan.');
      }
      final shift = ShiftSession.fromFirestore(shiftSnap.id, shiftSnap.data()!);
      if (!shift.isOpen) {
        throw StateError(
          'Shift sudah ditutup. Buka shift baru terlebih dahulu.',
        );
      }

      final now = DateTime.now();
      final todayKey = toDateKey(now);
      final outletData = outletSnap.data() ?? const <String, dynamic>{};
      final lastDateKey = outletData['lastQueueDateKey'] as String?;
      final lastSeq = (outletData['lastQueueSeq'] as num?)?.toInt() ?? 0;
      final nextSeq = lastDateKey == todayKey ? lastSeq + 1 : 1;
      final queueNumber = 'CW-${nextSeq.toString().padLeft(3, '0')}';

      final order = _buildValidatedOrder(
        id: orderRef.id,
        queueNumber: queueNumber,
        outletId: outletId,
        shiftId: shift.id,
        vehicleType: vehicleType,
        vehicleSize: vehicleSize,
        brand: brand,
        model: model,
        licensePlate: licensePlate,
        package: package,
        paymentMethod: paymentMethod,
        cashTendered: cashTendered,
        pickupDisplay: pickupDisplay,
        estimatedReadyAt: estimatedReadyAt,
        createdAt: now,
        qrisProofFileName: qrisProofFileName,
      );

      final outletName = (outletData['name'] as String?) ?? _defaultOutletName;
      final activeBays = (outletData['activeBays'] as num?)?.toInt() ?? 4;

      transaction.set(_outletDoc, <String, Object?>{
        'name': outletName,
        'activeBays': activeBays,
        'lastQueueDateKey': todayKey,
        'lastQueueSeq': nextSeq,
        'updatedAt': Timestamp.fromDate(now),
      }, SetOptions(merge: true));
      transaction.set(orderRef, order.toFirestore());
      return order;
    });
  }

  @override
  Future<void> startWash({
    required String orderId,
    required String bayId,
    required String operatorName,
  }) async {
    final cleanOperator = operatorName.trim();
    if (cleanOperator.isEmpty) {
      throw ArgumentError.value(
        operatorName,
        'operatorName',
        'Nama operator pencuci wajib diisi.',
      );
    }

    await _firestore.runTransaction((transaction) async {
      final orderRef = _ordersCol.doc(orderId);
      final bayRef = _baysCol.doc(bayId);

      final orderSnap = await transaction.get(orderRef);
      final baySnap = await transaction.get(bayRef);

      if (!orderSnap.exists || orderSnap.data() == null) {
        throw StateError('Order $orderId tidak ditemukan.');
      }
      if (!baySnap.exists || baySnap.data() == null) {
        throw StateError('Bay $bayId tidak ditemukan.');
      }

      final order = CarwashOrder.fromFirestore(orderSnap.id, orderSnap.data()!);
      final bay = WashBay.fromFirestore(baySnap.id, baySnap.data()!);

      if (order.status != OrderStatus.waiting) {
        throw StateError(
          'Order ${order.queueNumber} tidak berada di antrian Menunggu.',
        );
      }
      if (!bay.isAvailable) {
        throw StateError('${bay.name} sedang terisi atau dalam perbaikan.');
      }
      if (!bay.supportsVehicleType(order.vehicleType)) {
        throw StateError(
          '${bay.name} tidak mendukung kendaraan ${order.vehicleType.label}.',
        );
      }

      final nowTs = Timestamp.fromDate(DateTime.now());
      transaction.update(orderRef, <String, Object?>{
        'status': OrderStatus.washing.name,
        'bayId': bay.id,
        'bayName': bay.name,
        'operatorName': cleanOperator,
        'startedWashingAt': nowTs,
      });
      transaction.update(bayRef, <String, Object?>{
        'status': BayStatus.occupied.name,
        'currentOrderId': order.id,
        'currentPlate': order.licensePlate,
        'operatorName': cleanOperator,
        'updatedAt': nowTs,
      });
    });
  }

  @override
  Future<void> markReadyForPickup(String orderId) async {
    await _firestore.runTransaction((transaction) async {
      final orderRef = _ordersCol.doc(orderId);
      final orderSnap = await transaction.get(orderRef);

      if (!orderSnap.exists || orderSnap.data() == null) {
        throw StateError('Order $orderId tidak ditemukan.');
      }
      final order = CarwashOrder.fromFirestore(orderSnap.id, orderSnap.data()!);
      if (order.status != OrderStatus.washing) {
        throw StateError(
          'Order ${order.queueNumber} harus berstatus Dicuci sebelum ditandai Selesai.',
        );
      }

      final bayRef = order.bayId != null ? _baysCol.doc(order.bayId) : null;
      final baySnap = bayRef != null ? await transaction.get(bayRef) : null;

      final nowTs = Timestamp.fromDate(DateTime.now());
      transaction.update(orderRef, <String, Object?>{
        'status': OrderStatus.ready.name,
        'finishedAt': nowTs,
      });

      _releaseBayIfAssigned(transaction, bayRef, baySnap, orderId, nowTs);
    });
  }

  @override
  Future<void> completeHandover(String orderId) async {
    await _firestore.runTransaction((transaction) async {
      final orderRef = _ordersCol.doc(orderId);
      final orderSnap = await transaction.get(orderRef);

      if (!orderSnap.exists || orderSnap.data() == null) {
        throw StateError('Order $orderId tidak ditemukan.');
      }
      final order = CarwashOrder.fromFirestore(orderSnap.id, orderSnap.data()!);
      if (order.status != OrderStatus.ready &&
          order.status != OrderStatus.washing) {
        throw StateError(
          'Order ${order.queueNumber} tidak dapat diserahkan dari status ${order.status.label}.',
        );
      }

      final bayRef = order.status == OrderStatus.washing && order.bayId != null
          ? _baysCol.doc(order.bayId)
          : null;
      final baySnap = bayRef != null ? await transaction.get(bayRef) : null;

      final nowTs = Timestamp.fromDate(DateTime.now());
      final updates = <String, Object?>{
        'status': OrderStatus.completed.name,
        'paymentStatus': PaymentStatus.paid.name,
        'completedAt': nowTs,
      };
      if (order.finishedAt == null) {
        updates['finishedAt'] = nowTs;
      }
      if (order.paymentMethod == PaymentMethod.cash &&
          order.cashTendered == 0) {
        updates['cashTendered'] = order.price;
        updates['changeAmount'] = 0;
      }

      transaction.update(orderRef, updates);
      _releaseBayIfAssigned(transaction, bayRef, baySnap, orderId, nowTs);
    });
  }

  @override
  Future<void> cancelOrder(String orderId) async {
    await _firestore.runTransaction((transaction) async {
      final orderRef = _ordersCol.doc(orderId);
      final orderSnap = await transaction.get(orderRef);

      if (!orderSnap.exists || orderSnap.data() == null) {
        throw StateError('Order $orderId tidak ditemukan.');
      }
      final order = CarwashOrder.fromFirestore(orderSnap.id, orderSnap.data()!);
      if (order.status == OrderStatus.completed ||
          order.status == OrderStatus.cancelled) {
        throw StateError(
          'Order ${order.queueNumber} sudah ${order.status.label} dan tidak dapat dibatalkan.',
        );
      }

      final bayRef = order.status == OrderStatus.washing && order.bayId != null
          ? _baysCol.doc(order.bayId)
          : null;
      final baySnap = bayRef != null ? await transaction.get(bayRef) : null;

      transaction.update(orderRef, <String, Object?>{
        'status': OrderStatus.cancelled.name,
      });

      _releaseBayIfAssigned(
        transaction,
        bayRef,
        baySnap,
        orderId,
        Timestamp.fromDate(DateTime.now()),
      );
    });
  }

  void _releaseBayIfAssigned(
    Transaction transaction,
    DocumentReference<Map<String, dynamic>>? bayRef,
    DocumentSnapshot<Map<String, dynamic>>? baySnap,
    String orderId,
    Timestamp nowTs,
  ) {
    if (bayRef != null &&
        baySnap != null &&
        baySnap.exists &&
        baySnap.data()?['currentOrderId'] == orderId) {
      transaction.update(bayRef, <String, Object?>{
        'status': BayStatus.available.name,
        'currentOrderId': null,
        'currentPlate': null,
        'operatorName': null,
        'updatedAt': nowTs,
      });
    }
  }

  @override
  Future<void> updateShiftAudit({
    required int physicalCashCount,
    required String supervisorNotes,
  }) => _updateShift(
    physicalCashCount: physicalCashCount,
    supervisorNotes: supervisorNotes,
    close: false,
  );

  @override
  Future<void> closeShift({
    required int physicalCashCount,
    required String supervisorNotes,
  }) => _updateShift(
    physicalCashCount: physicalCashCount,
    supervisorNotes: supervisorNotes,
    close: true,
  );

  Future<void> _updateShift({
    required int physicalCashCount,
    required String supervisorNotes,
    required bool close,
  }) async {
    if (physicalCashCount < 0) {
      throw ArgumentError.value(
        physicalCashCount,
        'physicalCashCount',
        'Hitungan kas fisik tidak boleh negatif.',
      );
    }

    final shiftId = await _resolveOrProvisionActiveShiftId();
    final shiftRef = _shiftsCol.doc(shiftId);
    await _firestore.runTransaction((transaction) async {
      final snap = await transaction.get(shiftRef);
      if (!snap.exists || snap.data() == null) {
        throw StateError('Shift aktif tidak ditemukan.');
      }
      final shift = ShiftSession.fromFirestore(snap.id, snap.data()!);
      if (!shift.isOpen) {
        throw StateError('Shift sudah ditutup.');
      }
      transaction.update(shiftRef, <String, Object?>{
        'physicalCashCount': physicalCashCount,
        'supervisorNotes': supervisorNotes.trim(),
        if (close) ...<String, Object?>{
          'closedAt': Timestamp.fromDate(DateTime.now()),
          'status': ShiftStatus.closed.name,
        },
      });
    });
  }

  @override
  Future<void> reopenDemoShift() async {
    final query = await _shiftsCol
        .orderBy('openedAt', descending: true)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      final latest = ShiftSession.fromFirestore(
        query.docs.first.id,
        query.docs.first.data(),
      );
      if (latest.isOpen) {
        return;
      }
      final newRef = _shiftsCol.doc();
      final nextShift = _createFreshShift(
        id: newRef.id,
        openedAt: DateTime.now(),
        cashierName: latest.cashierName,
        terminalId: latest.terminalId,
        bayLabel: latest.bayLabel,
        shiftLabel: 'Shift Berikutnya',
      );
      await newRef.set(nextShift.toFirestore());
      return;
    }

    final now = DateTime.now();
    final ref = _shiftsCol.doc('shift_${toDateKey(now)}_1');
    await ref.set(_createFreshShift(id: ref.id, openedAt: now).toFirestore());
  }
}

/// In-memory [CarwashRepository] pre-seeded for offline/demo POS operation.
class InMemoryCarwashRepository implements CarwashRepository {
  InMemoryCarwashRepository({
    this.outletId = _defaultOutletId,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _seedInitialData();
  }

  final String outletId;
  final DateTime Function() _clock;

  final _ordersController = StreamController<List<CarwashOrder>>.broadcast();
  final _baysController = StreamController<List<WashBay>>.broadcast();
  final _shiftController = StreamController<ShiftSession>.broadcast();

  final List<CarwashOrder> _orders = <CarwashOrder>[];
  final List<WashBay> _bays = <WashBay>[];
  late ShiftSession _activeShift;
  int _dailySeq = 0;
  int _shiftSeq = 1;
  bool _disposed = false;

  void _seedInitialData() {
    final now = _clock();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayKey = toDateKey(now);

    // Keep seeded createdAt inside today's calendar date even near midnight.
    DateTime todayOffset(int minutesAgo) {
      final candidate = now.subtract(Duration(minutes: minutesAgo));
      if (candidate.isBefore(todayStart)) {
        return todayStart.add(
          Duration(seconds: (240 - minutesAgo).clamp(1, 300)),
        );
      }
      return candidate;
    }

    final shiftOpenedAt = now.hour >= 8
        ? DateTime(now.year, now.month, now.day, 8)
        : todayStart;

    _activeShift = _createFreshShift(
      id: 'shift_${todayKey}_1',
      openedAt: shiftOpenedAt,
      openingCash: _defaultOpeningCash,
      // Opening 200.000 + Cash orders (50.000 + 75.000 + 30.000 = 155.000) = 355.000.
      physicalCashCount: 355000,
    );

    final mobilSmallPkg = defaultWashPackages[0]; // Rp 50.000
    final mobilMediumPkg = defaultWashPackages[1]; // Rp 75.000
    final mobilLargePkg = defaultWashPackages[2]; // Rp 100.000
    final motorMediumPkg = defaultWashPackages[4]; // Rp 30.000

    final ord1Created = todayOffset(175);
    final ord1Finished = ord1Created.add(const Duration(minutes: 33));
    final ord2Created = todayOffset(140);
    final ord2Finished = ord2Created.add(const Duration(minutes: 25));
    final ord3Created = todayOffset(95);
    final ord3Finished = ord3Created.add(const Duration(minutes: 52));
    final ord4Created = todayOffset(22);
    final ord5Created = todayOffset(14);
    final ord6Created = todayOffset(4);

    _orders.addAll([
      CarwashOrder(
        id: 'ord_seed_001',
        queueNumber: 'CW-001',
        outletId: outletId,
        shiftId: _activeShift.id,
        vehicleType: VehicleType.mobil,
        vehicleSize: VehicleSize.small,
        brand: 'Honda',
        model: 'Brio RS',
        licensePlate: 'B 1402 KJA',
        packageId: mobilSmallPkg.id,
        packageName: mobilSmallPkg.name,
        price: mobilSmallPkg.price,
        paymentMethod: PaymentMethod.cash,
        paymentStatus: PaymentStatus.paid,
        cashTendered: 50000,
        changeAmount: 0,
        status: OrderStatus.completed,
        bayId: 'bay_01',
        bayName: 'BAY 01',
        operatorName: 'Rizky Pratama',
        pickupDisplay: '+1 Jam',
        estimatedReadyAt: ord1Created.add(const Duration(minutes: 45)),
        startedWashingAt: ord1Finished.subtract(const Duration(minutes: 28)),
        finishedAt: ord1Finished,
        completedAt: ord1Finished.add(const Duration(minutes: 5)),
        createdAt: ord1Created,
        dateKey: todayKey,
      ),
      CarwashOrder(
        id: 'ord_seed_002',
        queueNumber: 'CW-002',
        outletId: outletId,
        shiftId: _activeShift.id,
        vehicleType: VehicleType.motor,
        vehicleSize: VehicleSize.medium,
        brand: 'Vespa',
        model: 'Sprint 150',
        licensePlate: 'B 6710 VSP',
        packageId: motorMediumPkg.id,
        packageName: motorMediumPkg.name,
        price: motorMediumPkg.price,
        paymentMethod: PaymentMethod.qris,
        paymentStatus: PaymentStatus.paid,
        cashTendered: 0,
        changeAmount: 0,
        qrisProofFileName: 'qris_cw002_vespa.jpg',
        status: OrderStatus.completed,
        bayId: 'bay_motor_01',
        bayName: 'BAY MOTOR 01',
        operatorName: 'Budi Santoso',
        pickupDisplay: 'Sesuai Antrian',
        estimatedReadyAt: ord2Created.add(const Duration(minutes: 30)),
        startedWashingAt: ord2Finished.subtract(const Duration(minutes: 22)),
        finishedAt: ord2Finished,
        completedAt: ord2Finished.add(const Duration(minutes: 4)),
        createdAt: ord2Created,
        dateKey: todayKey,
      ),
      CarwashOrder(
        id: 'ord_seed_003',
        queueNumber: 'CW-003',
        outletId: outletId,
        shiftId: _activeShift.id,
        vehicleType: VehicleType.mobil,
        vehicleSize: VehicleSize.large,
        brand: 'Toyota',
        model: 'Fortuner',
        licensePlate: 'B 8831 ZXP',
        packageId: mobilLargePkg.id,
        packageName: mobilLargePkg.name,
        price: mobilLargePkg.price,
        paymentMethod: PaymentMethod.qris,
        paymentStatus: PaymentStatus.paid,
        cashTendered: 0,
        changeAmount: 0,
        qrisProofFileName: 'qris_cw003_fortuner.jpg',
        status: OrderStatus.ready,
        bayId: 'bay_03',
        bayName: 'BAY 03',
        operatorName: 'Dimas Putra',
        pickupDisplay: '+1 Jam',
        estimatedReadyAt: ord3Created.add(const Duration(minutes: 60)),
        startedWashingAt: ord3Finished.subtract(const Duration(minutes: 48)),
        finishedAt: ord3Finished,
        createdAt: ord3Created,
        dateKey: todayKey,
      ),
      CarwashOrder(
        id: 'ord_seed_004',
        queueNumber: 'CW-004',
        outletId: outletId,
        shiftId: _activeShift.id,
        vehicleType: VehicleType.mobil,
        vehicleSize: VehicleSize.medium,
        brand: 'Toyota',
        model: 'Innova Reborn',
        licensePlate: 'B 2841 SKZ',
        packageId: mobilMediumPkg.id,
        packageName: mobilMediumPkg.name,
        price: mobilMediumPkg.price,
        paymentMethod: PaymentMethod.cash,
        paymentStatus: PaymentStatus.paid,
        cashTendered: 100000,
        changeAmount: 25000,
        status: OrderStatus.washing,
        bayId: 'bay_02',
        bayName: 'BAY 02',
        operatorName: 'Rizky Pratama',
        pickupDisplay: '+1 Jam',
        estimatedReadyAt: ord4Created.add(const Duration(minutes: 45)),
        startedWashingAt: ord4Created.add(const Duration(minutes: 3)),
        createdAt: ord4Created,
        dateKey: todayKey,
      ),
      CarwashOrder(
        id: 'ord_seed_005',
        queueNumber: 'CW-005',
        outletId: outletId,
        shiftId: _activeShift.id,
        vehicleType: VehicleType.motor,
        vehicleSize: VehicleSize.medium,
        brand: 'Yamaha',
        model: 'NMAX',
        licensePlate: 'B 4992 KLA',
        packageId: motorMediumPkg.id,
        packageName: motorMediumPkg.name,
        price: motorMediumPkg.price,
        paymentMethod: PaymentMethod.cash,
        paymentStatus: PaymentStatus.paid,
        cashTendered: 50000,
        changeAmount: 20000,
        status: OrderStatus.washing,
        bayId: 'bay_motor_01',
        bayName: 'BAY MOTOR 01',
        operatorName: 'Budi Santoso',
        pickupDisplay: 'Sesuai Antrian',
        estimatedReadyAt: ord5Created.add(const Duration(minutes: 25)),
        startedWashingAt: ord5Created.add(const Duration(minutes: 2)),
        createdAt: ord5Created,
        dateKey: todayKey,
      ),
      CarwashOrder(
        id: 'ord_seed_006',
        queueNumber: 'CW-006',
        outletId: outletId,
        shiftId: _activeShift.id,
        vehicleType: VehicleType.mobil,
        vehicleSize: VehicleSize.medium,
        brand: 'Honda',
        model: 'HR-V',
        licensePlate: 'D 1092 ABT',
        packageId: mobilMediumPkg.id,
        packageName: mobilMediumPkg.name,
        price: mobilMediumPkg.price,
        paymentMethod: PaymentMethod.qris,
        paymentStatus: PaymentStatus.paid,
        cashTendered: 0,
        changeAmount: 0,
        qrisProofFileName: 'qris_cw006_hrv.jpg',
        status: OrderStatus.waiting,
        pickupDisplay: '+1 Jam',
        estimatedReadyAt: ord6Created.add(const Duration(minutes: 50)),
        createdAt: ord6Created,
        dateKey: todayKey,
      ),
    ]);

    _dailySeq = 6;

    _bays.addAll([
      WashBay(
        id: 'bay_01',
        name: 'BAY 01',
        supportedType: VehicleType.mobil,
        status: BayStatus.available,
        updatedAt: ord1Finished,
      ),
      WashBay(
        id: 'bay_02',
        name: 'BAY 02',
        supportedType: VehicleType.mobil,
        status: BayStatus.occupied,
        currentOrderId: 'ord_seed_004',
        currentPlate: 'B 2841 SKZ',
        operatorName: 'Rizky Pratama',
        updatedAt: ord4Created.add(const Duration(minutes: 3)),
      ),
      WashBay(
        id: 'bay_03',
        name: 'BAY 03',
        supportedType: VehicleType.mobil,
        status: BayStatus.available,
        updatedAt: ord3Finished,
      ),
      WashBay(
        id: 'bay_motor_01',
        name: 'BAY MOTOR 01',
        supportedType: VehicleType.motor,
        status: BayStatus.occupied,
        currentOrderId: 'ord_seed_005',
        currentPlate: 'B 4992 KLA',
        operatorName: 'Budi Santoso',
        updatedAt: ord5Created.add(const Duration(minutes: 2)),
      ),
    ]);
  }

  List<CarwashOrder> _todayOrdersSnapshot() {
    final todayKey = toDateKey(_clock());
    final todayOrders =
        _orders.where((order) => order.dateKey == todayKey).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List<CarwashOrder>.unmodifiable(todayOrders);
  }

  List<WashBay> _baysSnapshot() => List<WashBay>.unmodifiable(_bays);

  void _emitOrders() {
    if (!_disposed && !_ordersController.isClosed) {
      _ordersController.add(_todayOrdersSnapshot());
    }
  }

  void _emitBays() {
    if (!_disposed && !_baysController.isClosed) {
      _baysController.add(_baysSnapshot());
    }
  }

  void _emitShift() {
    if (!_disposed && !_shiftController.isClosed) {
      _shiftController.add(_activeShift);
    }
  }

  Stream<T> _watchStream<T>(T Function() snapshot, Stream<T> broadcast) {
    return Stream.multi((controller) {
      controller.add(snapshot());
      if (_disposed) {
        controller.close();
        return;
      }
      final sub = broadcast.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = sub.cancel;
    });
  }

  @override
  Stream<List<CarwashOrder>> watchTodayOrders() =>
      _watchStream(_todayOrdersSnapshot, _ordersController.stream);

  @override
  Stream<List<WashBay>> watchBays() =>
      _watchStream(_baysSnapshot, _baysController.stream);

  @override
  Stream<ShiftSession> watchActiveShift() =>
      _watchStream(() => _activeShift, _shiftController.stream);

  @override
  Future<CarwashOrder> createOrder({
    required VehicleType vehicleType,
    required VehicleSize vehicleSize,
    required String brand,
    required String model,
    required String licensePlate,
    required WashPackage package,
    required PaymentMethod paymentMethod,
    required int cashTendered,
    required String pickupDisplay,
    required DateTime estimatedReadyAt,
    String? qrisProofFileName,
  }) async {
    if (!_activeShift.isOpen) {
      throw StateError('Shift sudah ditutup. Buka shift baru terlebih dahulu.');
    }

    final now = _clock();
    _dailySeq++;
    final queueNumber = 'CW-${_dailySeq.toString().padLeft(3, '0')}';
    final id = 'ord_${now.microsecondsSinceEpoch}_$_dailySeq';

    final order = _buildValidatedOrder(
      id: id,
      queueNumber: queueNumber,
      outletId: outletId,
      shiftId: _activeShift.id,
      vehicleType: vehicleType,
      vehicleSize: vehicleSize,
      brand: brand,
      model: model,
      licensePlate: licensePlate,
      package: package,
      paymentMethod: paymentMethod,
      cashTendered: cashTendered,
      pickupDisplay: pickupDisplay,
      estimatedReadyAt: estimatedReadyAt,
      createdAt: now,
      qrisProofFileName: qrisProofFileName,
    );

    _orders.add(order);
    _emitOrders();
    return order;
  }

  int _findOrderIndex(String orderId) {
    final index = _orders.indexWhere((order) => order.id == orderId);
    if (index < 0) {
      throw StateError('Order $orderId tidak ditemukan.');
    }
    return index;
  }

  int _findBayIndex(String bayId) {
    final index = _bays.indexWhere((bay) => bay.id == bayId);
    if (index < 0) {
      throw StateError('Bay $bayId tidak ditemukan.');
    }
    return index;
  }

  bool _releaseBayForOrder(String orderId, String? bayId, DateTime now) {
    if (bayId == null) {
      return false;
    }
    final bayIndex = _bays.indexWhere((bay) => bay.id == bayId);
    if (bayIndex < 0) {
      return false;
    }
    final bay = _bays[bayIndex];
    if (bay.currentOrderId != orderId) {
      return false;
    }
    _bays[bayIndex] = bay.copyWith(
      status: BayStatus.available,
      clearAssignment: true,
      updatedAt: now,
    );
    return true;
  }

  @override
  Future<void> startWash({
    required String orderId,
    required String bayId,
    required String operatorName,
  }) async {
    final cleanOperator = operatorName.trim();
    if (cleanOperator.isEmpty) {
      throw ArgumentError.value(
        operatorName,
        'operatorName',
        'Nama operator pencuci wajib diisi.',
      );
    }

    final orderIndex = _findOrderIndex(orderId);
    final bayIndex = _findBayIndex(bayId);

    final order = _orders[orderIndex];
    final bay = _bays[bayIndex];

    if (order.status != OrderStatus.waiting) {
      throw StateError(
        'Order ${order.queueNumber} tidak berada di antrian Menunggu.',
      );
    }
    if (!bay.isAvailable) {
      throw StateError('${bay.name} sedang terisi atau dalam perbaikan.');
    }
    if (!bay.supportsVehicleType(order.vehicleType)) {
      throw StateError(
        '${bay.name} tidak mendukung kendaraan ${order.vehicleType.label}.',
      );
    }

    final now = _clock();
    _orders[orderIndex] = order.copyWith(
      status: OrderStatus.washing,
      bayId: bay.id,
      bayName: bay.name,
      operatorName: cleanOperator,
      startedWashingAt: now,
    );
    _bays[bayIndex] = bay.copyWith(
      status: BayStatus.occupied,
      currentOrderId: order.id,
      currentPlate: order.licensePlate,
      operatorName: cleanOperator,
      updatedAt: now,
    );

    _emitOrders();
    _emitBays();
  }

  @override
  Future<void> markReadyForPickup(String orderId) async {
    final orderIndex = _findOrderIndex(orderId);
    final order = _orders[orderIndex];
    if (order.status != OrderStatus.washing) {
      throw StateError(
        'Order ${order.queueNumber} harus berstatus Dicuci sebelum ditandai Selesai.',
      );
    }

    final now = _clock();
    _orders[orderIndex] = order.copyWith(
      status: OrderStatus.ready,
      finishedAt: now,
    );
    final bayChanged = _releaseBayForOrder(order.id, order.bayId, now);

    _emitOrders();
    if (bayChanged) {
      _emitBays();
    }
  }

  @override
  Future<void> completeHandover(String orderId) async {
    final orderIndex = _findOrderIndex(orderId);
    final order = _orders[orderIndex];
    if (order.status != OrderStatus.ready &&
        order.status != OrderStatus.washing) {
      throw StateError(
        'Order ${order.queueNumber} tidak dapat diserahkan dari status ${order.status.label}.',
      );
    }

    final now = _clock();
    final bayChanged = order.status == OrderStatus.washing
        ? _releaseBayForOrder(order.id, order.bayId, now)
        : false;

    _orders[orderIndex] = order.copyWith(
      status: OrderStatus.completed,
      paymentStatus: PaymentStatus.paid,
      cashTendered:
          order.paymentMethod == PaymentMethod.cash && order.cashTendered == 0
          ? order.price
          : order.cashTendered,
      changeAmount:
          order.paymentMethod == PaymentMethod.cash && order.cashTendered == 0
          ? 0
          : order.changeAmount,
      finishedAt: order.finishedAt ?? now,
      completedAt: now,
    );

    _emitOrders();
    if (bayChanged) {
      _emitBays();
    }
  }

  @override
  Future<void> cancelOrder(String orderId) async {
    final orderIndex = _findOrderIndex(orderId);
    final order = _orders[orderIndex];
    if (order.status == OrderStatus.completed ||
        order.status == OrderStatus.cancelled) {
      throw StateError(
        'Order ${order.queueNumber} sudah ${order.status.label} dan tidak dapat dibatalkan.',
      );
    }

    final now = _clock();
    final bayChanged = order.status == OrderStatus.washing
        ? _releaseBayForOrder(order.id, order.bayId, now)
        : false;

    _orders[orderIndex] = order.copyWith(status: OrderStatus.cancelled);

    _emitOrders();
    if (bayChanged) {
      _emitBays();
    }
  }

  @override
  Future<void> updateShiftAudit({
    required int physicalCashCount,
    required String supervisorNotes,
  }) => _updateActiveShift(
    physicalCashCount: physicalCashCount,
    supervisorNotes: supervisorNotes,
    close: false,
  );

  @override
  Future<void> closeShift({
    required int physicalCashCount,
    required String supervisorNotes,
  }) => _updateActiveShift(
    physicalCashCount: physicalCashCount,
    supervisorNotes: supervisorNotes,
    close: true,
  );

  Future<void> _updateActiveShift({
    required int physicalCashCount,
    required String supervisorNotes,
    required bool close,
  }) async {
    if (physicalCashCount < 0) {
      throw ArgumentError.value(
        physicalCashCount,
        'physicalCashCount',
        'Hitungan kas fisik tidak boleh negatif.',
      );
    }
    if (!_activeShift.isOpen) {
      throw StateError('Shift sudah ditutup.');
    }

    _activeShift = _activeShift.copyWith(
      physicalCashCount: physicalCashCount,
      supervisorNotes: supervisorNotes.trim(),
      closedAt: close ? _clock() : null,
      status: close ? ShiftStatus.closed : ShiftStatus.open,
    );
    _emitShift();
  }

  @override
  Future<void> reopenDemoShift() async {
    if (_activeShift.isOpen) {
      return;
    }

    final now = _clock();
    _shiftSeq++;
    _activeShift = _createFreshShift(
      id: 'shift_${toDateKey(now)}_$_shiftSeq',
      openedAt: now,
      cashierName: _activeShift.cashierName,
      terminalId: _activeShift.terminalId,
      bayLabel: _activeShift.bayLabel,
      shiftLabel: 'Shift Berikutnya',
    );
    _emitShift();
  }

  /// Releases broadcast stream controllers when the repository is discarded.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _ordersController.close();
    _baysController.close();
    _shiftController.close();
  }
}
