import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show immutable, listEquals;
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../firebase/firebase_options.dart';
import '../models/carwash_order.dart';
import '../models/shift_summary.dart';
import '../models/wash_bay.dart';
import '../repositories/carwash_repository.dart';
import '../repositories/catalog_repository.dart';
import '../services/export_service.dart';
import '../services/receipt_service.dart';

// ---------------------------------------------------------------------------
// 1. Core Dependency Injection Providers
// ---------------------------------------------------------------------------

/// Active Firebase/runtime environment resolved from `--dart-define=APP_ENV`.
final appEnvironmentProvider = Provider<AppEnvironment>(
  (ref) => AppEnvironment.fromDefine(),
);

/// Whether Firebase initialized successfully with live credentials.
final isFirebaseReadyProvider = Provider<bool>((ref) => false);

/// Singleton [FirebaseAuth] instance provided via Riverpod DI.
final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);

/// Singleton [FirebaseFirestore] instance provided via Riverpod DI.
final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

/// Active [CarwashRepository] implementation (Firestore when live, demo in-memory otherwise).
final carwashRepositoryProvider = Provider<CarwashRepository>((ref) {
  final isFirebaseReady = ref.watch(isFirebaseReadyProvider);
  if (isFirebaseReady) {
    return FirestoreCarwashRepository(firestore: ref.watch(firestoreProvider));
  }

  final repo = InMemoryCarwashRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// O(1) dictionary-indexed [CatalogRepository] with non-blocking Firestore sync.
final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  final repo = MapCatalogRepository();
  if (ref.watch(isFirebaseReadyProvider)) {
    unawaited(
      repo.syncFromFirestore(ref.watch(firestoreProvider)).catchError((_) {}),
    );
  }
  return repo;
});

/// 32-column thermal ESC/POS receipt formatter.
final receiptServiceProvider = Provider<ReceiptService>(
  (ref) => const ThermalReceiptService(),
);

/// CSV shift transaction & audit export service storing files in app documents.
final exportServiceProvider = Provider<ExportService>(
  (ref) => CsvExportService(
    directoryResolver: () async {
      final dir = await getApplicationDocumentsDirectory();
      return dir.path;
    },
  ),
);

/// Normalizes an Indonesian license plate by stripping whitespace and uppercasing.
String normalizeLicensePlate(String raw) =>
    raw.replaceAll(RegExp(r'\s+'), '').toUpperCase();

// ---------------------------------------------------------------------------
// 2. Real-Time Operational Streams & Computed Reports
// ---------------------------------------------------------------------------

/// Real-time stream of today's carwash orders.
final todayOrdersProvider = StreamProvider<List<CarwashOrder>>(
  (ref) => ref.watch(carwashRepositoryProvider).watchTodayOrders(),
);

/// Real-time stream of physical washing bays.
final baysProvider = StreamProvider<List<WashBay>>(
  (ref) => ref.watch(carwashRepositoryProvider).watchBays(),
);

/// Real-time stream of the active cashier shift session.
final activeShiftProvider = StreamProvider<ShiftSession>(
  (ref) => ref.watch(carwashRepositoryProvider).watchActiveShift(),
);

/// Real-time shift summary report aggregating active shift metadata and today's orders.
final shiftReportProvider = Provider<AsyncValue<ShiftReport>>((ref) {
  final shiftAsync = ref.watch(activeShiftProvider);
  final ordersAsync = ref.watch(todayOrdersProvider);

  return shiftAsync.when(
    data: (shift) => ordersAsync.when(
      data: (orders) => AsyncValue.data(
        ShiftReport.fromOrders(shift: shift, orders: orders),
      ),
      loading: () => const AsyncValue.loading(),
      error: (error, stackTrace) => AsyncValue.error(error, stackTrace),
    ),
    loading: () => const AsyncValue.loading(),
    error: (error, stackTrace) => AsyncValue.error(error, stackTrace),
  );
});

// ---------------------------------------------------------------------------
// 3. Navigation & Queue Filter State
// ---------------------------------------------------------------------------

/// Manages the active bottom-navigation tab index (0: Kasir, 1: Antrian, 2: Shift).
class ActiveTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setTab(int index) {
    if (index < 0 || index > 2) {
      return;
    }
    state = index;
  }

  void goToKasir() => state = 0;

  void goToAntrian() => state = 1;

  void goToShift() => state = 2;
}

