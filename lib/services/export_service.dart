import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show immutable;

import '../models/carwash_order.dart';
import '../models/shift_summary.dart';

/// Callback resolving the target directory path where exported CSV files are saved.
typedef ExportDirectoryResolver = Future<String> Function();

/// Result metadata and content produced by an operational CSV export.
@immutable
class ExportResult {
  const ExportResult({
    required this.fileName,
    required this.filePath,
    required this.csvContent,
    required this.rowCount,
  });

  final String fileName;
  final String filePath;
  final String csvContent;
  final int rowCount;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ExportResult &&
            runtimeType == other.runtimeType &&
            fileName == other.fileName &&
            filePath == other.filePath &&
            csvContent == other.csvContent &&
            rowCount == other.rowCount;
  }

  @override
  int get hashCode => Object.hash(fileName, filePath, csvContent, rowCount);
}

/// Contract for exporting ClearWash POS shift reports and transactions.
abstract interface class ExportService {
  String buildShiftOrdersCsv({
    required ShiftReport report,
    required List<CarwashOrder> orders,
  });

  Future<ExportResult> exportShiftReportCsv({
    required ShiftReport report,
    required List<CarwashOrder> orders,
  });
}

/// Excel-compatible UTF-8 BOM CSV exporter following RFC-4180 cell escaping.
class CsvExportService implements ExportService {
  const CsvExportService({this.directoryResolver});

  /// Optional target directory resolver (defaults to [Directory.systemTemp.path]).
  final ExportDirectoryResolver? directoryResolver;

  static const String utf8Bom = '\uFEFF';

  static const List<String> _orderColumns = <String>[
    'Antrian',
    'Tanggal',
    'Jam',
    'Plat Nomor',
    'Tipe',
    'Ukuran',
    'Merek',
    'Model',
    'Paket',
    'Harga',
    'Metode',
    'Status Bayar',
    'Status Antrian',
    'Bay',
    'Operator',
  ];

  @override
  String buildShiftOrdersCsv({
    required ShiftReport report,
    required List<CarwashOrder> orders,
  }) {
    final shift = report.shift;
    final shiftOrders = _filterAndSortShiftOrders(shift.id, orders);

    final lines = <String>[
      _csvRow(<Object?>['LAPORAN TRANSAKSI SHIFT CLEARWASH POS']),
      _csvRow(<Object?>['Shift', shift.shiftLabel]),
      _csvRow(<Object?>['ID Shift', shift.id]),
      _csvRow(<Object?>['Kasir', shift.cashierName]),
      _csvRow(<Object?>['Terminal', shift.terminalId]),
      _csvRow(<Object?>['Outlet / Bay', shift.bayLabel]),
      _csvRow(<Object?>['Waktu Buka', formatDateTime(shift.openedAt)]),
      _csvRow(<Object?>[
        'Waktu Tutup',
        shift.closedAt != null ? formatDateTime(shift.closedAt!) : '-',
      ]),
      _csvRow(<Object?>['Status Shift', shift.status.label]),
      _csvRow(<Object?>['Modal Awal', formatRupiah(shift.openingCash)]),
      _csvRow(<Object?>['Total Omzet', formatRupiah(report.totalRevenue)]),
      _csvRow(<Object?>[
        'Omzet Tunai (${report.cashCount})',
        formatRupiah(report.cashRevenue),
      ]),
      _csvRow(<Object?>[
        'Omzet QRIS (${report.qrisCount})',
        formatRupiah(report.qrisRevenue),
      ]),
      _csvRow(<Object?>[
        'Kas Diharapkan',
        formatRupiah(report.expectedCashInDrawer),
      ]),
      _csvRow(<Object?>['Fisik Laci', formatRupiah(shift.physicalCashCount)]),
      _csvRow(<Object?>['Selisih Kas', formatRupiah(report.cashVariance)]),
      _csvRow(<Object?>['Total Kendaraan', report.totalVehicles]),
      _csvRow(<Object?>['Catatan Supervisor', shift.supervisorNotes]),
      '',
      _csvRow(_orderColumns),
    ];

    var paidOrderCount = 0;
    var paidRevenueTotal = 0;

    for (final order in shiftOrders) {
      if (order.status != OrderStatus.cancelled &&
          order.paymentStatus == PaymentStatus.paid) {
        paidOrderCount++;
        paidRevenueTotal += order.price;
      }

      lines.add(
        _csvRow(<Object?>[
          order.queueNumber,
          order.dateKey,
          formatClock(order.createdAt),
          order.licensePlate,
          order.vehicleType.label,
          order.vehicleSize.label,
          order.brand,
          order.model,
          order.packageName,
          order.price,
          order.paymentMethod.label,
          order.paymentStatus.label,
          order.status.label,
          order.bayName ?? '-',
          order.operatorName ?? '-',
        ]),
      );
    }

    lines
      ..add('')
      ..add(
        _csvRow(<Object?>[
          'TOTAL TRANSAKSI TERBAYAR',
          '$paidOrderCount transaksi',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          paidRevenueTotal,
          '',
          formatRupiah(paidRevenueTotal),
          '',
          '',
          '',
        ]),
      )
      ..add(
        _csvRow(<Object?>[
          'TOTAL LAPORAN SHIFT',
          '${report.totalVehicles} kendaraan',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          report.totalRevenue,
          '',
          formatRupiah(report.totalRevenue),
          '',
          '',
          '',
        ]),
      );

    return '$utf8Bom${lines.join('\n')}';
  }

