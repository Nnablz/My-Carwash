import '../models/carwash_order.dart';
import '../models/shift_summary.dart';

/// Contract for formatting printable POS customer tickets and shift reports.
abstract interface class ReceiptService {
  String formatOrderTicket(CarwashOrder order);
  String formatShiftClosingReceipt(ShiftReport report);
}

/// 32-column ESC/POS thermal receipt formatter for 58mm handheld printers.
class ThermalReceiptService implements ReceiptService {
  const ThermalReceiptService();

  static const int columnWidth = 32;

  @override
  String formatOrderTicket(CarwashOrder order) {
    final lines = <String>[
      _divider('='),
      _center('CLEARWASH POS'),
      _center('Car & Motorcycle Detailing'),
      _divider('-'),
      ..._keyValue('Antrian', order.queueNumber),
      ..._keyValue('Tanggal', formatDateTime(order.createdAt)),
      _divider('-'),
      ..._keyValue('Plat', order.licensePlate),
      ..._keyValue(
        'Jenis',
        '${order.vehicleType.label} (${order.vehicleSize.label})',
      ),
      ..._keyValue('Unit', order.vehicleTitle),
      _divider('-'),
      ..._twoColWrapped(order.packageName, formatRupiah(order.price)),
    ];

    if (order.bayName != null) {
      final bayDetail = order.operatorName != null
          ? '${order.bayName} (${order.operatorName})'
          : order.bayName!;
      lines.addAll(_keyValue('Bay', bayDetail));
    }

    lines.addAll(
      _keyValue(
        'Estimasi',
        '${formatClock(order.estimatedReadyAt)} (${order.pickupDisplay})',
      ),
    );

    lines
      ..add(_divider('-'))
      ..addAll(_twoColWrapped('TOTAL', formatRupiah(order.price)))
      ..addAll(
        _keyValue(
          'Metode',
          '${order.paymentMethod.label} (${order.paymentStatus.label})',
        ),
      );

    if (order.paymentMethod == PaymentMethod.cash && order.cashTendered > 0) {
      lines
        ..addAll(_twoColWrapped('Bayar', formatRupiah(order.cashTendered)))
        ..addAll(_twoColWrapped('Kembali', formatRupiah(order.changeAmount)));
    } else if (order.qrisProofFileName != null) {
      lines.addAll(_keyValue('Bukti', order.qrisProofFileName!));
    }

    lines
      ..add(_divider('-'))
      ..add(_center('Terima kasih atas kunjungan'))
      ..add(_center('Simpan struk ini sebagai'))
      ..add(_center('bukti pengambilan kendaraan'))
      ..add(_divider('='));

    return lines.join('\n');
  }

  @override
  String formatShiftClosingReceipt(ShiftReport report) {
    final shift = report.shift;
    final lines = <String>[
      _divider('='),
      _center('LAPORAN TUTUP SHIFT'),
      _center('CLEARWASH POS'),
      _divider('-'),
      ..._keyValue('Shift', shift.shiftLabel),
      ..._keyValue('Kasir', shift.cashierName),
      ..._keyValue('Terminal', shift.terminalId),
      ..._keyValue('Buka', formatDateTime(shift.openedAt)),
      ..._keyValue(
        'Tutup',
        shift.closedAt != null ? formatDateTime(shift.closedAt!) : '-',
      ),
      ..._keyValue('Status', shift.status.label),
      _divider('-'),
      'RINGKASAN PENDAPATAN',
      ..._twoColWrapped('Total Omzet', formatRupiah(report.totalRevenue)),
      ..._twoColWrapped(
        'Tunai (${report.cashCount})',
        formatRupiah(report.cashRevenue),
      ),
      ..._twoColWrapped(
        'QRIS (${report.qrisCount})',
        formatRupiah(report.qrisRevenue),
      ),
      _divider('-'),
      'VOLUME KENDARAAN',
      ..._twoColWrapped('Total Kendaraan', '${report.totalVehicles}'),
      ..._twoColWrapped(
        'Mobil (K:${report.carSmallCount} S:${report.carMediumCount} B:${report.carLargeCount})',
        '${report.carCount}',
      ),
      ..._twoColWrapped(
        'Motor (K:${report.motorSmallCount} S:${report.motorMediumCount} B:${report.motorLargeCount})',
        '${report.motorCount}',
      ),
      ..._twoColWrapped('Rata-rata Cuci', '${report.averageWashMinutes} mnt'),
      _divider('-'),
      'RINCIAN LAYANAN',
    ];

    if (report.serviceBreakdowns.isEmpty) {
      lines.add('(Belum ada transaksi)');
    } else {
      for (final item in report.serviceBreakdowns) {
        lines.addAll(
          _twoColWrapped(
            '${item.packageName} (${item.count})',
            formatRupiah(item.totalRevenue),
          ),
        );
      }
    }

    final varianceLabel = report.cashVariance > 0
        ? '+${formatRupiah(report.cashVariance)}'
        : formatRupiah(report.cashVariance);

    lines
      ..add(_divider('-'))
      ..add('REKONSILIASI LACI KAS')
      ..addAll(_twoColWrapped('Modal Awal', formatRupiah(shift.openingCash)))
      ..addAll(_twoColWrapped('Masuk Tunai', formatRupiah(report.cashRevenue)))
      ..addAll(
        _twoColWrapped('Seharusnya', formatRupiah(report.expectedCashInDrawer)),
      )
      ..addAll(
        _twoColWrapped('Fisik Laci', formatRupiah(shift.physicalCashCount)),
      )
      ..addAll(_twoColWrapped('Selisih', varianceLabel));

    if (shift.supervisorNotes.trim().isNotEmpty) {
      lines
        ..add(_divider('-'))
        ..add('Catatan Supervisor:')
        ..addAll(_wrapText(shift.supervisorNotes.trim()));
    }

    lines.add(_divider('='));
    return lines.join('\n');
  }

