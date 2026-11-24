import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseFirestore;

import '../models/carwash_order.dart';
import '../models/vehicle_catalog.dart';

/// O(1) lookup contract for ClearWash wash packages, vehicle brands, and models.
abstract interface class CatalogRepository {
  WashPackage? getPackageById(String packageId);
  WashPackage getPackageByVehicle(VehicleType type, VehicleSize size);
  List<WashPackage> getPackagesForType(VehicleType type);
  List<String> getBrandsForType(VehicleType type);
  List<VehicleSeriesSpec> getSeriesForBrand(VehicleType type, String brand);
  VehicleSeriesSpec? findSeries(
    VehicleType type,
    String brand,
    String series,
  );
  int calculatePrice({
    required VehicleType type,
    required VehicleSize size,
    int discountAmount = 0,
  });
}

/// Dictionary-indexed [CatalogRepository] guaranteeing O(1) lookups across
/// wash packages, vehicle brands, and vehicle brand/series specifications.
class MapCatalogRepository implements CatalogRepository {
  MapCatalogRepository({
    List<WashPackage> packages = defaultWashPackages,
    List<VehicleSeriesSpec> seriesList = defaultVehicleSeries,
    List<String> customCarBrands = carBrands,
    List<String> customMotorBrands = motorBrands,
  }) {
    _rebuildMaps(
      packages: packages,
      seriesList: seriesList,
      carBrandSeeds: customCarBrands,
      motorBrandSeeds: customMotorBrands,
    );
  }

  static const String defaultOutletId = 'clearwash-main';
  static const String fallbackBrandLabel = 'Lainnya';

  late Map<String, WashPackage> _packagesById;
  late Map<String, WashPackage> _packagesByVehicleKey;
  late Map<VehicleType, List<WashPackage>> _packagesByType;
  late Map<VehicleType, List<String>> _brandsByType;
  late Map<String, List<VehicleSeriesSpec>> _seriesByBrandKey;
  late Map<String, VehicleSeriesSpec> _seriesByExactKey;

  @override
  WashPackage? getPackageById(String packageId) => _packagesById[packageId];

  @override
  WashPackage getPackageByVehicle(VehicleType type, VehicleSize size) {
    final pkg = _packagesByVehicleKey[_vehicleKey(type, size)];
    if (pkg != null) {
      return pkg;
    }
    throw StateError(
      'Paket cuci untuk ${type.name}/${size.name} tidak ditemukan.',
    );
  }

  @override
  List<WashPackage> getPackagesForType(VehicleType type) =>
      _packagesByType[type] ?? const <WashPackage>[];

  @override
  List<String> getBrandsForType(VehicleType type) =>
      _brandsByType[type] ?? const <String>[];

  @override
  List<VehicleSeriesSpec> getSeriesForBrand(VehicleType type, String brand) =>
      _seriesByBrandKey[_normalizedBrandKey(type, brand)] ??
      const <VehicleSeriesSpec>[];

  @override
  VehicleSeriesSpec? findSeries(
    VehicleType type,
    String brand,
    String series,
  ) => _seriesByExactKey[_normalizedSeriesKey(type, brand, series)];

  @override
  int calculatePrice({
    required VehicleType type,
    required VehicleSize size,
    int discountAmount = 0,
  }) {
    if (discountAmount < 0) {
      throw ArgumentError.value(
        discountAmount,
        'discountAmount',
        'Diskon tidak boleh negatif.',
      );
    }
    final pkg = getPackageByVehicle(type, size);
    final netPrice = pkg.price - discountAmount;
    return netPrice < 0 ? 0 : netPrice;
  }

  /// Fetches active catalog overrides from `/outlets/{outletId}/catalogs`
  /// using the `(vehicleType, isActive)` index and atomically refreshes maps.
  Future<void> syncFromFirestore(
    FirebaseFirestore firestore, {
    String outletId = defaultOutletId,
  }) async {
    final catalogsCol = firestore.collection('outlets/$outletId/catalogs');
    final snapshots = await Future.wait([
      catalogsCol
          .where('vehicleType', isEqualTo: VehicleType.mobil.name)
          .where('isActive', isEqualTo: true)
          .get(),
      catalogsCol
          .where('vehicleType', isEqualTo: VehicleType.motor.name)
          .where('isActive', isEqualTo: true)
          .get(),
    ]);

    final mergedPackagesByVehicleKey = <String, WashPackage>{
      for (final pkg in defaultWashPackages)
        _vehicleKey(pkg.vehicleType, pkg.size): pkg,
    };
    final mergedSeriesByKey = <String, VehicleSeriesSpec>{
      for (final spec in defaultVehicleSeries)
        _normalizedSeriesKey(spec.vehicleType, spec.brand, spec.series): spec,
    };

    var hasRemoteItems = false;
    for (final snapshot in snapshots) {
      for (final doc in snapshot.docs) {
        hasRemoteItems = true;
        final data = doc.data();
        final itemType = (data['itemType'] as String?)?.trim();
        if (itemType == 'package') {
          final parsedPackage = _parseFirestorePackage(doc.id, data);
          if (parsedPackage != null) {
            mergedPackagesByVehicleKey[_vehicleKey(
              parsedPackage.vehicleType,
              parsedPackage.size,
            )] = parsedPackage;
          }
        } else if (itemType == 'vehicle_series') {
          final parsedSeries = VehicleSeriesSpec.fromFirestore(doc.id, data);
          if (parsedSeries.brand.isNotEmpty && parsedSeries.series.isNotEmpty) {
            mergedSeriesByKey[_normalizedSeriesKey(
              parsedSeries.vehicleType,
              parsedSeries.brand,
              parsedSeries.series,
            )] = parsedSeries;
          }
        }
      }
    }

    if (!hasRemoteItems) {
      return;
    }

    _rebuildMaps(
      packages: mergedPackagesByVehicleKey.values.toList(growable: false),
      seriesList: mergedSeriesByKey.values.toList(growable: false),
      carBrandSeeds: carBrands,
      motorBrandSeeds: motorBrands,
    );
  }

