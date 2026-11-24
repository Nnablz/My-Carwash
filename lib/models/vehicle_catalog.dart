import 'package:flutter/foundation.dart' show immutable;

import 'carwash_order.dart';

/// Catalog specification mapping a vehicle brand and series to its default size tier.
@immutable
class VehicleSeriesSpec {
  const VehicleSeriesSpec({
    required this.id,
    required this.vehicleType,
    required this.brand,
    required this.series,
    required this.defaultSize,
    this.isActive = true,
  });

  final String id;
  final VehicleType vehicleType;
  final String brand;
  final String series;
  final VehicleSize defaultSize;
  final bool isActive;

  /// Parses a Firestore `/outlets/{outletId}/catalogs/{catalogId}` document.
  factory VehicleSeriesSpec.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return VehicleSeriesSpec(
      id: id,
      vehicleType: enumFromName(
        VehicleType.values,
        data['vehicleType'],
        VehicleType.mobil,
      ),
      brand: ((data['brand'] as String?) ?? '').trim(),
      series: ((data['series'] as String?) ?? '').trim(),
      defaultSize: enumFromName(
        VehicleSize.values,
        data['vehicleSize'] ?? data['defaultSize'],
        VehicleSize.medium,
      ),
      isActive: (data['isActive'] as bool?) ?? true,
    );
  }

  /// Serializes this entry into a Firestore `/catalogs/{catalogId}` payload.
  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'id': id,
      'itemType': 'vehicle_series',
      'vehicleType': vehicleType.name,
      'vehicleSize': defaultSize.name,
      'brand': brand,
      'series': series,
      'price': null,
      'estimatedMinutes': null,
      'isActive': isActive,
    };
  }

  VehicleSeriesSpec copyWith({
    String? id,
    VehicleType? vehicleType,
    String? brand,
    String? series,
    VehicleSize? defaultSize,
    bool? isActive,
  }) {
    return VehicleSeriesSpec(
      id: id ?? this.id,
      vehicleType: vehicleType ?? this.vehicleType,
      brand: brand ?? this.brand,
      series: series ?? this.series,
      defaultSize: defaultSize ?? this.defaultSize,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is VehicleSeriesSpec &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            vehicleType == other.vehicleType &&
            brand == other.brand &&
            series == other.series &&
            defaultSize == other.defaultSize &&
            isActive == other.isActive;
  }

  @override
  int get hashCode =>
      Object.hash(id, vehicleType, brand, series, defaultSize, isActive);
}

