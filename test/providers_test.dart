import 'dart:io';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protein/di/providers.dart';
import 'package:protein/firebase/firebase_options.dart';
import 'package:protein/models/carwash_order.dart';
import 'package:protein/models/shift_summary.dart';
import 'package:protein/models/wash_bay.dart';
import 'package:protein/repositories/carwash_repository.dart';
import 'package:protein/repositories/catalog_repository.dart';
import 'package:protein/services/export_service.dart';
import 'package:protein/services/receipt_service.dart';

void main() {
  Directory createTempExportDir() {
    final baseTmp = Directory(r'd:\code\Protein\build\.tmp');
    if (!baseTmp.existsSync()) {
      baseTmp.createSync(recursive: true);
    }
    final dir = baseTmp.createTempSync('providers_export_');
    addTearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });
    return dir;
  }

  ProviderContainer createTestContainer({Directory? exportDir}) {
    final overrides = <dynamic>[
      isFirebaseReadyProvider.overrideWithValue(false),
      if (exportDir != null)
        exportServiceProvider.overrideWithValue(
          CsvExportService(directoryResolver: () async => exportDir.path),
        ),
    ];
    final container = ProviderContainer(
      overrides: overrides.cast(),
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> waitForStreams(ProviderContainer container) async {
    container.listen(todayOrdersProvider, (_, _) {}, fireImmediately: true);
    container.listen(baysProvider, (_, _) {}, fireImmediately: true);
    container.listen(activeShiftProvider, (_, _) {}, fireImmediately: true);
    await container.read(todayOrdersProvider.future);
    await container.read(baysProvider.future);
    await container.read(activeShiftProvider.future);
  }

  Future<void> flushStreams() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  group('Core DI & navigation providers', () {
    test('resolves environment, InMemoryCarwashRepository, MapCatalogRepository, ThermalReceiptService, and CsvExportService', () {
      final container = createTestContainer();

      expect(container.read(appEnvironmentProvider), AppEnvironment.dev);
      expect(container.read(isFirebaseReadyProvider), isFalse);
      expect(
        container.read(carwashRepositoryProvider),
        isA<InMemoryCarwashRepository>(),
      );
      expect(
        container.read(catalogRepositoryProvider),
        isA<MapCatalogRepository>(),
      );
      expect(
        container.read(receiptServiceProvider),
        isA<ThermalReceiptService>(),
      );
      expect(
        container.read(exportServiceProvider),
        isA<CsvExportService>(),
      );
    });

    test('ActiveTabNotifier validates tab bounds and exposes tab helpers', () {
      final container = createTestContainer();
      final notifier = container.read(activeTabIndexProvider.notifier);

      expect(container.read(activeTabIndexProvider), 0);

      notifier.setTab(1);
      expect(container.read(activeTabIndexProvider), 1);

      notifier.setTab(-1);
      notifier.setTab(3);
      expect(container.read(activeTabIndexProvider), 1);

      notifier.goToShift();
      expect(container.read(activeTabIndexProvider), 2);

      notifier.goToAntrian();
      expect(container.read(activeTabIndexProvider), 1);

      notifier.goToKasir();
      expect(container.read(activeTabIndexProvider), 0);
    });
  });

  group('PosRegistrationNotifier', () {
    test('handles cascading catalog selections, custom series, plate normalization, and vehicle type switching', () {
      final container = createTestContainer();
      final notifier = container.read(posRegistrationProvider.notifier);

      // Initial state derived from CatalogRepository (Mobil -> Toyota -> Agya small)
      var state = container.read(posRegistrationProvider);
      expect(state.vehicleType, VehicleType.mobil);
      expect(state.selectedBrand, 'Toyota');
      expect(state.selectedSeries, 'Agya');
      expect(state.modelName, 'Agya');
      expect(state.isCustomSeries, isFalse);
      expect(state.selectedSize, VehicleSize.small);
      expect(state.availableBrands, carBrands);
      expect(state.availableSeries, containsAll(['Agya', 'Avanza', 'Fortuner', 'Lainnya']));
      expect(state.selectedPackage.id, 'pkg_mobil_small');
      expect(state.selectedPackage.price, 50000);

      // Cascading series selection auto-selects default size & price in O(1)
      notifier.setSeries('Avanza');
      state = container.read(posRegistrationProvider);
      expect(state.selectedSeries, 'Avanza');
      expect(state.modelName, 'Avanza');
      expect(state.selectedSize, VehicleSize.medium);
      expect(state.selectedPackage.id, 'pkg_mobil_medium');
      expect(state.selectedPackage.price, 75000);

      notifier.setSeries('Fortuner');
      state = container.read(posRegistrationProvider);
      expect(state.selectedSeries, 'Fortuner');
      expect(state.modelName, 'Fortuner');
      expect(state.selectedSize, VehicleSize.large);
      expect(state.selectedPackage.id, 'pkg_mobil_large');
      expect(state.selectedPackage.price, 100000);

      // Picking 'Lainnya' enables custom series mode and clears modelName while keeping size
      notifier.setSeries('Lainnya');
      state = container.read(posRegistrationProvider);
      expect(state.isCustomSeries, isTrue);
      expect(state.selectedSeries, 'Lainnya');
      expect(state.modelName, isEmpty);
      expect(state.selectedSize, VehicleSize.large);

      // Selecting same vehicle type should be a no-op
      notifier.setBrand('Honda');
      expect(container.read(posRegistrationProvider).selectedSeries, 'Brio');
      notifier.selectVehicleType(VehicleType.mobil);
      expect(container.read(posRegistrationProvider).selectedBrand, 'Honda');

      // Switch to Motor -> defaults to Honda / Beat (VehicleSize.small, Rp 20.000)
      notifier.selectVehicleType(VehicleType.motor);
      state = container.read(posRegistrationProvider);
      expect(state.vehicleType, VehicleType.motor);
      expect(state.availableBrands, motorBrands);
      expect(state.selectedBrand, 'Honda');
      expect(state.selectedSeries, 'Beat');
      expect(state.modelName, 'Beat');
      expect(state.selectedSize, VehicleSize.small);
      expect(state.selectedPackage.id, 'pkg_motor_small');
      expect(state.selectedPackage.price, 20000);
      expect(
        state.availablePackages.every((p) => p.vehicleType == VehicleType.motor),
        isTrue,
      );

      notifier.setBrand('Vespa');
      state = container.read(posRegistrationProvider);
      expect(state.selectedBrand, 'Vespa');
      expect(state.selectedSeries, 'Primavera 150');
      expect(state.selectedSize, VehicleSize.medium);
      expect(state.selectedPackage.price, 30000);

      notifier.setSeries('GTS 300');
      state = container.read(posRegistrationProvider);
      expect(state.selectedSize, VehicleSize.large);
      expect(state.selectedPackage.price, 50000);

      // License plate normalization strips whitespace & uppercases
      notifier.setLicensePlate('b 1234 abc');
      expect(container.read(posRegistrationProvider).licensePlate, 'B1234ABC');
    });

    test('computes pickup presets and custom times accurately', () {
      final container = createTestContainer();
      final notifier = container.read(posRegistrationProvider.notifier);
      notifier.setSeries('Avanza'); // 40m estimated wash duration
      final morning = DateTime(2026, 11, 24, 10, 15);
      final lateNight = DateTime(2026, 11, 24, 20, 0);

      // Default +1 Jam Lagi
      var state = container.read(posRegistrationProvider);
      expect(state.estimatedReadyAt(morning), DateTime(2026, 11, 24, 11, 15));
      expect(state.pickupDisplayFor(morning), 'Pukul 11:15 WIB');

      // Afternoon (17:30)
      notifier.selectPickupPreset(PickupPreset.afternoon);
      state = container.read(posRegistrationProvider);
      expect(state.estimatedReadyAt(morning), DateTime(2026, 11, 24, 17, 30));
      expect(state.pickupDisplayFor(morning), 'Pukul 17:30 WIB');
      expect(state.estimatedReadyAt(lateNight), DateTime(2026, 11, 25, 17, 30));

      // Evening (19:00)
      notifier.selectPickupPreset(PickupPreset.evening);
      state = container.read(posRegistrationProvider);
      expect(state.estimatedReadyAt(morning), DateTime(2026, 11, 24, 19, 0));
      expect(state.estimatedReadyAt(lateNight), DateTime(2026, 11, 25, 19, 0));

      // Queue (uses selectedPackage.estimatedMinutes = 40 for mobil medium)
      notifier.selectPickupPreset(PickupPreset.queue);
      state = container.read(posRegistrationProvider);
      expect(state.pickupDisplayFor(morning), 'Sesuai Antrian');
      expect(state.estimatedReadyAt(morning), DateTime(2026, 11, 24, 10, 55));

      // Custom time
      notifier.setCustomTime(const TimeOfDay(hour: 15, minute: 45));
      state = container.read(posRegistrationProvider);
      expect(state.pickupPreset, PickupPreset.custom);
      expect(state.customTime, const TimeOfDay(hour: 15, minute: 45));
      expect(state.estimatedReadyAt(morning), DateTime(2026, 11, 24, 15, 45));
      expect(state.pickupDisplayFor(morning), 'Pukul 15:45 WIB');
    });

    test('validates required inputs and surfaces repository errors', () async {
      final container = createTestContainer();
      await waitForStreams(container);
      final notifier = container.read(posRegistrationProvider.notifier);

      // Custom series with empty model
      notifier.setSeries('Lainnya');
      var result = await notifier.submitOrder(
        paymentMethod: PaymentMethod.cash,
        cashTendered: 100000,
      );
      expect(result, isNull);
      expect(
        container.read(posRegistrationProvider).errorMessage,
        'Model kendaraan wajib diisi.',
      );

      // Missing license plate
      notifier.setModelName('Avanza');
      expect(container.read(posRegistrationProvider).errorMessage, isNull);
      result = await notifier.submitOrder(
        paymentMethod: PaymentMethod.cash,
        cashTendered: 100000,
      );
      expect(result, isNull);
      expect(
        container.read(posRegistrationProvider).errorMessage,
        'Plat nomor wajib diisi.',
      );

      // Missing brand
      notifier.setLicensePlate('b 1234 xyz');
      notifier.setBrand('   ');
      result = await notifier.submitOrder(
        paymentMethod: PaymentMethod.cash,
        cashTendered: 100000,
      );
      expect(result, isNull);
      expect(
        container.read(posRegistrationProvider).errorMessage,
        'Merek kendaraan wajib dipilih.',
      );

      // Insufficient cash tendered propagated from repository
      notifier.setBrand('Toyota');
      notifier.setSeries('Avanza'); // Rp 75.000
      result = await notifier.submitOrder(
        paymentMethod: PaymentMethod.cash,
        cashTendered: 50000,
      );
      expect(result, isNull);
      expect(
        container.read(posRegistrationProvider).errorMessage,
        contains('Nominal tunai kurang'),
      );

      notifier.clearError();
      expect(container.read(posRegistrationProvider).errorMessage, isNull);
    });

    test('submitOrder creates cash and QRIS orders and resets plate/custom model cleanly', () async {
      final container = createTestContainer();
      await waitForStreams(container);
      final notifier = container.read(posRegistrationProvider.notifier);

      notifier.setBrand('Honda');
      notifier.setSeries('Civic'); // VehicleSize.medium = Rp 75.000
      notifier.setLicensePlate('b 8888 civ');

      final cashOrder = await notifier.submitOrder(
        paymentMethod: PaymentMethod.cash,
        cashTendered: 100000,
      );

      expect(cashOrder, isNotNull);
      expect(cashOrder!.queueNumber, 'CW-007');
      expect(cashOrder.licensePlate, 'B8888CIV');
      expect(cashOrder.model, 'Civic');
      expect(cashOrder.changeAmount, 25000);
      expect(cashOrder.paymentStatus, PaymentStatus.paid);

      var state = container.read(posRegistrationProvider);
      expect(state.modelName, 'Civic');
      expect(state.licensePlate, isEmpty);
      expect(state.isSubmitting, isFalse);
      expect(state.errorMessage, isNull);

      // Second order via QRIS using custom 'Lainnya' series on Motor
      notifier.selectVehicleType(VehicleType.motor);
      notifier.setBrand('Yamaha');
      notifier.setSeries('Lainnya');
      notifier.setModelName('Aerox 155 Special');
      notifier.setLicensePlate('b 4444 ymh');
      notifier.selectPickupPreset(PickupPreset.queue);

      final qrisOrder = await notifier.submitOrder(
        paymentMethod: PaymentMethod.qris,
        qrisProofFileName: 'QRIS_ClearWash_1200.jpg',
      );
      expect(qrisOrder, isNotNull);
      expect(qrisOrder!.queueNumber, 'CW-008');
      expect(qrisOrder.licensePlate, 'B4444YMH');
      expect(qrisOrder.paymentMethod, PaymentMethod.qris);
      expect(qrisOrder.qrisProofFileName, 'QRIS_ClearWash_1200.jpg');
      expect(qrisOrder.pickupDisplay, 'Sesuai Antrian');

      state = container.read(posRegistrationProvider);
      expect(state.modelName, isEmpty);
      expect(state.licensePlate, isEmpty);

      notifier.resetForm();
      state = container.read(posRegistrationProvider);
      expect(state.vehicleType, VehicleType.mobil);
      expect(state.selectedBrand, 'Toyota');
      expect(state.selectedSeries, 'Agya');
    });
  });

  group('Queue providers & repository actions', () {
    test('QueueFilterNotifier, queueStatsProvider, and filteredQueueOrdersProvider reflect seeded & mutated queue', () async {
      final container = createTestContainer();
      await waitForStreams(container);

      // Initial seeded stats: 1 waiting, 2 washing, 1 ready, 2 completed
      expect(
        container.read(queueStatsProvider),
        const QueueStats(
          totalActive: 4,
          waiting: 1,
          washing: 2,
          ready: 1,
          completedToday: 2,
        ),
      );

      // Default filter is all (active only, sorted washing -> waiting -> ready)
      expect(container.read(queueFilterProvider), QueueFilter.all);
      final allActive = container.read(filteredQueueOrdersProvider).value!;
      expect(
        allActive.map((o) => o.queueNumber),
        ['CW-004', 'CW-005', 'CW-006', 'CW-003'],
      );

      final filterNotifier = container.read(queueFilterProvider.notifier);
      filterNotifier.setFilter(QueueFilter.waiting);
      expect(
        container.read(filteredQueueOrdersProvider).value!.map((o) => o.queueNumber),
        ['CW-006'],
      );

      filterNotifier.setFilter(QueueFilter.washing);
      expect(
        container.read(filteredQueueOrdersProvider).value!.map((o) => o.queueNumber),
        ['CW-004', 'CW-005'],
      );

      filterNotifier.setFilter(QueueFilter.ready);
      expect(
        container.read(filteredQueueOrdersProvider).value!.map((o) => o.queueNumber),
        ['CW-003'],
      );

      filterNotifier.setFilter(QueueFilter.all);

      final repository = container.read(carwashRepositoryProvider);

      // Start wash on waiting CW-006 -> bay_01
      await repository.startWash(
        orderId: 'ord_seed_006',
        bayId: 'bay_01',
        operatorName: 'Asep',
      );
      await flushStreams();
      expect(
        container.read(queueStatsProvider),
        const QueueStats(
          totalActive: 4,
          waiting: 0,
          washing: 3,
          ready: 1,
          completedToday: 2,
        ),
      );

      // Mark washing CW-004 ready
      await repository.markReadyForPickup('ord_seed_004');
      await flushStreams();
      expect(
        container.read(queueStatsProvider),
        const QueueStats(
          totalActive: 4,
          waiting: 0,
          washing: 2,
          ready: 2,
          completedToday: 2,
        ),
      );

      // Complete handover on ready CW-003
      await repository.completeHandover('ord_seed_003');
      await flushStreams();
      expect(
        container.read(queueStatsProvider),
        const QueueStats(
          totalActive: 3,
          waiting: 0,
          washing: 2,
          ready: 1,
          completedToday: 3,
        ),
      );

      // Cancel washing CW-005
      await repository.cancelOrder('ord_seed_005');
      await flushStreams();
      expect(
        container.read(queueStatsProvider),
        const QueueStats(
          totalActive: 2,
          waiting: 0,
          washing: 1,
          ready: 1,
          completedToday: 3,
        ),
      );
      final bays = container.read(baysProvider).value!;
      expect(
        bays.firstWhere((b) => b.id == 'bay_motor_01').status,
        BayStatus.available,
      );
    });
  });

  group('Shift repository & shiftReportProvider', () {
    test('updates audit, exports CSV, closes shift, blocks new orders, and reopens demo shift', () async {
      final tempDir = createTempExportDir();
      final container = createTestContainer(exportDir: tempDir);
      await waitForStreams(container);

      var report = container.read(shiftReportProvider).value!;
      expect(report.shift.isOpen, isTrue);
      expect(report.totalRevenue, 360000);
      expect(report.cashRevenue, 155000);
      expect(report.qrisRevenue, 205000);
      expect(report.totalVehicles, 6);
      expect(report.expectedCashInDrawer, 355000);
      expect(report.cashVariance, 0);
      expect(report.isCashBalanced, isTrue);

      final repository = container.read(carwashRepositoryProvider);
      final exportService = container.read(exportServiceProvider);

      // Export CSV via ExportService
      final orders = container.read(todayOrdersProvider).value!;
      final exportResult = await exportService.exportShiftReportCsv(
        report: report,
        orders: orders,
      );
      expect(exportResult.rowCount, 6);
      expect(exportResult.csvContent.startsWith(CsvExportService.utf8Bom), isTrue);
      expect(File(exportResult.filePath).existsSync(), isTrue);

      // Update cash audit
      await repository.updateShiftAudit(
        physicalCashCount: 365000,
        supervisorNotes: 'Kelebihan Rp 10.000',
      );
      await flushStreams();

      report = container.read(shiftReportProvider).value!;
      expect(report.shift.physicalCashCount, 365000);
      expect(report.shift.supervisorNotes, 'Kelebihan Rp 10.000');
      expect(report.cashVariance, 10000);
      expect(report.isCashBalanced, isFalse);

      // Close shift
      await repository.closeShift(
        physicalCashCount: 355000,
        supervisorNotes: 'Sudah disesuaikan, laci pas',
      );
      await flushStreams();

      report = container.read(shiftReportProvider).value!;
      expect(report.shift.status, ShiftStatus.closed);
      expect(report.shift.isOpen, isFalse);
      expect(report.shift.closedAt, isNotNull);
      expect(report.isCashBalanced, isTrue);

      // Orders submitted via PosRegistrationNotifier while closed should fail cleanly
      final posNotifier = container.read(posRegistrationProvider.notifier);
      posNotifier.setModelName('Brio');
      posNotifier.setLicensePlate('B 1010 ABC');
      final blockedOrder = await posNotifier.submitOrder(
        paymentMethod: PaymentMethod.cash,
        cashTendered: 75000,
      );
      expect(blockedOrder, isNull);
      expect(
        container.read(posRegistrationProvider).errorMessage,
        contains('Shift sudah ditutup'),
      );

      // Reopen demo shift creates a fresh shift with zeroed revenue/orders
      await repository.reopenDemoShift();
      await flushStreams();

      report = container.read(shiftReportProvider).value!;
      expect(report.shift.isOpen, isTrue);
      expect(report.shift.shiftLabel, 'Shift Berikutnya');
      expect(report.totalRevenue, 0);
      expect(report.totalVehicles, 0);
      expect(report.expectedCashInDrawer, 200000);
      expect(report.isCashBalanced, isTrue);
    });
  });
}