  void _rebuildMaps({
    required List<WashPackage> packages,
    required List<VehicleSeriesSpec> seriesList,
    required List<String> carBrandSeeds,
    required List<String> motorBrandSeeds,
  }) {
    final pkgById = <String, WashPackage>{};
    final pkgByVehicle = <String, WashPackage>{};
    final pkgBuckets = <VehicleType, List<WashPackage>>{
      for (final type in VehicleType.values) type: <WashPackage>[],
    };

    for (final pkg in packages) {
      pkgById[pkg.id] = pkg;
      pkgByVehicle[_vehicleKey(pkg.vehicleType, pkg.size)] = pkg;
      pkgBuckets[pkg.vehicleType]!.add(pkg);
    }

    for (final bucket in pkgBuckets.values) {
      bucket.sort((a, b) => a.size.index.compareTo(b.size.index));
    }

    final pkgByType = <VehicleType, List<WashPackage>>{
      for (final entry in pkgBuckets.entries)
        entry.key: List<WashPackage>.unmodifiable(entry.value),
    };

    final brandBuckets = <VehicleType, Set<String>>{
      VehicleType.mobil: <String>{
        for (final brand in carBrandSeeds)
          if (brand.trim().isNotEmpty && brand != fallbackBrandLabel)
            brand.trim(),
      },
      VehicleType.motor: <String>{
        for (final brand in motorBrandSeeds)
          if (brand.trim().isNotEmpty && brand != fallbackBrandLabel)
            brand.trim(),
      },
    };

    final seriesBrandBuckets = <String, List<VehicleSeriesSpec>>{};
    final seriesExact = <String, VehicleSeriesSpec>{};

    for (final spec in seriesList) {
      if (!spec.isActive) {
        continue;
      }
      final cleanBrand = spec.brand.trim();
      final cleanSeries = spec.series.trim();
      if (cleanBrand.isEmpty || cleanSeries.isEmpty) {
        continue;
      }

      if (cleanBrand != fallbackBrandLabel) {
        brandBuckets[spec.vehicleType]?.add(cleanBrand);
      }

      final normBrandKey = _normalizedBrandKey(spec.vehicleType, cleanBrand);
      seriesBrandBuckets
          .putIfAbsent(normBrandKey, () => <VehicleSeriesSpec>[])
          .add(spec);

      seriesExact[_normalizedSeriesKey(
        spec.vehicleType,
        cleanBrand,
        cleanSeries,
      )] = spec;
    }

    final brandsByType = <VehicleType, List<String>>{
      for (final entry in brandBuckets.entries)
        entry.key: List<String>.unmodifiable(<String>[
          ...entry.value,
          fallbackBrandLabel,
        ]),
    };

    final immutableSeriesByBrand = <String, List<VehicleSeriesSpec>>{
      for (final entry in seriesBrandBuckets.entries)
        entry.key: List<VehicleSeriesSpec>.unmodifiable(entry.value),
    };

    _packagesById = Map<String, WashPackage>.unmodifiable(pkgById);
    _packagesByVehicleKey = Map<String, WashPackage>.unmodifiable(pkgByVehicle);
    _packagesByType = Map<VehicleType, List<WashPackage>>.unmodifiable(
      pkgByType,
    );
    _brandsByType = Map<VehicleType, List<String>>.unmodifiable(brandsByType);
    _seriesByBrandKey = Map<String, List<VehicleSeriesSpec>>.unmodifiable(
      immutableSeriesByBrand,
    );
    _seriesByExactKey = Map<String, VehicleSeriesSpec>.unmodifiable(seriesExact);
  }

  static WashPackage? _parseFirestorePackage(
    String id,
    Map<String, dynamic> data,
  ) {
    final name = ((data['name'] as String?) ?? '').trim();
    final price = (data['price'] as num?)?.toInt() ?? 0;
    final estimatedMinutes = (data['estimatedMinutes'] as num?)?.toInt() ?? 0;
    if (name.isEmpty || price <= 0 || estimatedMinutes <= 0) {
      return null;
    }

    return WashPackage(
      id: id,
      vehicleType: enumFromName(
        VehicleType.values,
        data['vehicleType'],
        VehicleType.mobil,
      ),
      size: enumFromName(
        VehicleSize.values,
        data['vehicleSize'] ?? data['size'],
        VehicleSize.medium,
      ),
      name: name,
      description: ((data['description'] as String?) ?? '').trim(),
      price: price,
      estimatedMinutes: estimatedMinutes,
    );
  }

  static String _vehicleKey(VehicleType type, VehicleSize size) =>
      '${type.name}_${size.name}';

  static String _normalizedBrandKey(VehicleType type, String brand) =>
      '${type.name}_${brand.trim().toLowerCase()}';

  static String _normalizedSeriesKey(
    VehicleType type,
    String brand,
    String series,
  ) =>
      '${type.name}_${brand.trim().toLowerCase()}_${series.trim().toLowerCase()}';
}