/// Default Indonesian car and motorcycle series catalog across [carBrands] and [motorBrands].
const List<VehicleSeriesSpec> defaultVehicleSeries = [
  // -------------------------------------------------------------------------
  // Cars (VehicleType.mobil)
  // -------------------------------------------------------------------------
  VehicleSeriesSpec(
    id: 'vs_mobil_toyota_agya',
    vehicleType: VehicleType.mobil,
    brand: 'Toyota',
    series: 'Agya',
    defaultSize: VehicleSize.small,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_toyota_raize',
    vehicleType: VehicleType.mobil,
    brand: 'Toyota',
    series: 'Raize',
    defaultSize: VehicleSize.small,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_toyota_yaris',
    vehicleType: VehicleType.mobil,
    brand: 'Toyota',
    series: 'Yaris',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_toyota_avanza',
    vehicleType: VehicleType.mobil,
    brand: 'Toyota',
    series: 'Avanza',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_toyota_veloz',
    vehicleType: VehicleType.mobil,
    brand: 'Toyota',
    series: 'Veloz',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_toyota_innova_reborn',
    vehicleType: VehicleType.mobil,
    brand: 'Toyota',
    series: 'Innova Reborn',
    defaultSize: VehicleSize.large,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_toyota_fortuner',
    vehicleType: VehicleType.mobil,
    brand: 'Toyota',
    series: 'Fortuner',
    defaultSize: VehicleSize.large,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_toyota_alphard',
    vehicleType: VehicleType.mobil,
    brand: 'Toyota',
    series: 'Alphard',
    defaultSize: VehicleSize.large,
  ),

  VehicleSeriesSpec(
    id: 'vs_mobil_honda_brio',
    vehicleType: VehicleType.mobil,
    brand: 'Honda',
    series: 'Brio',
    defaultSize: VehicleSize.small,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_honda_mobilio',
    vehicleType: VehicleType.mobil,
    brand: 'Honda',
    series: 'Mobilio',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_honda_br_v',
    vehicleType: VehicleType.mobil,
    brand: 'Honda',
    series: 'BR-V',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_honda_hr_v',
    vehicleType: VehicleType.mobil,
    brand: 'Honda',
    series: 'HR-V',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_honda_civic',
    vehicleType: VehicleType.mobil,
    brand: 'Honda',
    series: 'Civic',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_honda_cr_v',
    vehicleType: VehicleType.mobil,
    brand: 'Honda',
    series: 'CR-V',
    defaultSize: VehicleSize.large,
  ),

  VehicleSeriesSpec(
    id: 'vs_mobil_mitsubishi_xpander',
    vehicleType: VehicleType.mobil,
    brand: 'Mitsubishi',
    series: 'Xpander',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_mitsubishi_xforce',
    vehicleType: VehicleType.mobil,
    brand: 'Mitsubishi',
    series: 'Xforce',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_mitsubishi_pajero_sport',
    vehicleType: VehicleType.mobil,
    brand: 'Mitsubishi',
    series: 'Pajero Sport',
    defaultSize: VehicleSize.large,
  ),

  VehicleSeriesSpec(
    id: 'vs_mobil_daihatsu_ayla',
    vehicleType: VehicleType.mobil,
    brand: 'Daihatsu',
    series: 'Ayla',
    defaultSize: VehicleSize.small,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_daihatsu_sigra',
    vehicleType: VehicleType.mobil,
    brand: 'Daihatsu',
    series: 'Sigra',
    defaultSize: VehicleSize.small,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_daihatsu_xenia',
    vehicleType: VehicleType.mobil,
    brand: 'Daihatsu',
    series: 'Xenia',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_daihatsu_terios',
    vehicleType: VehicleType.mobil,
    brand: 'Daihatsu',
    series: 'Terios',
    defaultSize: VehicleSize.medium,
  ),

  VehicleSeriesSpec(
    id: 'vs_mobil_suzuki_baleno',
    vehicleType: VehicleType.mobil,
    brand: 'Suzuki',
    series: 'Baleno',
    defaultSize: VehicleSize.small,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_suzuki_ertiga',
    vehicleType: VehicleType.mobil,
    brand: 'Suzuki',
    series: 'Ertiga',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_suzuki_xl7',
    vehicleType: VehicleType.mobil,
    brand: 'Suzuki',
    series: 'XL7',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_suzuki_jimny',
    vehicleType: VehicleType.mobil,
    brand: 'Suzuki',
    series: 'Jimny',
    defaultSize: VehicleSize.medium,
  ),

  VehicleSeriesSpec(
    id: 'vs_mobil_wuling_air_ev',
    vehicleType: VehicleType.mobil,
    brand: 'Wuling',
    series: 'Air EV',
    defaultSize: VehicleSize.small,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_wuling_confero',
    vehicleType: VehicleType.mobil,
    brand: 'Wuling',
    series: 'Confero',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_wuling_almaz',
    vehicleType: VehicleType.mobil,
    brand: 'Wuling',
    series: 'Almaz',
    defaultSize: VehicleSize.large,
  ),

  VehicleSeriesSpec(
    id: 'vs_mobil_hyundai_creta',
    vehicleType: VehicleType.mobil,
    brand: 'Hyundai',
    series: 'Creta',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_hyundai_stargazer',
    vehicleType: VehicleType.mobil,
    brand: 'Hyundai',
    series: 'Stargazer',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_hyundai_ioniq_5',
    vehicleType: VehicleType.mobil,
    brand: 'Hyundai',
    series: 'Ioniq 5',
    defaultSize: VehicleSize.large,
  ),

  VehicleSeriesSpec(
    id: 'vs_mobil_nissan_livina',
    vehicleType: VehicleType.mobil,
    brand: 'Nissan',
    series: 'Livina',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_nissan_serena',
    vehicleType: VehicleType.mobil,
    brand: 'Nissan',
    series: 'Serena',
    defaultSize: VehicleSize.large,
  ),

  VehicleSeriesSpec(
    id: 'vs_mobil_mazda_mazda_2',
    vehicleType: VehicleType.mobil,
    brand: 'Mazda',
    series: 'Mazda 2',
    defaultSize: VehicleSize.small,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_mazda_cx_5',
    vehicleType: VehicleType.mobil,
    brand: 'Mazda',
    series: 'CX-5',
    defaultSize: VehicleSize.large,
  ),

  VehicleSeriesSpec(
    id: 'vs_mobil_kia_sonet',
    vehicleType: VehicleType.mobil,
    brand: 'Kia',
    series: 'Sonet',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_kia_carens',
    vehicleType: VehicleType.mobil,
    brand: 'Kia',
    series: 'Carens',
    defaultSize: VehicleSize.medium,
  ),

  VehicleSeriesSpec(
    id: 'vs_mobil_bmw_320i',
    vehicleType: VehicleType.mobil,
    brand: 'BMW',
    series: '320i',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_bmw_x3',
    vehicleType: VehicleType.mobil,
    brand: 'BMW',
    series: 'X3',
    defaultSize: VehicleSize.large,
  ),

  VehicleSeriesSpec(
    id: 'vs_mobil_mercedes_c200',
    vehicleType: VehicleType.mobil,
    brand: 'Mercedes-Benz',
    series: 'C200',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_mobil_mercedes_glc_300',
    vehicleType: VehicleType.mobil,
    brand: 'Mercedes-Benz',
    series: 'GLC 300',
    defaultSize: VehicleSize.large,
  ),

  // -------------------------------------------------------------------------
  // Motorcycles (VehicleType.motor)
  // -------------------------------------------------------------------------
  VehicleSeriesSpec(
    id: 'vs_motor_honda_beat',
    vehicleType: VehicleType.motor,
    brand: 'Honda',
    series: 'Beat',
    defaultSize: VehicleSize.small,
  ),
  VehicleSeriesSpec(
    id: 'vs_motor_honda_scoopy',
    vehicleType: VehicleType.motor,
    brand: 'Honda',
    series: 'Scoopy',
    defaultSize: VehicleSize.small,
  ),
  VehicleSeriesSpec(
    id: 'vs_motor_honda_vario_160',
    vehicleType: VehicleType.motor,
    brand: 'Honda',
    series: 'Vario 160',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_motor_honda_pcx_160',
    vehicleType: VehicleType.motor,
    brand: 'Honda',
    series: 'PCX 160',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_motor_honda_adv_160',
    vehicleType: VehicleType.motor,
    brand: 'Honda',
    series: 'ADV 160',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_motor_honda_cbr250rr',
    vehicleType: VehicleType.motor,
    brand: 'Honda',
    series: 'CBR250RR',
    defaultSize: VehicleSize.medium,
  ),

  VehicleSeriesSpec(
    id: 'vs_motor_yamaha_mio_m3',
    vehicleType: VehicleType.motor,
    brand: 'Yamaha',
    series: 'Mio M3',
    defaultSize: VehicleSize.small,
  ),
  VehicleSeriesSpec(
    id: 'vs_motor_yamaha_aerox_155',
    vehicleType: VehicleType.motor,
    brand: 'Yamaha',
    series: 'Aerox 155',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_motor_yamaha_nmax',
    vehicleType: VehicleType.motor,
    brand: 'Yamaha',
    series: 'NMAX',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_motor_yamaha_r15',
    vehicleType: VehicleType.motor,
    brand: 'Yamaha',
    series: 'R15',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_motor_yamaha_xmax_250',
    vehicleType: VehicleType.motor,
    brand: 'Yamaha',
    series: 'XMAX 250',
    defaultSize: VehicleSize.medium,
  ),

  VehicleSeriesSpec(
    id: 'vs_motor_suzuki_address',
    vehicleType: VehicleType.motor,
    brand: 'Suzuki',
    series: 'Address',
    defaultSize: VehicleSize.small,
  ),
  VehicleSeriesSpec(
    id: 'vs_motor_suzuki_nex_ii',
    vehicleType: VehicleType.motor,
    brand: 'Suzuki',
    series: 'Nex II',
    defaultSize: VehicleSize.small,
  ),
  VehicleSeriesSpec(
    id: 'vs_motor_suzuki_gsx_r150',
    vehicleType: VehicleType.motor,
    brand: 'Suzuki',
    series: 'GSX-R150',
    defaultSize: VehicleSize.medium,
  ),

  VehicleSeriesSpec(
    id: 'vs_motor_kawasaki_klx_150',
    vehicleType: VehicleType.motor,
    brand: 'Kawasaki',
    series: 'KLX 150',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_motor_kawasaki_ninja_250',
    vehicleType: VehicleType.motor,
    brand: 'Kawasaki',
    series: 'Ninja 250',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_motor_kawasaki_zx_25r',
    vehicleType: VehicleType.motor,
    brand: 'Kawasaki',
    series: 'ZX-25R',
    defaultSize: VehicleSize.medium,
  ),

  VehicleSeriesSpec(
    id: 'vs_motor_vespa_primavera_150',
    vehicleType: VehicleType.motor,
    brand: 'Vespa',
    series: 'Primavera 150',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_motor_vespa_sprint_150',
    vehicleType: VehicleType.motor,
    brand: 'Vespa',
    series: 'Sprint 150',
    defaultSize: VehicleSize.medium,
  ),
  VehicleSeriesSpec(
    id: 'vs_motor_vespa_gts_300',
    vehicleType: VehicleType.motor,
    brand: 'Vespa',
    series: 'GTS 300',
    defaultSize: VehicleSize.large,
  ),

  VehicleSeriesSpec(
    id: 'vs_motor_piaggio_medley_150',
    vehicleType: VehicleType.motor,
    brand: 'Piaggio',
    series: 'Medley 150',
    defaultSize: VehicleSize.medium,
  ),

  VehicleSeriesSpec(
    id: 'vs_motor_bmw_r_1250_gs',
    vehicleType: VehicleType.motor,
    brand: 'BMW Motorrad',
    series: 'R 1250 GS',
    defaultSize: VehicleSize.large,
  ),

  VehicleSeriesSpec(
    id: 'vs_motor_ducati_panigale_v4',
    vehicleType: VehicleType.motor,
    brand: 'Ducati',
    series: 'Panigale V4',
    defaultSize: VehicleSize.large,
  ),
];