  String _divider(String fill) => fill * columnWidth;

  String _center(String text) {
    final trimmed = text.trim();
    if (trimmed.length >= columnWidth) {
      return trimmed.substring(0, columnWidth);
    }
    final leftPad = (columnWidth - trimmed.length) ~/ 2;
    return '${' ' * leftPad}$trimmed';
  }

  List<String> _keyValue(String label, String value) {
    final prefix = '${label.padRight(9)}: ';
    final available = columnWidth - prefix.length;
    if (available <= 4) {
      return _wrapText('$label: $value');
    }
    final wrappedValues = _wrapText(value, width: available);
    final result = <String>['$prefix${wrappedValues.first}'];
    final continuationPad = ' ' * prefix.length;
    for (var i = 1; i < wrappedValues.length; i++) {
      result.add('$continuationPad${wrappedValues[i]}');
    }
    return result;
  }

  List<String> _twoColWrapped(String left, String right) {
    if (left.length + right.length + 1 <= columnWidth) {
      final spaces = columnWidth - left.length - right.length;
      return <String>['$left${' ' * spaces}$right'];
    }
    if (right.length >= columnWidth - 1) {
      return <String>[..._wrapText(left), ..._wrapText(right)];
    }
    final firstLineWidth = columnWidth - right.length - 1;
    final leftLines = _wrapText(left, width: firstLineWidth);
    if (leftLines.length == 1) {
      final spaces = columnWidth - leftLines.first.length - right.length;
      return <String>['${leftLines.first}${' ' * spaces}$right'];
    }
    final result = _wrapText(left);
    final last = result.last;
    if (last.length + right.length + 1 <= columnWidth) {
      final spaces = columnWidth - last.length - right.length;
      result[result.length - 1] = '$last${' ' * spaces}$right';
      return result;
    }
    result.add('${' ' * (columnWidth - right.length)}$right');
    return result;
  }

  List<String> _wrapText(String text, {int width = columnWidth}) {
    final clean = text.trim();
    if (clean.isEmpty) {
      return const <String>[''];
    }
    final words = clean.split(RegExp(r'\s+'));
    final lines = <String>[];
    var current = StringBuffer();

    for (final word in words) {
      if (word.length > width) {
        if (current.isNotEmpty) {
          lines.add(current.toString());
          current = StringBuffer();
        }
        for (var i = 0; i < word.length; i += width) {
          final end = (i + width) > word.length ? word.length : i + width;
          lines.add(word.substring(i, end));
        }
        continue;
      }

      if (current.isEmpty) {
        current.write(word);
      } else if (current.length + 1 + word.length <= width) {
        current.write(' $word');
      } else {
        lines.add(current.toString());
        current = StringBuffer(word);
      }
    }

    if (current.isNotEmpty) {
      lines.add(current.toString());
    }
    return lines;
  }
}