/// Active bottom-navigation tab index provider.
final activeTabIndexProvider = NotifierProvider<ActiveTabNotifier, int>(
  ActiveTabNotifier.new,
);

/// Status filter pills for the live operational queue.
enum QueueFilter {
  all('Semua'),
  waiting('Tunggu'),
  washing('Cuci'),
  ready('Siap');

  const QueueFilter(this.label);

  final String label;
}

/// Manages the active [QueueFilter] selection.
class QueueFilterNotifier extends Notifier<QueueFilter> {
  @override
  QueueFilter build() => QueueFilter.all;

  void setFilter(QueueFilter filter) {
    state = filter;
  }
}

/// Active queue status filter provider.
final queueFilterProvider = NotifierProvider<QueueFilterNotifier, QueueFilter>(
  QueueFilterNotifier.new,
);

/// Aggregated counters for queue badges and operational status strips.
@immutable
class QueueStats {
  const QueueStats({
    required this.totalActive,
    required this.waiting,
    required this.washing,
    required this.ready,
    required this.completedToday,
  });

  final int totalActive;
  final int waiting;
  final int washing;
  final int ready;
  final int completedToday;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is QueueStats &&
            runtimeType == other.runtimeType &&
            totalActive == other.totalActive &&
            waiting == other.waiting &&
            washing == other.washing &&
            ready == other.ready &&
            completedToday == other.completedToday;
  }

  @override
  int get hashCode =>
      Object.hash(totalActive, waiting, washing, ready, completedToday);
}

/// Real-time counts of waiting, washing, ready, and completed orders today.
final queueStatsProvider = Provider<QueueStats>((ref) {
  final orders = ref.watch(todayOrdersProvider).value ?? const <CarwashOrder>[];

  var waiting = 0;
  var washing = 0;
  var ready = 0;
  var completedToday = 0;

  for (final order in orders) {
    switch (order.status) {
      case OrderStatus.waiting:
        waiting++;
      case OrderStatus.washing:
        washing++;
      case OrderStatus.ready:
        ready++;
      case OrderStatus.completed:
        completedToday++;
      case OrderStatus.cancelled:
        break;
    }
  }

  return QueueStats(
    totalActive: waiting + washing + ready,
    waiting: waiting,
    washing: washing,
    ready: ready,
    completedToday: completedToday,
  );
});

/// Filtered and sorted operational queue orders.
///
/// In [QueueFilter.all], completed and cancelled orders are excluded so the live
/// queue focuses on active intake, bay washing, and pickup lanes, ordered with
/// washing first, waiting by queue number, and ready last.
final filteredQueueOrdersProvider = Provider<AsyncValue<List<CarwashOrder>>>((
  ref,
) {
  final ordersAsync = ref.watch(todayOrdersProvider);
  final filter = ref.watch(queueFilterProvider);

  return ordersAsync.whenData((orders) {
    final filtered = orders.where((order) {
      return switch (filter) {
        QueueFilter.all => order.isActive,
        QueueFilter.waiting => order.status == OrderStatus.waiting,
        QueueFilter.washing => order.status == OrderStatus.washing,
        QueueFilter.ready => order.status == OrderStatus.ready,
      };
    }).toList();

    filtered.sort((a, b) {
      final statusCompare =
          _statusSortRank(a.status).compareTo(_statusSortRank(b.status));
      if (statusCompare != 0) {
        return statusCompare;
      }
      final queueCompare = _compareQueueNumber(a.queueNumber, b.queueNumber);
      if (queueCompare != 0) {
        return queueCompare;
      }
      return a.createdAt.compareTo(b.createdAt);
    });

    return List<CarwashOrder>.unmodifiable(filtered);
  });
});

int _statusSortRank(OrderStatus status) {
  return switch (status) {
    OrderStatus.washing => 0,
    OrderStatus.waiting => 1,
    OrderStatus.ready => 2,
    OrderStatus.completed => 3,
    OrderStatus.cancelled => 4,
  };
}

