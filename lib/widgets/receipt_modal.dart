import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/carwash_order.dart';
import '../models/shift_summary.dart';
import '../services/receipt_service.dart';
import '../theme/clearwash_theme.dart';
import 'license_plate_badge.dart';

/// Displays the post-payment order ticket modal with queue number, payment
/// verification badge, toggleable 32-column thermal preview, clipboard copy, and
/// navigation actions.
Future<void> showReceiptModal(
  BuildContext context,
  CarwashOrder order, {
  required ReceiptService receiptService,
  VoidCallback? onGoToQueue,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _OrderReceiptSheet(
      order: order,
      receiptService: receiptService,
      onGoToQueue: onGoToQueue,
    ),
  );
}

/// Displays the shift closing summary & 32-column thermal audit slip modal.
Future<void> showShiftReceiptModal(
  BuildContext context,
  ShiftReport report, {
  required ReceiptService receiptService,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _ShiftReceiptSheet(
      report: report,
      receiptService: receiptService,
    ),
  );
}

Future<void> _copyToClipboard({
  required BuildContext context,
  required String text,
  required String snackbarMessage,
  required VoidCallback markCopied,
}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) {
    return;
  }
  markCopied();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(snackbarMessage),
      duration: const Duration(seconds: 2),
    ),
  );
}

class _OrderReceiptSheet extends StatefulWidget {
  const _OrderReceiptSheet({
    required this.order,
    required this.receiptService,
    this.onGoToQueue,
  });

  final CarwashOrder order;
  final ReceiptService receiptService;
  final VoidCallback? onGoToQueue;

  @override
  State<_OrderReceiptSheet> createState() => _OrderReceiptSheetState();
}

class _OrderReceiptSheetState extends State<_OrderReceiptSheet> {
  bool _showThermalPreview = false;
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isPaid = order.paymentStatus == PaymentStatus.paid;
    final thermalText = widget.receiptService.formatOrderTicket(order);