  @override
  Future<ExportResult> exportShiftReportCsv({
    required ShiftReport report,
    required List<CarwashOrder> orders,
  }) async {
    final shiftOrders = _filterAndSortShiftOrders(report.shift.id, orders);
    final csvContent = buildShiftOrdersCsv(report: report, orders: orders);

    final targetDirPath = directoryResolver != null
        ? await directoryResolver!()
        : Directory.systemTemp.path;
    final targetDir = Directory(targetDirPath);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final safeShiftId = _sanitizeFileSegment(report.shift.id);
    final datePart = toDateKey(report.shift.openedAt);
    final fileName = 'clearwash_shift_${safeShiftId}_$datePart.csv';
    final separator = targetDir.path.endsWith(Platform.pathSeparator)
        ? ''
        : Platform.pathSeparator;
    final filePath = '${targetDir.path}$separator$fileName';

    final file = File(filePath);
    await file.writeAsBytes(utf8.encode(csvContent), flush: true);

    return ExportResult(
      fileName: fileName,
      filePath: file.path,
      csvContent: csvContent,
      rowCount: shiftOrders.length,
    );
  }

  static List<CarwashOrder> _filterAndSortShiftOrders(
    String shiftId,
    List<CarwashOrder> orders,
  ) {
    final filtered = orders
        .where((order) => order.shiftId == shiftId)
        .toList(growable: true);
    filtered.sort((a, b) {
      final createdCmp = a.createdAt.compareTo(b.createdAt);
      if (createdCmp != 0) {
        return createdCmp;
      }
      return a.queueNumber.compareTo(b.queueNumber);
    });
    return filtered;
  }

  static String _csvRow(List<Object?> cells) {
    return cells.map(_escapeCsvCell).join(',');
  }

  static String _escapeCsvCell(Object? value) {
    final text = value?.toString() ?? '';
    final requiresQuoting =
        text.contains(',') ||
        text.contains('"') ||
        text.contains('\n') ||
        text.contains('\r');
    if (!requiresQuoting) {
      return text;
    }
    final escaped = text.replaceAll('"', '""');
    return '"$escaped"';
  }

  static String _sanitizeFileSegment(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return cleaned.isEmpty ? 'shift' : cleaned;
  }
}
