import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:protein/firebase/firebase_options.dart';
import 'package:protein/models/carwash_order.dart';
import 'package:protein/models/shift_summary.dart';
import 'package:protein/models/vehicle_catalog.dart';
import 'package:protein/models/wash_bay.dart';
import 'package:protein/repositories/carwash_repository.dart';
import 'package:protein/repositories/catalog_repository.dart';
import 'package:protein/services/export_service.dart';
import 'package:protein/services/receipt_service.dart';
import 'package:protein/widgets/payment_modal.dart';

void main() {
  group('Formatting and parsing helpers', () {
    test('formatRupiah formats zero, positive, and negative IDR amounts', () {
      expect(formatRupiah(0), 'Rp 0');
      expect(formatRupiah(500), 'Rp 500');
      expect(formatRupiah(1000), 'Rp 1.000');
      expect(formatRupiah(75000), 'Rp 75.000');
      expect(formatRupiah(1250000), 'Rp 1.250.000');
      expect(formatRupiah(-25000), '-Rp 25.000');
    });

    test('toDateKey formats DateTime into zero-padded YYYY-MM-DD', () {
      expect(toDateKey(DateTime(2026, 1, 5)), '2026-01-05');
      expect(toDateKey(DateTime(2026, 11, 24, 23, 59)), '2026-11-24');
    });

    test('enumFromName resolves matching enum name or returns fallback', () {
      expect(
        enumFromName(VehicleType.values, 'motor', VehicleType.mobil),
        VehicleType.motor,
      );
      expect(
        enumFromName(VehicleType.values, 'unknown', VehicleType.mobil),
        VehicleType.mobil,
      );
      expect(
        enumFromName(OrderStatus.values, null, OrderStatus.waiting),
        OrderStatus.waiting,
      );
    });

    test('parseFirestoreTimestamp handles supported timestamp inputs', () {
      final local = DateTime(2026, 11, 24, 9, 30, 15);
      expect(parseFirestoreTimestamp(null), isNull);
      expect(parseFirestoreTimestamp(Timestamp.fromDate(local)), local);
      expect(parseFirestoreTimestamp(local), local);
      expect(
        parseFirestoreTimestamp('2026-11-24T09:30:15.000'),
        DateTime(2026, 11, 24, 9, 30, 15),
      );
      expect(
        parseFirestoreTimestamp(local.millisecondsSinceEpoch),
        DateTime.fromMillisecondsSinceEpoch(local.millisecondsSinceEpoch),
      );
      expect(parseFirestoreTimestamp(true), isNull);
    });
  });

  group('CarwashOrder', () {
    test('Firestore roundtrip preserves all fields and timestamps', () {
      final createdAt = DateTime(2026, 11, 24, 8, 15);
      final startedAt = DateTime(2026, 11, 24, 8, 20);
      final finishedAt = DateTime(2026, 11, 24, 8, 52);
      final completedAt = DateTime(2026, 11, 24, 9, 0);
      final estimatedReadyAt = DateTime(2026, 11, 24, 9, 15);

      final order = CarwashOrder(
        id: 'ord_roundtrip_1',
        queueNumber: 'CW-012',
        outletId: 'clearwash-main',
        shiftId: 'shift_2026-11-24_1',
        vehicleType: VehicleType.mobil,
        vehicleSize: VehicleSize.large,
        brand: 'Toyota',
        model: 'Fortuner GR',
        licensePlate: 'B 1234 XYZ',
        packageId: 'pkg_mobil_large',
        packageName: 'Cuci Mobil Besar',
        price: 100000,
        paymentMethod: PaymentMethod.qris,
        paymentStatus: PaymentStatus.paid,
        cashTendered: 0,
        changeAmount: 0,
        qrisProofFileName: 'QRIS_ClearWash_0815.jpg',
        status: OrderStatus.completed,
        bayId: 'bay_03',
        bayName: 'BAY 03',
        operatorName: 'Dimas Putra',
        pickupDisplay: '+1 Jam',
        estimatedReadyAt: estimatedReadyAt,
        startedWashingAt: startedAt,
        finishedAt: finishedAt,
        completedAt: completedAt,
        createdAt: createdAt,
        dateKey: '2026-11-24',
      );

      final map = order.toFirestore();
      expect(map['createdAt'], isA<Timestamp>());
      expect(map['estimatedReadyAt'], isA<Timestamp>());
      expect(map['startedWashingAt'], isA<Timestamp>());
      expect(map['finishedAt'], isA<Timestamp>());
      expect(map['completedAt'], isA<Timestamp>());
      expect(map['vehicleType'], 'mobil');
      expect(map['status'], 'completed');

      final restored = CarwashOrder.fromFirestore(order.id, map);
      expect(restored, equals(order));
      expect(restored.hashCode, equals(order.hashCode));
      expect(restored.vehicleTitle, 'Toyota Fortuner GR');
      expect(restored.washDurationMinutes, 32);
      expect(restored.isActive, isFalse);
    });

    test('fromFirestore falls back cleanly on missing/invalid fields', () {
      final created = DateTime(2026, 11, 24, 10, 0);
      final restored = CarwashOrder.fromFirestore('ord_minimal', {
        'createdAt': Timestamp.fromDate(created),
        'vehicleType': 'invalid',
        'status': 'unknown',
        'price': 50000.0,
      });

      expect(restored.id, 'ord_minimal');
      expect(restored.queueNumber, 'CW-000');
      expect(restored.vehicleType, VehicleType.mobil);
      expect(restored.vehicleSize, VehicleSize.medium);
      expect(restored.status, OrderStatus.waiting);
      expect(restored.paymentMethod, PaymentMethod.cash);
      expect(restored.paymentStatus, PaymentStatus.pending);
      expect(restored.price, 50000);
      expect(restored.estimatedReadyAt, created.add(const Duration(minutes: 45)));
      expect(restored.dateKey, '2026-11-24');
      expect(restored.isActive, isTrue);
      expect(restored.washDurationMinutes, isNull);
    });

    test('copyWith clears nullable QRIS proof and bay fields', () {
      final now = DateTime(2026, 11, 24, 11, 0);
      final order = CarwashOrder(
        id: 'ord_copy',
        queueNumber: 'CW-001',
        outletId: 'clearwash-main',
        shiftId: 'shift_1',
        vehicleType: VehicleType.motor,
        vehicleSize: VehicleSize.small,
        brand: 'Honda',
        model: 'Beat',
        licensePlate: 'B 4321 AA',
        packageId: 'pkg_motor_small',
        packageName: 'Cuci Motor Kecil',
        price: 20000,
        paymentMethod: PaymentMethod.qris,
        paymentStatus: PaymentStatus.paid,
        cashTendered: 0,
        changeAmount: 0,
        qrisProofFileName: 'proof.jpg',
        status: OrderStatus.washing,
        bayId: 'bay_motor_01',
        bayName: 'BAY MOTOR 01',
        operatorName: 'Budi',
        pickupDisplay: 'Sesuai Antrian',
        estimatedReadyAt: now.add(const Duration(minutes: 15)),
        startedWashingAt: now,
        finishedAt: now.subtract(const Duration(minutes: 5)),
        createdAt: now,
        dateKey: toDateKey(now),
      );

      expect(order.washDurationMinutes, 0);

      final cleared = order.copyWith(clearQrisProof: true, clearBay: true);
      expect(cleared.qrisProofFileName, isNull);
      expect(cleared.bayId, isNull);
      expect(cleared.bayName, isNull);
      expect(cleared.operatorName, isNull);
    });
  });

  group('WashBay', () {
    test('Firestore roundtrip, compatibility, availability, and copyWith', () {
      final updatedAt = DateTime(2026, 11, 24, 9, 45);
      final carBay = WashBay(
        id: 'bay_01',
        name: 'BAY 01',
        supportedType: VehicleType.mobil,
        status: BayStatus.available,
        updatedAt: updatedAt,
      );

      final restored = WashBay.fromFirestore('bay_01', carBay.toFirestore());
      expect(restored, equals(carBay));
      expect(restored.isAvailable, isTrue);
      expect(restored.supportsVehicleType(VehicleType.mobil), isTrue);
      expect(restored.supportsVehicleType(VehicleType.motor), isFalse);

      final universalBay = carBay.copyWith(
        clearSupportedType: true,
        status: BayStatus.occupied,
        currentOrderId: 'ord_1',
        currentPlate: 'B 1234 CD',
        operatorName: 'Asep',
      );
      expect(universalBay.supportedType, isNull);
      expect(universalBay.supportsVehicleType(VehicleType.mobil), isTrue);
      expect(universalBay.supportsVehicleType(VehicleType.motor), isTrue);
      expect(universalBay.isAvailable, isFalse);

      final universalRestored = WashBay.fromFirestore(
        universalBay.id,
        universalBay.toFirestore(),
      );
      expect(universalRestored, equals(universalBay));

      final released = universalBay.copyWith(
        status: BayStatus.available,
        clearAssignment: true,
      );
      expect(released.isAvailable, isTrue);
      expect(released.currentOrderId, isNull);
      expect(released.currentPlate, isNull);
      expect(released.operatorName, isNull);
    });
  });

  group('ShiftSession and ShiftReport', () {
    test('ShiftSession Firestore roundtrip and copyWith', () {
      final openedAt = DateTime(2026, 11, 24, 8, 0);
      final closedAt = DateTime(2026, 11, 24, 16, 0);
      final session = ShiftSession(
        id: 'shift_2026-11-24_1',
        cashierName: 'Andi Wijaya',
        terminalId: 'POS-SUNMI-01',
        bayLabel: 'Outlet Utama - 4 Bay',
        shiftLabel: 'Shift Pagi (08:00 - 16:00)',
        openedAt: openedAt,
        closedAt: closedAt,
        openingCash: 200000,
        physicalCashCount: 355000,
        supervisorNotes: 'Laci cocok',
        status: ShiftStatus.closed,
      );

      final restored = ShiftSession.fromFirestore(
        session.id,
        session.toFirestore(),
      );
      expect(restored, equals(session));
      expect(restored.isOpen, isFalse);

      final reopened = restored.copyWith(
        status: ShiftStatus.open,
        clearClosedAt: true,
      );
      expect(reopened.isOpen, isTrue);
      expect(reopened.closedAt, isNull);
    });

    test('ShiftReport.fromOrders aggregates metrics and ignores cancelled/other shifts', () {
      final base = DateTime(2026, 11, 24, 9, 0);
      final shift = ShiftSession(
        id: 'shift_A',
        cashierName: 'Andi Wijaya',
        terminalId: 'POS-SUNMI-01',
        bayLabel: 'Outlet Utama',
        shiftLabel: 'Shift Pagi',
        openedAt: DateTime(2026, 11, 24, 8, 0),
        openingCash: 200000,
        physicalCashCount: 330000,
        supervisorNotes: '',
        status: ShiftStatus.open,
      );

      CarwashOrder makeOrder({
        required String id,
        String shiftId = 'shift_A',
        required VehicleType type,
        required VehicleSize size,
        required WashPackage pkg,
        required PaymentMethod method,
        required PaymentStatus paymentStatus,
        required OrderStatus status,
        int? washMinutes,
      }) {
        return CarwashOrder(
          id: id,
          queueNumber: 'CW-$id',
          outletId: 'clearwash-main',
          shiftId: shiftId,
          vehicleType: type,
          vehicleSize: size,
          brand: 'Test',
          model: 'Unit',
          licensePlate: 'B $id AA',
          packageId: pkg.id,
          packageName: pkg.name,
          price: pkg.price,
          paymentMethod: method,
          paymentStatus: paymentStatus,
          cashTendered: method == PaymentMethod.cash && paymentStatus == PaymentStatus.paid
              ? pkg.price
              : 0,
          changeAmount: 0,
          status: status,
          pickupDisplay: '+1 Jam',
          estimatedReadyAt: base.add(const Duration(hours: 1)),
          startedWashingAt: washMinutes != null ? base : null,
          finishedAt: washMinutes != null
              ? base.add(Duration(minutes: washMinutes))
              : null,
          createdAt: base,
          dateKey: '2026-11-24',
        );
      }

      final orders = [
        // Paid cash mobil small (50k, 30m)
        makeOrder(
          id: '1',
          type: VehicleType.mobil,
          size: VehicleSize.small,
          pkg: defaultWashPackages[0],
          method: PaymentMethod.cash,
          paymentStatus: PaymentStatus.paid,
          status: OrderStatus.completed,
          washMinutes: 30,
        ),
        // Paid cash mobil medium (75k, 40m)
        makeOrder(
          id: '2',
          type: VehicleType.mobil,
          size: VehicleSize.medium,
          pkg: defaultWashPackages[1],
          method: PaymentMethod.cash,
          paymentStatus: PaymentStatus.paid,
          status: OrderStatus.completed,
          washMinutes: 40,
        ),
        // Paid qris mobil large (100k, 50m)
        makeOrder(
          id: '3',
          type: VehicleType.mobil,
          size: VehicleSize.large,
          pkg: defaultWashPackages[2],
          method: PaymentMethod.qris,
          paymentStatus: PaymentStatus.paid,
          status: OrderStatus.ready,
          washMinutes: 50,
        ),
        // Paid qris motor small (20k, no timing yet)
        makeOrder(
          id: '4',
          type: VehicleType.motor,
          size: VehicleSize.small,
          pkg: defaultWashPackages[3],
          method: PaymentMethod.qris,
          paymentStatus: PaymentStatus.paid,
          status: OrderStatus.waiting,
        ),
        // Unpaid pending motor large (50k) - counted in vehicle volume, excluded from paid revenue
        makeOrder(
          id: '5',
          type: VehicleType.motor,
          size: VehicleSize.large,
          pkg: defaultWashPackages[5],
          method: PaymentMethod.cash,
          paymentStatus: PaymentStatus.pending,
          status: OrderStatus.washing,
        ),
        // Cancelled order - completely excluded
        makeOrder(
          id: '6',
          type: VehicleType.mobil,
          size: VehicleSize.medium,
          pkg: defaultWashPackages[1],
          method: PaymentMethod.cash,
          paymentStatus: PaymentStatus.paid,
          status: OrderStatus.cancelled,
          washMinutes: 99,
        ),
        // Different shift order - completely excluded
        makeOrder(
          id: '7',
          shiftId: 'shift_B',
          type: VehicleType.motor,
          size: VehicleSize.medium,
          pkg: defaultWashPackages[4],
          method: PaymentMethod.cash,
          paymentStatus: PaymentStatus.paid,
          status: OrderStatus.completed,
          washMinutes: 10,
        ),
      ];

      final report = ShiftReport.fromOrders(shift: shift, orders: orders);

      expect(report.totalRevenue, 245000);
      expect(report.cashRevenue, 125000);
      expect(report.cashCount, 2);
      expect(report.qrisRevenue, 120000);
      expect(report.qrisCount, 2);
      expect(report.totalVehicles, 5);
      expect(report.carCount, 3);
      expect(report.carSmallCount, 1);
      expect(report.carMediumCount, 1);
      expect(report.carLargeCount, 1);
      expect(report.motorCount, 2);
      expect(report.motorSmallCount, 1);
      expect(report.motorMediumCount, 0);
      expect(report.motorLargeCount, 1);
      // (30 + 40 + 50) / 3 = 40
      expect(report.averageWashMinutes, 40);
      // Expected cash = 200.000 + 125.000 = 325.000; physical = 330.000 -> +5.000
      expect(report.expectedCashInDrawer, 325000);
      expect(report.cashVariance, 5000);
      expect(report.isCashBalanced, isFalse);

      expect(report.serviceBreakdowns.length, 4);
      expect(report.serviceBreakdowns.first.packageName, 'Cuci Mobil Besar');
      expect(report.serviceBreakdowns.first.totalRevenue, 100000);
      expect(
        report.serviceBreakdowns.first.percentage,
        closeTo((100000 / 245000) * 100, 0.001),
      );
    });

    test('ShiftReport.fromOrders handles empty order list with balanced drawer', () {
      final shift = ShiftSession(
        id: 'shift_empty',
        cashierName: 'Andi',
        terminalId: 'POS-01',
        bayLabel: 'Outlet',
        shiftLabel: 'Shift Pagi',
        openedAt: DateTime(2026, 11, 24, 8, 0),
        openingCash: 200000,
        physicalCashCount: 200000,
        supervisorNotes: '',
        status: ShiftStatus.open,
      );

      final report = ShiftReport.fromOrders(shift: shift, orders: const []);
      expect(report.totalRevenue, 0);
      expect(report.totalVehicles, 0);
      expect(report.averageWashMinutes, 0);
      expect(report.serviceBreakdowns, isEmpty);
      expect(report.expectedCashInDrawer, 200000);
      expect(report.cashVariance, 0);
      expect(report.isCashBalanced, isTrue);
    });
  });

  group('InMemoryCarwashRepository', () {
    late DateTime currentClock;
    late InMemoryCarwashRepository repo;

    setUp(() {
      currentClock = DateTime(2026, 11, 24, 11, 0);
      repo = InMemoryCarwashRepository(clock: () => currentClock);
    });

    tearDown(() {
      repo.dispose();
    });

    test('seeds initial orders, bays, and open balanced shift', () async {
      final orders = await repo.watchTodayOrders().first;
      final bays = await repo.watchBays().first;
      final shift = await repo.watchActiveShift().first;

      expect(orders.length, 6);
      expect(orders.map((o) => o.queueNumber), containsAll([
        'CW-001',
        'CW-002',
        'CW-003',
        'CW-004',
        'CW-005',
        'CW-006',
      ]));
      expect(bays.length, 4);
      expect(bays.where((b) => b.isAvailable).length, 2);
      expect(bays.where((b) => b.status == BayStatus.occupied).length, 2);

      expect(shift.isOpen, isTrue);
      expect(shift.openingCash, 200000);
      expect(shift.physicalCashCount, 355000);

      final report = ShiftReport.fromOrders(shift: shift, orders: orders);
      expect(report.totalRevenue, 360000);
      expect(report.cashRevenue, 155000);
      expect(report.qrisRevenue, 205000);
      expect(report.isCashBalanced, isTrue);
    });

    test('createOrder supports cash paid with change, pending cash, and QRIS', () async {
      final mobilPkg = defaultWashPackages[1]; // Rp 75.000
      final motorPkg = defaultWashPackages[3]; // Rp 20.000

      final cashOrder = await repo.createOrder(
        vehicleType: VehicleType.mobil,
        vehicleSize: VehicleSize.medium,
        brand: ' Toyota ',
        model: ' Avanza ',
        licensePlate: ' b 7777 cw ',
        package: mobilPkg,
        paymentMethod: PaymentMethod.cash,
        cashTendered: 100000,
        pickupDisplay: 'Pukul 12:00 WIB',
        estimatedReadyAt: currentClock.add(const Duration(hours: 1)),
      );

      expect(cashOrder.queueNumber, 'CW-007');
      expect(cashOrder.brand, 'Toyota');
      expect(cashOrder.model, 'Avanza');
      expect(cashOrder.licensePlate, 'B 7777 CW');
      expect(cashOrder.paymentStatus, PaymentStatus.paid);
      expect(cashOrder.cashTendered, 100000);
      expect(cashOrder.changeAmount, 25000);
      expect(cashOrder.status, OrderStatus.waiting);

      final pendingCash = await repo.createOrder(
        vehicleType: VehicleType.motor,
        vehicleSize: VehicleSize.small,
        brand: 'Honda',
        model: 'Beat',
        licensePlate: 'B 1111 MTR',
        package: motorPkg,
        paymentMethod: PaymentMethod.cash,
        cashTendered: 0,
        pickupDisplay: 'Sesuai Antrian',
        estimatedReadyAt: currentClock.add(const Duration(minutes: 15)),
      );
      expect(pendingCash.queueNumber, 'CW-008');
      expect(pendingCash.paymentStatus, PaymentStatus.pending);
      expect(pendingCash.cashTendered, 0);
      expect(pendingCash.changeAmount, 0);

      final qrisOrder = await repo.createOrder(
        vehicleType: VehicleType.motor,
        vehicleSize: VehicleSize.small,
        brand: 'Yamaha',
        model: 'Fazzio',
        licensePlate: 'B 2222 FZZ',
        package: motorPkg,
        paymentMethod: PaymentMethod.qris,
        cashTendered: 50000,
        pickupDisplay: 'Pukul 17:30 WIB',
        estimatedReadyAt: currentClock.add(const Duration(hours: 2)),
        qrisProofFileName: 'QRIS_ClearWash_1100.jpg',
      );
      expect(qrisOrder.queueNumber, 'CW-009');
      expect(qrisOrder.paymentStatus, PaymentStatus.paid);
      expect(qrisOrder.cashTendered, 0);
      expect(qrisOrder.changeAmount, 0);
      expect(qrisOrder.qrisProofFileName, 'QRIS_ClearWash_1100.jpg');

      final latestOrders = await repo.watchTodayOrders().first;
      expect(latestOrders.length, 9);
    });

    test('createOrder validates required fields and cash amount', () async {
      final pkg = defaultWashPackages[0]; // Rp 50.000
      Future<CarwashOrder> attempt({
        String brand = 'Honda',
        String model = 'Brio',
        String plate = 'B 1000 AA',
        String pickup = '+1 Jam',
        int cashTendered = 50000,
      }) {
        return repo.createOrder(
          vehicleType: VehicleType.mobil,
          vehicleSize: VehicleSize.small,
          brand: brand,
          model: model,
          licensePlate: plate,
          package: pkg,
          paymentMethod: PaymentMethod.cash,
          cashTendered: cashTendered,
          pickupDisplay: pickup,
          estimatedReadyAt: currentClock.add(const Duration(hours: 1)),
        );
      }

      await expectLater(attempt(brand: '  '), throwsArgumentError);
      await expectLater(attempt(model: ''), throwsArgumentError);
      await expectLater(attempt(plate: '   '), throwsArgumentError);
      await expectLater(attempt(pickup: ''), throwsArgumentError);
      await expectLater(attempt(cashTendered: -1000), throwsArgumentError);
      await expectLater(attempt(cashTendered: 40000), throwsArgumentError);
    });

    test('startWash assigns bay and enforces occupied/incompatible bay guards', () async {
      // Waiting car order: ord_seed_006
      // Occupied bay: bay_02
      // Available car bay: bay_01
      // Motor bay (currently occupied by ord_seed_005): bay_motor_01
      await expectLater(
        repo.startWash(
          orderId: 'ord_seed_006',
          bayId: 'bay_01',
          operatorName: '   ',
        ),
        throwsArgumentError,
      );

      await expectLater(
        repo.startWash(
          orderId: 'unknown_order',
          bayId: 'bay_01',
          operatorName: 'Asep',
        ),
        throwsStateError,
      );

      await expectLater(
        repo.startWash(
          orderId: 'ord_seed_006',
          bayId: 'unknown_bay',
          operatorName: 'Asep',
        ),
        throwsStateError,
      );

      // Order not waiting (ord_seed_004 is already washing)
      await expectLater(
        repo.startWash(
          orderId: 'ord_seed_004',
          bayId: 'bay_01',
          operatorName: 'Asep',
        ),
        throwsStateError,
      );

      // Occupied bay (bay_02)
      await expectLater(
        repo.startWash(
          orderId: 'ord_seed_006',
          bayId: 'bay_02',
          operatorName: 'Asep',
        ),
        throwsStateError,
      );

      // Incompatible motor order assigned to car bay_01
      final motorOrder = await repo.createOrder(
        vehicleType: VehicleType.motor,
        vehicleSize: VehicleSize.small,
        brand: 'Honda',
        model: 'Scoopy',
        licensePlate: 'B 9001 SCP',
        package: defaultWashPackages[3],
        paymentMethod: PaymentMethod.qris,
        cashTendered: 0,
        pickupDisplay: 'Sesuai Antrian',
        estimatedReadyAt: currentClock.add(const Duration(minutes: 15)),
        qrisProofFileName: 'qris_scoopy.jpg',
      );
      await expectLater(
        repo.startWash(
          orderId: motorOrder.id,
          bayId: 'bay_01',
          operatorName: 'Asep',
        ),
        throwsStateError,
      );

      // Also test car order assigned to available motor bay
      await repo.markReadyForPickup('ord_seed_005'); // frees bay_motor_01
      await expectLater(
        repo.startWash(
          orderId: 'ord_seed_006',
          bayId: 'bay_motor_01',
          operatorName: 'Asep',
        ),
        throwsStateError,
      );

      // Valid assignment
      await repo.startWash(
        orderId: 'ord_seed_006',
        bayId: 'bay_01',
        operatorName: ' Asep ',
      );

      final orders = await repo.watchTodayOrders().first;
      final bays = await repo.watchBays().first;
      final updatedOrder = orders.firstWhere((o) => o.id == 'ord_seed_006');
      final updatedBay = bays.firstWhere((b) => b.id == 'bay_01');

      expect(updatedOrder.status, OrderStatus.washing);
      expect(updatedOrder.bayId, 'bay_01');
      expect(updatedOrder.bayName, 'BAY 01');
      expect(updatedOrder.operatorName, 'Asep');
      expect(updatedOrder.startedWashingAt, currentClock);

      expect(updatedBay.status, BayStatus.occupied);
      expect(updatedBay.isAvailable, isFalse);
      expect(updatedBay.currentOrderId, 'ord_seed_006');
      expect(updatedBay.currentPlate, 'D 1092 ABT');
      expect(updatedBay.operatorName, 'Asep');
    });

    test('markReadyForPickup transitions washing order and releases bay', () async {
      await expectLater(
        repo.markReadyForPickup('ord_seed_006'), // waiting
        throwsStateError,
      );

      await repo.markReadyForPickup('ord_seed_004'); // washing in bay_02

      final orders = await repo.watchTodayOrders().first;
      final bays = await repo.watchBays().first;
      final order = orders.firstWhere((o) => o.id == 'ord_seed_004');
      final bay = bays.firstWhere((b) => b.id == 'bay_02');

      expect(order.status, OrderStatus.ready);
      expect(order.finishedAt, currentClock);
      expect(bay.status, BayStatus.available);
      expect(bay.isAvailable, isTrue);
      expect(bay.currentOrderId, isNull);
      expect(bay.currentPlate, isNull);
      expect(bay.operatorName, isNull);
    });

    test('completeHandover completes ready/washing orders and settles pending cash', () async {
      await expectLater(
        repo.completeHandover('ord_seed_006'), // waiting cannot hand over
        throwsStateError,
      );
      await expectLater(
        repo.completeHandover('ord_seed_001'), // already completed
        throwsStateError,
      );

      // Complete ready order
      await repo.completeHandover('ord_seed_003');
      var orders = await repo.watchTodayOrders().first;
      final readyDone = orders.firstWhere((o) => o.id == 'ord_seed_003');
      expect(readyDone.status, OrderStatus.completed);
      expect(readyDone.completedAt, currentClock);

      // Create pending cash order, move to washing, complete handover directly
      final pending = await repo.createOrder(
        vehicleType: VehicleType.mobil,
        vehicleSize: VehicleSize.small,
        brand: 'Suzuki',
        model: 'Ignis',
        licensePlate: 'B 3131 IGN',
        package: defaultWashPackages[0],
        paymentMethod: PaymentMethod.cash,
        cashTendered: 0,
        pickupDisplay: '+1 Jam',
        estimatedReadyAt: currentClock.add(const Duration(hours: 1)),
      );
      await repo.startWash(
        orderId: pending.id,
        bayId: 'bay_01',
        operatorName: 'Rian',
      );
      await repo.completeHandover(pending.id);

      orders = await repo.watchTodayOrders().first;
      final bays = await repo.watchBays().first;
      final settled = orders.firstWhere((o) => o.id == pending.id);
      final bay01 = bays.firstWhere((b) => b.id == 'bay_01');

      expect(settled.status, OrderStatus.completed);
      expect(settled.paymentStatus, PaymentStatus.paid);
      expect(settled.cashTendered, defaultWashPackages[0].price);
      expect(settled.changeAmount, 0);
      expect(settled.finishedAt, currentClock);
      expect(settled.completedAt, currentClock);
      expect(bay01.isAvailable, isTrue);
    });

    test('cancelOrder cancels waiting or washing orders and frees bay', () async {
      await expectLater(
        repo.cancelOrder('ord_seed_001'), // already completed
        throwsStateError,
      );

      // Cancel waiting order
      await repo.cancelOrder('ord_seed_006');
      // Cancel washing order -> should free bay_02
      await repo.cancelOrder('ord_seed_004');

      final orders = await repo.watchTodayOrders().first;
      final bays = await repo.watchBays().first;

      expect(
        orders.firstWhere((o) => o.id == 'ord_seed_006').status,
        OrderStatus.cancelled,
      );
      expect(
        orders.firstWhere((o) => o.id == 'ord_seed_004').status,
        OrderStatus.cancelled,
      );
      expect(bays.firstWhere((b) => b.id == 'bay_02').isAvailable, isTrue);

      await expectLater(
        repo.cancelOrder('ord_seed_006'), // already cancelled
        throwsStateError,
      );
    });

    test('updateShiftAudit, closeShift, and reopenDemoShift enforce lifecycle rules', () async {
      await expectLater(
        repo.updateShiftAudit(physicalCashCount: -1, supervisorNotes: ''),
        throwsArgumentError,
      );

      await repo.updateShiftAudit(
        physicalCashCount: 360000,
        supervisorNotes: '  Selisih lebih Rp 5.000  ',
      );
      var shift = await repo.watchActiveShift().first;
      expect(shift.physicalCashCount, 360000);
      expect(shift.supervisorNotes, 'Selisih lebih Rp 5.000');

      // Reopen when already open should be a no-op
      final openShiftId = shift.id;
      await repo.reopenDemoShift();
      expect((await repo.watchActiveShift().first).id, openShiftId);

      // Negative cash on closeShift throws
      await expectLater(
        repo.closeShift(physicalCashCount: -500, supervisorNotes: ''),
        throwsArgumentError,
      );

      // Close shift
      await repo.closeShift(
        physicalCashCount: 355000,
        supervisorNotes: '  Laci kas cocok  ',
      );
      shift = await repo.watchActiveShift().first;
      expect(shift.isOpen, isFalse);
      expect(shift.status, ShiftStatus.closed);
      expect(shift.closedAt, currentClock);
      expect(shift.physicalCashCount, 355000);
      expect(shift.supervisorNotes, 'Laci kas cocok');

      // Closed shift prevents new orders, audits, and re-closing
      await expectLater(
        repo.createOrder(
          vehicleType: VehicleType.mobil,
          vehicleSize: VehicleSize.small,
          brand: 'Honda',
          model: 'Brio',
          licensePlate: 'B 1234 XYZ',
          package: defaultWashPackages[0],
          paymentMethod: PaymentMethod.cash,
          cashTendered: 50000,
          pickupDisplay: '+1 Jam',
          estimatedReadyAt: currentClock.add(const Duration(hours: 1)),
        ),
        throwsStateError,
      );
      await expectLater(
        repo.updateShiftAudit(physicalCashCount: 355000, supervisorNotes: ''),
        throwsStateError,
      );
      await expectLater(
        repo.closeShift(physicalCashCount: 355000, supervisorNotes: ''),
        throwsStateError,
      );

      // Reopen demo shift creates a fresh open shift
      currentClock = currentClock.add(const Duration(minutes: 30));
      await repo.reopenDemoShift();
      final nextShift = await repo.watchActiveShift().first;
      expect(nextShift.isOpen, isTrue);
      expect(nextShift.id, isNot(openShiftId));
      expect(nextShift.shiftLabel, 'Shift Berikutnya');
      expect(nextShift.openingCash, 200000);
      expect(nextShift.physicalCashCount, 200000);

      // Can create order again on reopened shift
      final order = await repo.createOrder(
        vehicleType: VehicleType.mobil,
        vehicleSize: VehicleSize.small,
        brand: 'Honda',
        model: 'Brio',
        licensePlate: 'B 1234 XYZ',
        package: defaultWashPackages[0],
        paymentMethod: PaymentMethod.cash,
        cashTendered: 50000,
        pickupDisplay: '+1 Jam',
        estimatedReadyAt: currentClock.add(const Duration(hours: 1)),
      );
      expect(order.shiftId, nextShift.id);
    });
  });

  group('ThermalReceiptService', () {
    const service = ThermalReceiptService();

    void expectAllLinesWithin32Cols(String receipt) {
      final lines = receipt.split('\n');
      expect(lines, isNotEmpty);
      for (var i = 0; i < lines.length; i++) {
        expect(
          lines[i].length,
          lessThanOrEqualTo(ThermalReceiptService.columnWidth),
          reason: 'Line ${i + 1} exceeded 32 chars: "${lines[i]}"',
        );
      }
    }

    test('formatOrderTicket keeps all lines <= 32 chars for cash and QRIS orders', () {
      final now = DateTime(2026, 11, 24, 14, 25);
      final cashOrder = CarwashOrder(
        id: 'ord_cash',
        queueNumber: 'CW-015',
        outletId: 'clearwash-main',
        shiftId: 'shift_1',
        vehicleType: VehicleType.mobil,
        vehicleSize: VehicleSize.large,
        brand: 'Mercedes-Benz',
        model: 'GLS 450 AMG Line 4MATIC',
        licensePlate: 'B 1999 SUPER',
        packageId: 'pkg_mobil_large',
        packageName: 'Cuci Mobil Besar Detailing Plus',
        price: 1250000,
        paymentMethod: PaymentMethod.cash,
        paymentStatus: PaymentStatus.paid,
        cashTendered: 1500000,
        changeAmount: 250000,
        status: OrderStatus.washing,
        bayId: 'bay_03',
        bayName: 'BAY 03 VIP',
        operatorName: 'Rizky Pratama Putra',
        pickupDisplay: 'Pukul 17:30 WIB',
        estimatedReadyAt: now.add(const Duration(hours: 1)),
        createdAt: now,
        dateKey: toDateKey(now),
      );

      final cashTicket = service.formatOrderTicket(cashOrder);
      expectAllLinesWithin32Cols(cashTicket);
      expect(cashTicket, contains('CLEARWASH POS'));
      expect(cashTicket, contains('CW-015'));
      expect(cashTicket, contains('Rp 1.250.000'));
      expect(cashTicket, contains('Rp 1.500.000'));
      expect(cashTicket, contains('Rp 250.000'));

      final qrisOrder = cashOrder.copyWith(
        id: 'ord_qris',
        paymentMethod: PaymentMethod.qris,
        cashTendered: 0,
        changeAmount: 0,
        qrisProofFileName: 'QRIS_ClearWash_20261124_1425_longfilename.jpg',
        clearBay: true,
      );

      final qrisTicket = service.formatOrderTicket(qrisOrder);
      expectAllLinesWithin32Cols(qrisTicket);
      expect(qrisTicket, contains('QRIS (Lunas)'));
      expect(qrisTicket, contains('Bukti'));
    });

    test('formatShiftClosingReceipt keeps all lines <= 32 chars for empty and full shifts', () {
      final openedAt = DateTime(2026, 11, 24, 8, 0);
      final closedAt = DateTime(2026, 11, 24, 16, 15);

      final emptyShift = ShiftSession(
        id: 'shift_empty',
        cashierName: 'Andi Wijaya',
        terminalId: 'POS-SUNMI-01',
        bayLabel: 'Outlet Utama',
        shiftLabel: 'Shift Pagi (08:00 - 16:00)',
        openedAt: openedAt,
        openingCash: 200000,
        physicalCashCount: 200000,
        supervisorNotes: '',
        status: ShiftStatus.open,
      );
      final emptyReport = ShiftReport.fromOrders(
        shift: emptyShift,
        orders: const [],
      );
      final emptyReceipt = service.formatShiftClosingReceipt(emptyReport);
      expectAllLinesWithin32Cols(emptyReceipt);
      expect(emptyReceipt, contains('(Belum ada transaksi)'));

      final repo = InMemoryCarwashRepository(clock: () => closedAt);
      addTearDown(repo.dispose);

      // Build dense report with long supervisor notes & variance
      final closedShift = ShiftSession(
        id: 'shift_${toDateKey(closedAt)}_1',
        cashierName: 'Andi Wijaya Supervisor',
        terminalId: 'POS-SUNMI-HANDHELD-01',
        bayLabel: 'Outlet Utama',
        shiftLabel: 'Shift Pagi (08:00 - 16:00) Extended',
        openedAt: openedAt,
        closedAt: closedAt,
        openingCash: 200000,
        physicalCashCount: 365000,
        supervisorNotes:
            'Selisih lebih Rp 10.000 karena uang kembalian pelanggan belum diambil, harap dicek ulang pada shift malam.',
        status: ShiftStatus.closed,
      );

      final sampleOrders = [
        CarwashOrder(
          id: 'o1',
          queueNumber: 'CW-001',
          outletId: 'clearwash-main',
          shiftId: closedShift.id,
          vehicleType: VehicleType.mobil,
          vehicleSize: VehicleSize.large,
          brand: 'Toyota',
          model: 'Alphard',
          licensePlate: 'B 1 ALP',
          packageId: 'pkg_mobil_large',
          packageName: 'Cuci Mobil Besar Premium Detailing',
          price: 155000,
          paymentMethod: PaymentMethod.cash,
          paymentStatus: PaymentStatus.paid,
          cashTendered: 155000,
          changeAmount: 0,
          status: OrderStatus.completed,
          pickupDisplay: '+1 Jam',
          estimatedReadyAt: closedAt,
          startedWashingAt: openedAt,
          finishedAt: openedAt.add(const Duration(minutes: 45)),
          createdAt: openedAt,
          dateKey: toDateKey(closedAt),
        ),
        CarwashOrder(
          id: 'o2',
          queueNumber: 'CW-002',
          outletId: 'clearwash-main',
          shiftId: closedShift.id,
          vehicleType: VehicleType.motor,
          vehicleSize: VehicleSize.large,
          brand: 'Ducati',
          model: 'Panigale V4',
          licensePlate: 'B 444 DUC',
          packageId: 'pkg_motor_large',
          packageName: 'Cuci Motor Besar',
          price: 10000000,
          paymentMethod: PaymentMethod.qris,
          paymentStatus: PaymentStatus.paid,
          cashTendered: 0,
          changeAmount: 0,
          qrisProofFileName: 'proof.jpg',
          status: OrderStatus.completed,
          pickupDisplay: '+1 Jam',
          estimatedReadyAt: closedAt,
          startedWashingAt: openedAt,
          finishedAt: openedAt.add(const Duration(minutes: 35)),
          createdAt: openedAt,
          dateKey: toDateKey(closedAt),
        ),
      ];

      final richReport = ShiftReport.fromOrders(
        shift: closedShift,
        orders: sampleOrders,
      );
      final richReceipt = service.formatShiftClosingReceipt(richReport);
      expectAllLinesWithin32Cols(richReceipt);
      expect(richReceipt, contains('LAPORAN TUTUP SHIFT'));
      expect(richReceipt, contains('Catatan Supervisor:'));
      expect(richReceipt, contains('+Rp 10.000'));
    });
  });

  group('VehicleSeriesSpec & MapCatalogRepository', () {
    test('VehicleSeriesSpec Firestore roundtrip, fallbacks, and copyWith', () {
      const spec = VehicleSeriesSpec(
        id: 'vs_mobil_toyota_fortuner',
        vehicleType: VehicleType.mobil,
        brand: 'Toyota',
        series: 'Fortuner',
        defaultSize: VehicleSize.large,
        isActive: true,
      );

      final map = spec.toFirestore();
      expect(map['itemType'], 'vehicle_series');
      expect(map['vehicleType'], 'mobil');
      expect(map['vehicleSize'], 'large');
      expect(map['price'], isNull);
      expect(map['estimatedMinutes'], isNull);
      expect(map['isActive'], isTrue);

      final restored = VehicleSeriesSpec.fromFirestore(spec.id, map);
      expect(restored, equals(spec));
      expect(restored.hashCode, equals(spec.hashCode));

      final fallback = VehicleSeriesSpec.fromFirestore('vs_fb', {
        'brand': '  Mazda  ',
        'series': ' CX-5 ',
        'defaultSize': 'large',
      });
      expect(fallback.vehicleType, VehicleType.mobil);
      expect(fallback.brand, 'Mazda');
      expect(fallback.series, 'CX-5');
      expect(fallback.defaultSize, VehicleSize.large);
      expect(fallback.isActive, isTrue);

      final inactive = spec.copyWith(isActive: false);
      expect(inactive.isActive, isFalse);
      expect(inactive, isNot(equals(spec)));
    });

    test('O(1) package, brand, series lookups and price calculation work accurately', () {
      final catalog = MapCatalogRepository();

      // getPackageById
      expect(
        catalog.getPackageById('pkg_mobil_large')?.name,
        'Cuci Mobil Besar',
      );
      expect(catalog.getPackageById('non_existent'), isNull);

      // getPackageByVehicle
      expect(
        catalog.getPackageByVehicle(VehicleType.mobil, VehicleSize.small).price,
        50000,
      );
      expect(
        catalog.getPackageByVehicle(VehicleType.motor, VehicleSize.large).price,
        50000,
      );

      final emptyCatalog = MapCatalogRepository(packages: const []);
      expect(
        () => emptyCatalog.getPackageByVehicle(
          VehicleType.mobil,
          VehicleSize.medium,
        ),
        throwsStateError,
      );

      // getPackagesForType sorted small -> medium -> large
      final mobilPkgs = catalog.getPackagesForType(VehicleType.mobil);
      expect(
        mobilPkgs.map((p) => p.size),
        [VehicleSize.small, VehicleSize.medium, VehicleSize.large],
      );
      final motorPkgs = catalog.getPackagesForType(VehicleType.motor);
      expect(
        motorPkgs.map((p) => p.size),
        [VehicleSize.small, VehicleSize.medium, VehicleSize.large],
      );

      // getBrandsForType includes fallback 'Lainnya' at the end
      final mobilBrands = catalog.getBrandsForType(VehicleType.mobil);
      expect(mobilBrands, containsAll(['Toyota', 'Honda', 'Mercedes-Benz']));
      expect(mobilBrands.last, MapCatalogRepository.fallbackBrandLabel);

      final motorBrandsList = catalog.getBrandsForType(VehicleType.motor);
      expect(motorBrandsList, containsAll(['Honda', 'Yamaha', 'Vespa']));
      expect(motorBrandsList.last, MapCatalogRepository.fallbackBrandLabel);

      // getSeriesForBrand (exact & case-insensitive)
      final toyotaSeries = catalog.getSeriesForBrand(
        VehicleType.mobil,
        'Toyota',
      );
      expect(toyotaSeries.length, greaterThanOrEqualTo(7));
      expect(
        catalog.getSeriesForBrand(VehicleType.mobil, '  tOyOtA '),
        equals(toyotaSeries),
      );
      expect(
        catalog
            .getSeriesForBrand(VehicleType.motor, 'bmw motorrad')
            .map((s) => s.series),
        contains('R 1250 GS'),
      );
      expect(
        catalog.getSeriesForBrand(VehicleType.mobil, 'UnknownBrand'),
        isEmpty,
      );

      // findSeries (exact & case-insensitive)
      final fortuner = catalog.findSeries(
        VehicleType.mobil,
        'Toyota',
        'Fortuner',
      );
      expect(fortuner?.defaultSize, VehicleSize.large);
      expect(
        catalog.findSeries(VehicleType.mobil, '  toyota ', ' fortuner '),
        equals(fortuner),
      );
      expect(
        catalog.findSeries(VehicleType.motor, 'vespa', 'GTS 300')?.defaultSize,
        VehicleSize.large,
      );
      expect(
        catalog.findSeries(VehicleType.mobil, 'Toyota', 'Supra'),
        isNull,
      );

      // calculatePrice
      expect(
        catalog.calculatePrice(
          type: VehicleType.mobil,
          size: VehicleSize.medium,
        ),
        75000,
      );
      expect(
        catalog.calculatePrice(
          type: VehicleType.mobil,
          size: VehicleSize.medium,
          discountAmount: 15000,
        ),
        60000,
      );
      expect(
        catalog.calculatePrice(
          type: VehicleType.motor,
          size: VehicleSize.small,
          discountAmount: 50000,
        ),
        0,
      );
      expect(
        () => catalog.calculatePrice(
          type: VehicleType.mobil,
          size: VehicleSize.small,
          discountAmount: -500,
        ),
        throwsArgumentError,
      );
    });
  });

  group('CsvExportService', () {
    test('buildShiftOrdersCsv emits UTF-8 BOM, RFC-4180 escaped cells, 15 columns, and excludes other shifts', () {
      final openedAt = DateTime(2026, 11, 24, 8, 0);
      final closedAt = DateTime(2026, 11, 24, 16, 0);
      final shift = ShiftSession(
        id: 'shift_csv_1',
        cashierName: 'Andi Wijaya',
        terminalId: 'POS-SUNMI-01',
        bayLabel: 'Outlet Utama - 4 Bay',
        shiftLabel: 'Shift Pagi (08:00 - 16:00)',
        openedAt: openedAt,
        closedAt: closedAt,
        openingCash: 200000,
        physicalCashCount: 275000,
        supervisorNotes: 'Kas cocok, "shift pagi"\nselesai aman',
        status: ShiftStatus.closed,
      );

      final matchingLate = CarwashOrder(
        id: 'ord_2',
        queueNumber: 'CW-002',
        outletId: 'clearwash-main',
        shiftId: 'shift_csv_1',
        vehicleType: VehicleType.mobil,
        vehicleSize: VehicleSize.medium,
        brand: 'Honda',
        model: 'Civic, "Turbo"',
        licensePlate: 'B2222XYZ',
        packageId: 'pkg_mobil_medium',
        packageName: 'Cuci Mobil Sedang',
        price: 75000,
        paymentMethod: PaymentMethod.cash,
        paymentStatus: PaymentStatus.paid,
        cashTendered: 100000,
        changeAmount: 25000,
        status: OrderStatus.completed,
        bayId: 'bay_01',
        bayName: 'BAY 01',
        operatorName: 'Joko, S.',
        pickupDisplay: '+1 Jam',
        estimatedReadyAt: openedAt.add(const Duration(hours: 2)),
        createdAt: openedAt.add(const Duration(hours: 1)),
        dateKey: '2026-11-24',
      );

      final matchingEarly = CarwashOrder(
        id: 'ord_1',
        queueNumber: 'CW-001',
        outletId: 'clearwash-main',
        shiftId: 'shift_csv_1',
        vehicleType: VehicleType.motor,
        vehicleSize: VehicleSize.small,
        brand: 'Honda',
        model: 'Beat',
        licensePlate: 'B1111MTR',
        packageId: 'pkg_motor_small',
        packageName: 'Cuci Motor Kecil',
        price: 20000,
        paymentMethod: PaymentMethod.qris,
        paymentStatus: PaymentStatus.paid,
        cashTendered: 0,
        changeAmount: 0,
        qrisProofFileName: 'proof.jpg',
        status: OrderStatus.waiting,
        pickupDisplay: 'Sesuai Antrian',
        estimatedReadyAt: openedAt.add(const Duration(minutes: 30)),
        createdAt: openedAt.add(const Duration(minutes: 10)),
        dateKey: '2026-11-24',
      );

      final otherShiftOrder = matchingEarly.copyWith(
        id: 'ord_other',
        queueNumber: 'CW-999',
        shiftId: 'shift_other',
        licensePlate: 'B9999OTH',
      );

      final allOrders = [matchingLate, otherShiftOrder, matchingEarly];
      final report = ShiftReport.fromOrders(shift: shift, orders: allOrders);
      const service = CsvExportService();

      final csv = service.buildShiftOrdersCsv(report: report, orders: allOrders);

      expect(csv.startsWith(CsvExportService.utf8Bom), isTrue);
      expect(csv, contains('LAPORAN TRANSAKSI SHIFT CLEARWASH POS'));
      expect(
        csv,
        contains('"Kas cocok, ""shift pagi""\nselesai aman"'),
      );
      expect(
        csv,
        contains(
          'Antrian,Tanggal,Jam,Plat Nomor,Tipe,Ukuran,Merek,Model,Paket,Harga,Metode,Status Bayar,Status Antrian,Bay,Operator',
        ),
      );
      expect(csv, contains('"Civic, ""Turbo"""'));
      expect(csv, contains('"Joko, S."'));
      expect(csv, contains('TOTAL TRANSAKSI TERBAYAR,2 transaksi'));
      expect(csv, contains('TOTAL LAPORAN SHIFT,2 kendaraan'));
      expect(csv, isNot(contains('CW-999')));
      expect(csv, isNot(contains('B9999OTH')));

      // Chronological ordering: CW-001 appears before CW-002
      expect(csv.indexOf('CW-001'), lessThan(csv.indexOf('CW-002')));
    });

    test('exportShiftReportCsv writes real UTF-8 BOM CSV file to resolved temp directory', () async {
      final baseTmp = Directory(r'd:\code\Protein\build\.tmp');
      if (!baseTmp.existsSync()) {
        baseTmp.createSync(recursive: true);
      }
      final tempDir = baseTmp.createTempSync('csv_export_test_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final repo = InMemoryCarwashRepository(
        clock: () => DateTime(2026, 11, 24, 12, 0),
      );
      addTearDown(repo.dispose);

      final shift = await repo.watchActiveShift().first;
      final orders = await repo.watchTodayOrders().first;
      final report = ShiftReport.fromOrders(shift: shift, orders: orders);

      final service = CsvExportService(
        directoryResolver: () async => tempDir.path,
      );
      final result = await service.exportShiftReportCsv(
        report: report,
        orders: orders,
      );

      expect(result.fileName, endsWith('.csv'));
      expect(result.rowCount, 6);
      expect(result.csvContent.startsWith(CsvExportService.utf8Bom), isTrue);

      final exportedFile = File(result.filePath);
      expect(exportedFile.existsSync(), isTrue);

      final bytes = exportedFile.readAsBytesSync();
      // UTF-8 BOM bytes: EF BB BF (utf8.decode strips BOM in Dart)
      expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
      expect(bytes, utf8.encode(result.csvContent));
      expect(utf8.decode(bytes.sublist(3)), result.csvContent.substring(1));
    });
  });

  group('AppEnvironment, DefaultFirebaseOptions & buildQrisPayload', () {
    test('AppEnvironment and DefaultFirebaseOptions.forEnvironment map dev and prod correctly', () {
      expect(AppEnvironment.dev.label, 'DEV');
      expect(AppEnvironment.prod.label, 'PROD');
      expect(AppEnvironment.fromDefine(), AppEnvironment.dev);

      final devOptions = DefaultFirebaseOptions.forEnvironment(
        AppEnvironment.dev,
      );
      final prodOptions = DefaultFirebaseOptions.forEnvironment(
        AppEnvironment.prod,
      );

      expect(devOptions, equals(DefaultFirebaseOptions.dev));
      expect(prodOptions, equals(DefaultFirebaseOptions.prod));
      expect(devOptions.projectId, 'clearwash-pos-dev');
      expect(prodOptions.projectId, 'clearwash-pos-prod');
      expect(devOptions, isNot(equals(prodOptions)));
    });

    test('buildQrisPayload builds valid EMVCo QRIS TLV string with CRC-16/CCITT', () {
      int computeCrc16Ccitt(String input) {
        var crc = 0xFFFF;
        for (final unit in input.codeUnits) {
          crc ^= (unit & 0xFF) << 8;
          for (var i = 0; i < 8; i++) {
            crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) : (crc << 1);
            crc &= 0xFFFF;
          }
        }
        return crc;
      }

      final payload = buildQrisPayload(
        amount: 75000,
        nmid: 'ID1029384756382',
        reference: 'pkg_mobil_medium-B1234ABC',
      );

      expect(payload, startsWith('000201010212'));
      expect(payload, contains('ID.CO.QRIS.WWW'));
      expect(payload, contains('ID1029384756382'));
      expect(payload, contains('52047542'));
      expect(payload, contains('5303360'));
      expect(payload, contains('540575000'));
      expect(payload, contains('5802ID'));
      expect(payload, contains('5924CLEARWASH CAR & BIKE POS'));
      expect(payload, contains('6007JAKARTA'));

      final crcTagIndex = payload.length - 8;
      expect(payload.substring(crcTagIndex, crcTagIndex + 4), '6304');
      final body = payload.substring(0, payload.length - 4);
      final expectedHex = computeCrc16Ccitt(
        body,
      ).toRadixString(16).toUpperCase().padLeft(4, '0');
      expect(payload.substring(payload.length - 4), expectedHex);

      // Zero amount omits tag 54 and blank reference falls back to CLEARWASH
      final openAmountPayload = buildQrisPayload(
        amount: 0,
        nmid: 'ID1029384756382',
        reference: '   ',
      );
      expect(openAmountPayload, isNot(contains('530336054')));
      expect(openAmountPayload, contains('0209CLEARWASH'));

      // Overlong reference (> 25 chars) is truncated safely
      final longRefPayload = buildQrisPayload(
        amount: 50000,
        nmid: 'ID1029384756382',
        reference: '123456789012345678901234567890',
      );
      expect(longRefPayload, contains('01251234567890123456789012345'));
    });
  });
}