    return Container(
      decoration: ClearWashTheme.sheetDecoration(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClearWashTheme.sheetGrabber(),
            const SizedBox(height: 18),
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: ClearWashTheme.readyBg,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: ClearWashTheme.readyAccent.withValues(alpha: 0.24),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: ClearWashTheme.readyAccent,
                  size: 36,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Tiket Berhasil Dicetak!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: ClearWashTheme.slateInk,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: ClearWashTheme.slateInk,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'ANTRIAN #${extractQueueDigits(order.queueNumber) ?? order.queueNumber}',
                    style: ClearWashTheme.monoStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isPaid
                        ? ClearWashTheme.readyBg
                        : ClearWashTheme.waitingBg,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    isPaid ? 'LUNAS' : 'BELUM BAYAR',
                    style: ClearWashTheme.monoStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: isPaid
                          ? ClearWashTheme.readyText
                          : ClearWashTheme.waitingText,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: ClearWashTheme.cardDecoration(
                color: ClearWashTheme.canvas,
                radius: 16,
                elevated: false,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              order.vehicleTitle,
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                                color: ClearWashTheme.slateInk,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${order.vehicleType.label} • Ukuran ${order.vehicleSize.label}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: ClearWashTheme.slateMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      LicensePlateBadge(
                        plate: order.licensePlate,
                        compact: true,
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1),
                  ),
                  _ReceiptInfoRow(
                    label: 'Kode Antrian',
                    value: order.queueNumber,
                    mono: true,
                  ),
                  _ReceiptInfoRow(
                    label: 'Paket Layanan',
                    value: order.packageName,
                  ),
                  _ReceiptInfoRow(
                    label: 'Siap Ambil',
                    value:
                        '${formatClock(order.estimatedReadyAt)} WIB (${order.pickupDisplay})',
                    mono: true,
                  ),
                  _ReceiptInfoRow(
                    label: 'Metode Bayar',
                    value: order.qrisProofFileName != null
                        ? '${order.paymentMethod.label} (${order.qrisProofFileName})'
                        : order.paymentMethod.label,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(height: 1),
                  ),
                  _ReceiptInfoRow(
                    label: 'Total Tagihan',
                    value: formatRupiah(order.price),
                    mono: true,
                    boldValue: true,
                    valueColor: ClearWashTheme.actionCobalt,
                  ),
                  if (order.paymentMethod == PaymentMethod.cash &&
                      order.cashTendered > 0) ...[
                    _ReceiptInfoRow(
                      label: 'Tunai Diterima',
                      value: formatRupiah(order.cashTendered),
                      mono: true,
                    ),
                    _ReceiptInfoRow(
                      label: 'Kembalian',
                      value: formatRupiah(order.changeAmount),
                      mono: true,
                      boldValue: true,
                      valueColor: ClearWashTheme.readyText,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => setState(
                      () => _showThermalPreview = !_showThermalPreview,
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      side: const BorderSide(color: ClearWashTheme.borderSlate),
                      foregroundColor: ClearWashTheme.slateInk,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: Icon(
                      _showThermalPreview
                          ? Icons.visibility_off_rounded
                          : Icons.receipt_long_rounded,
                      size: 18,
                    ),
                    label: Text(
                      _showThermalPreview ? 'Sembunyikan Struk' : 'Preview 58mm',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _copyToClipboard(
                      context: context,
                      text: thermalText,
                      snackbarMessage: 'Struk 32-kolom disalin ke clipboard.',
                      markCopied: () => setState(() => _copied = true),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      side: BorderSide(
                        color: _copied
                            ? ClearWashTheme.readyAccent
                            : ClearWashTheme.borderSlate,
                      ),
                      foregroundColor: _copied
                          ? ClearWashTheme.readyText
                          : ClearWashTheme.actionCobalt,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: Icon(
                      _copied ? Icons.check_rounded : Icons.copy_rounded,
                      size: 18,
                    ),
                    label: Text(
                      _copied ? 'Disalin' : 'Salin Struk',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_showThermalPreview) ...[
              const SizedBox(height: 12),
              _ThermalPreviewBox(content: thermalText),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 4,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onGoToQueue?.call();
                    },
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      side: const BorderSide(
                        color: ClearWashTheme.actionCobalt,
                        width: 1.4,
                      ),
                      foregroundColor: ClearWashTheme.actionCobalt,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.list_alt_rounded, size: 18),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Lihat Antrian',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 5,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      backgroundColor: ClearWashTheme.actionCobalt,
                    ),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Selesai & Registrasi Baru',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ShiftReceiptSheet extends StatefulWidget {
  const _ShiftReceiptSheet({
    required this.report,
    required this.receiptService,
  });

  final ShiftReport report;
  final ReceiptService receiptService;

  @override
  State<_ShiftReceiptSheet> createState() => _ShiftReceiptSheetState();
}

class _ShiftReceiptSheetState extends State<_ShiftReceiptSheet> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final shift = report.shift;
    final slipText = widget.receiptService.formatShiftClosingReceipt(report);
    final isBalanced = report.isCashBalanced;

    return Container(
      decoration: ClearWashTheme.sheetDecoration(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClearWashTheme.sheetGrabber(),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: ClearWashTheme.surfaceSubtle,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: ClearWashTheme.actionCobalt,
                    size: 25,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Rekapitulasi Tutup Shift',
                        style: TextStyle(
                          fontSize: 17.5,
                          fontWeight: FontWeight.w700,
                          color: ClearWashTheme.slateInk,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        '${shift.cashierName} • ${shift.terminalId}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: ClearWashTheme.slateMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isBalanced
                        ? ClearWashTheme.readyBg
                        : ClearWashTheme.errorBg,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    isBalanced ? 'MATCH' : 'SELISIH',
                    style: ClearWashTheme.monoStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: isBalanced
                          ? ClearWashTheme.readyText
                          : ClearWashTheme.errorRed,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: ClearWashTheme.cardDecoration(
                color: ClearWashTheme.canvas,
                radius: 16,
                elevated: false,
              ),
              child: Column(
                children: [
                  _ReceiptInfoRow(
                    label: 'Total Omzet Shift',
                    value: formatRupiah(report.totalRevenue),
                    mono: true,
                    boldValue: true,
                    valueColor: ClearWashTheme.actionCobalt,
                  ),
                  _ReceiptInfoRow(
                    label: 'Total Kendaraan',
                    value: '${report.totalVehicles} Unit',
                    mono: true,
                  ),
                  _ReceiptInfoRow(
                    label: 'Saldo Seharusnya',
                    value: formatRupiah(report.expectedCashInDrawer),
                    mono: true,
                  ),
                  _ReceiptInfoRow(
                    label: 'Fisik Laci Kas',
                    value: formatRupiah(shift.physicalCashCount),
                    mono: true,
                  ),
                  _ReceiptInfoRow(
                    label: 'Selisih Kas',
                    value: report.cashVariance > 0
                        ? '+${formatRupiah(report.cashVariance)}'
                        : formatRupiah(report.cashVariance),
                    mono: true,
                    boldValue: true,
                    valueColor: isBalanced
                        ? ClearWashTheme.readyText
                        : ClearWashTheme.errorRed,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _ThermalPreviewBox(content: slipText),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _copyToClipboard(
                      context: context,
                      text: slipText,
                      snackbarMessage:
                          'Rekapitulasi shift disalin ke clipboard.',
                      markCopied: () => setState(() => _copied = true),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      side: BorderSide(
                        color: _copied
                            ? ClearWashTheme.readyAccent
                            : ClearWashTheme.borderSlate,
                      ),
                      foregroundColor: _copied
                          ? ClearWashTheme.readyText
                          : ClearWashTheme.actionCobalt,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: Icon(
                      _copied ? Icons.check_rounded : Icons.copy_rounded,
                      size: 18,
                    ),
                    label: Text(
                      _copied ? 'Disalin' : 'Salin Struk',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      backgroundColor: ClearWashTheme.slateInk,
                    ),
                    child: const Text(
                      'Tutup',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptInfoRow extends StatelessWidget {
  const _ReceiptInfoRow({
    required this.label,
    required this.value,
    this.mono = false,
    this.boldValue = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool mono;
  final bool boldValue;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = valueColor ?? ClearWashTheme.slateInk;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: ClearWashTheme.slateMuted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: mono
                  ? ClearWashTheme.monoStyle(
                      fontSize: boldValue ? 14.5 : 13,
                      fontWeight: boldValue ? FontWeight.w800 : FontWeight.w700,
                      color: resolvedColor,
                    )
                  : TextStyle(
                      fontSize: 13,
                      fontWeight: boldValue ? FontWeight.w800 : FontWeight.w700,
                      color: resolvedColor,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThermalPreviewBox extends StatelessWidget {
  const _ThermalPreviewBox({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ClearWashTheme.canvas,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ClearWashTheme.borderHairline, width: 0.8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          content,
          style: ClearWashTheme.monoStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: ClearWashTheme.slateInk,
            height: 1.4,
            fixedWidth: true,
          ),
        ),
      ),
    );
  }
}