int _compareQueueNumber(String a, String b) {
  final digitsA = extractQueueDigits(a);
  final digitsB = extractQueueDigits(b);
  final numA = digitsA == null ? null : int.tryParse(digitsA);
  final numB = digitsB == null ? null : int.tryParse(digitsB);
  if (numA != null && numB != null) {
    final cmp = numA.compareTo(numB);
    if (cmp != 0) {
      return cmp;
    }
  }
  return a.compareTo(b);
}

// ---------------------------------------------------------------------------
// 4. Kasir Registration State & Controller
// ---------------------------------------------------------------------------

/// Quick pickup-time preset options shown in the Kasir registration flow.
enum PickupPreset {
  oneHour('+1 Jam Lagi'),
  afternoon('Sore (17:30)'),
  evening('Malam (19:00)'),
  queue('Sesuai Antrian'),
  custom('Jam Khusus');

  const PickupPreset(this.label);

  final String label;
}

/// Immutable form and submission state for the Kasir registration screen.
@immutable
class PosRegistrationState {
  const PosRegistrationState({
    this.vehicleType = VehicleType.mobil,
    required this.selectedBrand,
    required this.selectedSeries,
    required this.modelName,
    this.licensePlate = '',
    required this.selectedSize,
    required this.availableBrands,
    required this.availableSeries,
    required this.availablePackages,
    required this.selectedPackage,
    this.pickupPreset = PickupPreset.oneHour,
    this.customTime = const TimeOfDay(hour: 17, minute: 30),
    this.isSubmitting = false,
    this.errorMessage,
  });

  final VehicleType vehicleType;
  final String selectedBrand;
  final String selectedSeries;
  final String modelName;
  final String licensePlate;
  final VehicleSize selectedSize;
  final List<String> availableBrands;
  final List<String> availableSeries;
  final List<WashPackage> availablePackages;
  final WashPackage selectedPackage;
  final PickupPreset pickupPreset;
  final TimeOfDay customTime;
  final bool isSubmitting;
  final String? errorMessage;

  bool get isCustomSeries => selectedSeries == 'Lainnya';

  String get pickupDisplayText => pickupDisplayFor(DateTime.now());

  /// Formats the pickup display label for a specific reference timestamp [now].
  String pickupDisplayFor(DateTime now) {
    if (pickupPreset == PickupPreset.queue) {
      return 'Sesuai Antrian';
    }
    return 'Pukul ${formatClock(estimatedReadyAt(now))} WIB';
  }

  /// Computes the expected completion/pickup [DateTime] relative to [now].
  DateTime estimatedReadyAt(DateTime now) {
    return switch (pickupPreset) {
      PickupPreset.oneHour => now.add(const Duration(hours: 1)),
      PickupPreset.afternoon => _nextOccurrenceOf(now, 17, 30),
      PickupPreset.evening => _nextOccurrenceOf(now, 19, 0),
      PickupPreset.queue => now.add(
        Duration(minutes: selectedPackage.estimatedMinutes),
      ),
      PickupPreset.custom => _nextOccurrenceOf(
        now,
        customTime.hour,
        customTime.minute,
      ),
    };
  }

  static DateTime _nextOccurrenceOf(DateTime now, int hour, int minute) {
    final candidate = DateTime(now.year, now.month, now.day, hour, minute);
    if (candidate.isBefore(now)) {
      return candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  PosRegistrationState copyWith({
    VehicleType? vehicleType,
    String? selectedBrand,
    String? selectedSeries,
    String? modelName,
    String? licensePlate,
    VehicleSize? selectedSize,
    List<String>? availableBrands,
    List<String>? availableSeries,
    List<WashPackage>? availablePackages,
    WashPackage? selectedPackage,
    PickupPreset? pickupPreset,
    TimeOfDay? customTime,
    bool? isSubmitting,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PosRegistrationState(
      vehicleType: vehicleType ?? this.vehicleType,
      selectedBrand: selectedBrand ?? this.selectedBrand,
      selectedSeries: selectedSeries ?? this.selectedSeries,
      modelName: modelName ?? this.modelName,
      licensePlate: licensePlate ?? this.licensePlate,
      selectedSize: selectedSize ?? this.selectedSize,
      availableBrands: availableBrands ?? this.availableBrands,
      availableSeries: availableSeries ?? this.availableSeries,
      availablePackages: availablePackages ?? this.availablePackages,
      selectedPackage: selectedPackage ?? this.selectedPackage,
      pickupPreset: pickupPreset ?? this.pickupPreset,
      customTime: customTime ?? this.customTime,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PosRegistrationState &&
            runtimeType == other.runtimeType &&
            vehicleType == other.vehicleType &&
            selectedBrand == other.selectedBrand &&
            selectedSeries == other.selectedSeries &&
            modelName == other.modelName &&
            licensePlate == other.licensePlate &&
            selectedSize == other.selectedSize &&
            listEquals(availableBrands, other.availableBrands) &&
            listEquals(availableSeries, other.availableSeries) &&
            listEquals(availablePackages, other.availablePackages) &&
            selectedPackage == other.selectedPackage &&
            pickupPreset == other.pickupPreset &&
            customTime == other.customTime &&
            isSubmitting == other.isSubmitting &&
            errorMessage == other.errorMessage;
  }

  @override
  int get hashCode => Object.hashAll([
    vehicleType,
    selectedBrand,
    selectedSeries,
    modelName,
    licensePlate,
    selectedSize,
    Object.hashAll(availableBrands),
    Object.hashAll(availableSeries),
    Object.hashAll(availablePackages),
    selectedPackage,
    pickupPreset,
    customTime,
    isSubmitting,
    errorMessage,
  ]);
}

/// Manages Kasir vehicle intake form state and O(1) catalog selection.
class PosRegistrationNotifier extends Notifier<PosRegistrationState> {
  @override
  PosRegistrationState build() {
    final catalog = ref.watch(catalogRepositoryProvider);
    return _initialStateForType(catalog, VehicleType.mobil);
  }

  PosRegistrationState _initialStateForType(
    CatalogRepository catalog,
    VehicleType type,
  ) {
    final brands = catalog.getBrandsForType(type);
    final brand = brands.isNotEmpty
        ? brands.first
        : MapCatalogRepository.fallbackBrandLabel;
    final (series, model, seriesOptions, size, pkg) = _resolveBrandSelection(
      catalog,
      type,
      brand,
      VehicleSize.medium,
    );

    return PosRegistrationState(
      vehicleType: type,
      selectedBrand: brand,
      selectedSeries: series,
      modelName: model,
      selectedSize: size,
      availableBrands: brands,
      availableSeries: seriesOptions,
      availablePackages: catalog.getPackagesForType(type),
      selectedPackage: pkg,
    );
  }

  (String, String, List<String>, VehicleSize, WashPackage)
  _resolveBrandSelection(
    CatalogRepository catalog,
    VehicleType type,
    String brand,
    VehicleSize fallbackSize,
  ) {
    final specs = catalog.getSeriesForBrand(type, brand);
    final firstSpec = specs.isNotEmpty ? specs.first : null;
    final size = firstSpec?.defaultSize ?? fallbackSize;
    return (
      firstSpec?.series ?? 'Lainnya',
      firstSpec?.series ?? '',
      List<String>.unmodifiable(<String>[...specs.map((s) => s.series), 'Lainnya']),
      size,
      catalog.getPackageByVehicle(type, size),
    );
  }

  void selectVehicleType(VehicleType type) {
    if (state.vehicleType == type) {
      return;
    }
    final catalog = ref.read(catalogRepositoryProvider);
    state = _initialStateForType(catalog, type).copyWith(
      licensePlate: state.licensePlate,
      pickupPreset: state.pickupPreset,
      customTime: state.customTime,
      isSubmitting: state.isSubmitting,
    );
  }

  void setBrand(String brand) {
    final (series, model, seriesOptions, size, pkg) = _resolveBrandSelection(
      ref.read(catalogRepositoryProvider),
      state.vehicleType,
      brand,
      state.selectedSize,
    );

    state = state.copyWith(
      selectedBrand: brand,
      selectedSeries: series,
      modelName: model,
      selectedSize: size,
      availableSeries: seriesOptions,
      selectedPackage: pkg,
      clearError: true,
    );
  }

  void setSeries(String series) {
    if (series == 'Lainnya') {
      state = state.copyWith(
        selectedSeries: 'Lainnya',
        modelName: '',
        clearError: true,
      );
      return;
    }

    final catalog = ref.read(catalogRepositoryProvider);
    final spec = catalog.findSeries(
      state.vehicleType,
      state.selectedBrand,
      series,
    );
    final nextSize = spec?.defaultSize ?? state.selectedSize;
    final nextPackage = catalog.getPackageByVehicle(
      state.vehicleType,
      nextSize,
    );

    state = state.copyWith(
      selectedSeries: series,
      modelName: series,
      selectedSize: nextSize,
      selectedPackage: nextPackage,
      clearError: true,
    );
  }

  void setModelName(String model) {
    state = state.copyWith(modelName: model, clearError: true);
  }

  void setLicensePlate(String plate) {
    state = state.copyWith(
      licensePlate: normalizeLicensePlate(plate),
      clearError: true,
    );
  }

  void selectSize(VehicleSize size) {
    final catalog = ref.read(catalogRepositoryProvider);
    final nextPackage = catalog.getPackageByVehicle(state.vehicleType, size);
    state = state.copyWith(
      selectedSize: size,
      selectedPackage: nextPackage,
      clearError: true,
    );
  }

  void selectPickupPreset(PickupPreset preset) {
    state = state.copyWith(pickupPreset: preset, clearError: true);
  }

  void setCustomTime(TimeOfDay time) {
    state = state.copyWith(
      pickupPreset: PickupPreset.custom,
      customTime: time,
      clearError: true,
    );
  }

  void clearError() {
    if (state.errorMessage != null) {
      state = state.copyWith(clearError: true);
    }
  }

  Future<CarwashOrder?> submitOrder({
    required PaymentMethod paymentMethod,
    int cashTendered = 0,
    String? qrisProofFileName,
  }) async {
    if (state.isSubmitting) {
      return null;
    }

    final cleanBrand = state.selectedBrand.trim();
    final cleanModel = state.modelName.trim();
    final cleanPlate = normalizeLicensePlate(state.licensePlate);

    if (cleanBrand.isEmpty) {
      state = state.copyWith(errorMessage: 'Merek kendaraan wajib dipilih.');
      return null;
    }
    if (cleanModel.isEmpty) {
      state = state.copyWith(errorMessage: 'Model kendaraan wajib diisi.');
      return null;
    }
    if (cleanPlate.isEmpty) {
      state = state.copyWith(errorMessage: 'Plat nomor wajib diisi.');
      return null;
    }

    final snapshot = state;
    state = state.copyWith(isSubmitting: true, clearError: true);

    try {
      final now = DateTime.now();
      final order = await ref.read(carwashRepositoryProvider).createOrder(
        vehicleType: snapshot.vehicleType,
        vehicleSize: snapshot.selectedSize,
        brand: cleanBrand,
        model: cleanModel,
        licensePlate: cleanPlate,
        package: snapshot.selectedPackage,
        paymentMethod: paymentMethod,
        cashTendered: cashTendered,
        pickupDisplay: snapshot.pickupDisplayFor(now),
        estimatedReadyAt: snapshot.estimatedReadyAt(now),
        qrisProofFileName: qrisProofFileName,
      );

      if (!ref.mounted) {
        return order;
      }

      state = state.copyWith(
        modelName: snapshot.isCustomSeries ? '' : snapshot.selectedSeries,
        licensePlate: '',
        isSubmitting: false,
        clearError: true,
      );
      return order;
    } catch (error) {
      if (!ref.mounted) {
        return null;
      }
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: _formatErrorMessage(error),
      );
      return null;
    }
  }

  void resetForm() {
    state = _initialStateForType(
      ref.read(catalogRepositoryProvider),
      VehicleType.mobil,
    );
  }
}

/// Kasir registration state & controller provider.
final posRegistrationProvider =
    NotifierProvider<PosRegistrationNotifier, PosRegistrationState>(
      PosRegistrationNotifier.new,
    );

String _formatErrorMessage(Object error) {
  if (error is ArgumentError && error.message != null) {
    return error.message.toString();
  }
  if (error is StateError) {
    return error.message;
  }
  final raw = error.toString();
  if (raw.startsWith('Exception: ')) {
    return raw.substring('Exception: '.length);
  }
  return raw;
}
