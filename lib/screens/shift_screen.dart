import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../models/carwash_order.dart';
import '../models/shift_summary.dart';
import '../services/export_service.dart';
import '../theme/clearwash_theme.dart';
import '../widgets/receipt_modal.dart';

/// Tab 3 — Shift summary, revenue & volume analytics, cash drawer audit, and
/// shift closing reconciliation screen.
class ShiftScreen extends ConsumerStatefulWidget {
  const ShiftScreen({super.key});

  @override
  ConsumerState<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends ConsumerState<ShiftScreen> {
  late final TextEditingController _cashCountController;
  late final TextEditingController _notesController;
  String? _syncedShiftId;
  bool _isSavingAudit = false;
  bool _isClosingShift = false;
  bool _isReopeningShift = false;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    final initialReport = ref.read(shiftReportProvider).value;
    if (initialReport != null) {
      _syncedShiftId = initialReport.shift.id;
      _cashCountController = TextEditingController(
        text: '${initialReport.shift.physicalCashCount}',
      );
      _notesController = TextEditingController(
        text: initialReport.shift.supervisorNotes,
      );
    } else {
      _cashCountController = TextEditingController();
      _notesController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _cashCountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _syncControllersFromShift(ShiftSession shift) {
    if (_syncedShiftId == shift.id) {
      return;
    }
    _syncedShiftId = shift.id;
    final cashText = '${shift.physicalCashCount}';
    _cashCountController.value = TextEditingValue(
      text: cashText,
      selection: TextSelection.collapsed(offset: cashText.length),
    );
    _notesController.value = TextEditingValue(
      text: shift.supervisorNotes,
      selection: TextSelection.collapsed(offset: shift.supervisorNotes.length),
    );
  }

  int get _liveCashCount => int.tryParse(_cashCountController.text.trim()) ?? 0;

  Future<void> _saveAudit() async {
    if (_isSavingAudit) {
      return;
    }
    setState(() => _isSavingAudit = true);
    try {
      await ref.read(carwashRepositoryProvider).updateShiftAudit(
        physicalCashCount: _liveCashCount,
        supervisorNotes: _notesController.text,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Audit fisik uang tunai berhasil disimpan.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan audit: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingAudit = false);
      }
    }
  }

  Future<void> _closeShift(ShiftReport report) async {
    if (_isClosingShift) {
      return;
    }
    final liveCash = _liveCashCount;
    final variance = liveCash - report.expectedCashInDrawer;
    final varianceText = variance == 0
        ? 'MATCH (Rp 0)'
        : '${variance > 0 ? '+' : ''}${formatRupiah(variance)}';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Tutup Shift & Cetak Rekap?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total Omzet: ${formatRupiah(report.totalRevenue)}'),
            const SizedBox(height: 4),
            Text(
              'Saldo Seharusnya: ${formatRupiah(report.expectedCashInDrawer)}',
            ),
            Text('Fisik Laci: ${formatRupiah(liveCash)}'),
            Text('Selisih: $varianceText'),
            const SizedBox(height: 10),
            const Text(
              'Setelah shift ditutup, kasir tidak dapat menerima order baru sebelum membuka shift baru.',
              style: TextStyle(fontSize: 12.5, color: ClearWashTheme.slateMuted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: ClearWashTheme.slateInk,
            ),
            child: const Text('Ya, Tutup Shift'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isClosingShift = true);
    try {
      await ref.read(carwashRepositoryProvider).closeShift(
        physicalCashCount: liveCash,
        supervisorNotes: _notesController.text,
      );
      if (!mounted) {
        return;
      }

      final orders = ref.read(todayOrdersProvider).value ?? const <CarwashOrder>[];
      final closedShift = report.shift.copyWith(
        physicalCashCount: liveCash,
        supervisorNotes: _notesController.text.trim(),
        closedAt: DateTime.now(),
        status: ShiftStatus.closed,
      );
      final closedReport = ShiftReport.fromOrders(
        shift: closedShift,
        orders: orders,
      );

      await showShiftReceiptModal(
        context,
        closedReport,
        receiptService: ref.read(receiptServiceProvider),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menutup shift: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isClosingShift = false);
      }
    }
  }

  Future<void> _reopenDemoShift() async {
    if (_isReopeningShift) {
      return;
    }
    setState(() => _isReopeningShift = true);
    try {
      await ref.read(carwashRepositoryProvider).reopenDemoShift();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Shift baru (demo) dibuka dan siap digunakan.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuka shift baru: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isReopeningShift = false);
      }
    }
  }

  Future<void> _exportCsv(ShiftReport report) async {
    if (_isExporting) {
      return;
    }
    setState(() => _isExporting = true);
    try {
      final orders =
          ref.read(todayOrdersProvider).value ?? const <CarwashOrder>[];
      final result = await ref.read(exportServiceProvider).exportShiftReportCsv(
        report: report,
        orders: orders,
      );
      if (!mounted) {
        return;
      }
      setState(() => _isExporting = false);
      await _showExportResultDialog(result);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengekspor laporan CSV: $error')),
      );
    } finally {
      if (mounted && _isExporting) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _showExportResultDialog(ExportResult result) {
    var copied = false;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (builderContext, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
          contentPadding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
          actionsPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: ClearWashTheme.readyBg,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.table_chart_rounded,
                  color: ClearWashTheme.readyText,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Export Laporan Excel / CSV',
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: ClearWashTheme.slateInk,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: ClearWashTheme.surfaceSubtle,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: ClearWashTheme.borderSlate),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ExportMetaRow(
                          label: 'Nama File',
                          value: result.fileName,
                        ),
                        const SizedBox(height: 6),
                        _ExportMetaRow(
                          label: 'Jumlah Transaksi',
                          value: '${result.rowCount} transaksi',
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Lokasi File',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: ClearWashTheme.slateMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        SelectableText(
                          result.filePath,
                          style: ClearWashTheme.monoStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: ClearWashTheme.slateInk,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: ClearWashTheme.readyBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: ClearWashTheme.readyAccent.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline_rounded,
                                size: 15,
                                color: ClearWashTheme.readyText,
                              ),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'UTF-8 BOM Excel-ready (siap dibuka langsung di Microsoft Excel)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: ClearWashTheme.readyText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'PREVIEW CSV',
                    style: ClearWashTheme.sectionLabelStyle(fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: ClearWashTheme.canvas,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: ClearWashTheme.borderHairline,
                        width: 0.8,
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SelectableText(
                          result.csvContent,
                          style: ClearWashTheme.monoStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: ClearWashTheme.slateInk,
                            height: 1.35,
                            fixedWidth: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: result.csvContent),
                      );
                      if (!dialogContext.mounted) {
                        return;
                      }
                      setDialogState(() => copied = true);
                      if (!mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Isi CSV berhasil disalin ke clipboard.',
                          ),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      side: BorderSide(
                        color: copied
                            ? ClearWashTheme.readyAccent
                            : ClearWashTheme.actionCobalt,
                        width: 1.3,
                      ),
                      foregroundColor: copied
                          ? ClearWashTheme.readyText
                          : ClearWashTheme.actionCobalt,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: Icon(
                      copied ? Icons.check_rounded : Icons.copy_rounded,
                      size: 17,
                    ),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        copied ? 'CSV Disalin' : 'Salin CSV',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      backgroundColor: ClearWashTheme.slateInk,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
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

  @override
  Widget build(BuildContext context) {
    final reportAsync = ref.watch(shiftReportProvider);

    return ColoredBox(
      color: ClearWashTheme.canvas,
      child: reportAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Gagal memuat ringkasan shift: $error',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: ClearWashTheme.errorRed,
              ),
            ),
          ),
        ),
        data: (report) {
          _syncControllersFromShift(report.shift);
          final shift = report.shift;
          final liveCash = _liveCashCount;
          final liveVariance = liveCash - report.expectedCashInDrawer;
          final isMatch = liveVariance == 0;

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Operator Context Banner
                _OperatorContextBanner(shift: shift),
                const SizedBox(height: 14),

                // 2. Hero Revenue Card & Export Action
                _HeroRevenueCard(
                  report: report,
                  isExporting: _isExporting,
                  onExportCsv: () => _exportCsv(report),
                ),
                const SizedBox(height: 14),

                // 3. Vehicle Volume Card
                _VehicleVolumeCard(report: report),
                const SizedBox(height: 14),

                // 4. Top Services List
                _TopServicesCard(breakdowns: report.serviceBreakdowns),
                const SizedBox(height: 14),

                // 5. Cash Drawer Physical Audit & Shift Close
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: ClearWashTheme.cardDecoration(radius: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.point_of_sale_rounded,
                            size: 20,
                            color: ClearWashTheme.actionCobalt,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Audit Fisik Uang Tunai',
                              style: ClearWashTheme.headingStyle(fontSize: 15.5),
                            ),
                          ),
                          _VarianceBadge(
                            isMatch: isMatch,
                            variance: liveVariance,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: ClearWashTheme.canvas,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            _DrawerSummaryRow(
                              label: 'Modal Awal Laci',
                              value: formatRupiah(shift.openingCash),
                            ),
                            _DrawerSummaryRow(
                              label: 'Penjualan Tunai (${report.cashCount})',
                              value: formatRupiah(report.cashRevenue),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Divider(height: 1),
                            ),
                            _DrawerSummaryRow(
                              label: 'Saldo Seharusnya',
                              value: formatRupiah(report.expectedCashInDrawer),
                              emphasize: true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'HITUNGAN UANG FISIK',
                              style: ClearWashTheme.sectionLabelStyle(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: shift.isOpen
                                ? () {
                                    final expectedText =
                                        '${report.expectedCashInDrawer}';
                                    _cashCountController.value =
                                        TextEditingValue(
                                          text: expectedText,
                                          selection: TextSelection.collapsed(
                                            offset: expectedText.length,
                                          ),
                                        );
                                    setState(() {});
                                  }
                                : null,
                            style: TextButton.styleFrom(
                              minimumSize: const Size(0, 40),
                              foregroundColor: ClearWashTheme.actionCobalt,
                            ),
                            icon: const Icon(Icons.sync_alt_rounded, size: 17),
                            label: const Text(
                              'Samakan Saldo',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _cashCountController,
                        enabled: shift.isOpen,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        style: ClearWashTheme.monoStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                        decoration: const InputDecoration(
                          prefixText: 'Rp ',
                          hintText: '0',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'CATATAN SUPERVISOR',
                        style: ClearWashTheme.sectionLabelStyle(),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _notesController,
                        enabled: shift.isOpen,
                        maxLines: 2,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText:
                              'Opsional: keterangan selisih kas atau serah terima shift...',
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (shift.isOpen) ...[
                        OutlinedButton.icon(
                          onPressed: _isSavingAudit ? null : _saveAudit,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            side: const BorderSide(
                              color: ClearWashTheme.actionCobalt,
                              width: 1.4,
                            ),
                            foregroundColor: ClearWashTheme.actionCobalt,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: _isSavingAudit
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined, size: 20),
                          label: Text(
                            _isSavingAudit ? 'Menyimpan...' : 'Simpan Audit',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: _isClosingShift
                              ? null
                              : () => _closeShift(report),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(54),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            backgroundColor: ClearWashTheme.slateInk,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: _isClosingShift
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.print_rounded),
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _isClosingShift
                                  ? 'Menutup Shift...'
                                  : 'TUTUP SHIFT & CETAK REKAPITULASI',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ] else ...[
                        OutlinedButton.icon(
                          onPressed: () => showShiftReceiptModal(
                            context,
                            report,
                            receiptService: ref.read(receiptServiceProvider),
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            side: const BorderSide(
                              color: ClearWashTheme.borderSlate,
                            ),
                            foregroundColor: ClearWashTheme.slateInk,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.receipt_long_rounded),
                          label: const Text(
                            'Lihat Rekapitulasi Tutup Shift',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed:
                              _isReopeningShift ? null : _reopenDemoShift,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(54),
                            backgroundColor: ClearWashTheme.actionCobalt,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: _isReopeningShift
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.lock_open_rounded),
                          label: Text(
                            _isReopeningShift
                                ? 'Membuka Shift Baru...'
                                : 'BUKA SHIFT BARU (DEMO)',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OperatorContextBanner extends StatelessWidget {
  const _OperatorContextBanner({required this.shift});

  final ShiftSession shift;

  @override
  Widget build(BuildContext context) {
    final isOpen = shift.isOpen;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ClearWashTheme.cardDecoration(radius: 18),
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
                      shift.cashierName,
                      style: const TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        color: ClearWashTheme.slateInk,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      shift.shiftLabel,
                      style: const TextStyle(
                        fontSize: 13,
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
                  color: isOpen
                      ? ClearWashTheme.readyBg
                      : ClearWashTheme.waitingBg,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  shift.status.label,
                  style: ClearWashTheme.monoStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isOpen
                        ? ClearWashTheme.readyText
                        : ClearWashTheme.waitingText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _ContextChip(
                icon: Icons.devices_rounded,
                label: shift.terminalId,
              ),
              _ContextChip(
                icon: Icons.access_time_rounded,
                label: 'Buka ${formatClock(shift.openedAt)} WIB',
              ),
              if (shift.closedAt != null)
                _ContextChip(
                  icon: Icons.lock_clock_rounded,
                  label: 'Tutup ${formatClock(shift.closedAt!)} WIB',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContextChip extends StatelessWidget {
  const _ContextChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: ClearWashTheme.canvas,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: ClearWashTheme.actionCobalt),
          const SizedBox(width: 5),
          Text(
            label,
            style: ClearWashTheme.monoStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ClearWashTheme.slateMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroRevenueCard extends StatelessWidget {
  const _HeroRevenueCard({
    required this.report,
    required this.isExporting,
    required this.onExportCsv,
  });

  final ShiftReport report;
  final bool isExporting;
  final VoidCallback onExportCsv;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ClearWashTheme.brightCobalt, Color(0xFF0055D4)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: ClearWashTheme.actionCobalt.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Text(
                'TOTAL PENDAPATAN SHIFT',
                style: ClearWashTheme.sectionLabelStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '${report.cashCount + report.qrisCount} Lunas',
                  style: ClearWashTheme.monoStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatRupiah(report.totalRevenue),
              style: ClearWashTheme.monoStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.6,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _RevenueChannelCard(
                  title: 'Tunai',
                  amount: formatRupiah(report.cashRevenue),
                  countLabel: '${report.cashCount} transaksi',
                  icon: Icons.payments_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RevenueChannelCard(
                  title: 'QRIS',
                  amount: formatRupiah(report.qrisRevenue),
                  countLabel: '${report.qrisCount} transaksi',
                  icon: Icons.qr_code_2_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: isExporting ? null : onExportCsv,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: Colors.white,
              foregroundColor: ClearWashTheme.actionCobalt,
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.75),
              disabledForegroundColor: ClearWashTheme.actionCobalt,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: isExporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: ClearWashTheme.actionCobalt,
                    ),
                  )
                : const Icon(Icons.table_view_rounded, size: 20),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                isExporting ? 'Mengekspor CSV...' : 'Export CSV / Excel',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportMetaRow extends StatelessWidget {
  const _ExportMetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
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
            style: ClearWashTheme.monoStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: ClearWashTheme.slateInk,
            ),
          ),
        ),
      ],
    );
  }
}

class _RevenueChannelCard extends StatelessWidget {
  const _RevenueChannelCard({
    required this.title,
    required this.amount,
    required this.countLabel,
    required this.icon,
  });

  final String title;
  final String amount;
  final String countLabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.24),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.9)),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              amount,
              style: ClearWashTheme.monoStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            countLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleVolumeCard extends StatelessWidget {
  const _VehicleVolumeCard({required this.report});

  final ShiftReport report;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ClearWashTheme.cardDecoration(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TOTAL KENDARAAN SELESAI',
                      style: ClearWashTheme.sectionLabelStyle(),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${report.totalVehicles} Unit',
                      style: ClearWashTheme.monoStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: ClearWashTheme.surfaceSubtle,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Rata-rata Cuci',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: ClearWashTheme.slateMuted,
                      ),
                    ),
                    Text(
                      '${report.averageWashMinutes} mnt',
                      style: ClearWashTheme.monoStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: ClearWashTheme.actionCobalt,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _VehicleBreakdownBox(
            icon: Icons.directions_car_rounded,
            title: 'Mobil Dicuci',
            totalCount: report.carCount,
            smallCount: report.carSmallCount,
            mediumCount: report.carMediumCount,
            largeCount: report.carLargeCount,
          ),
          const SizedBox(height: 10),
          _VehicleBreakdownBox(
            icon: Icons.two_wheeler_rounded,
            title: 'Motor Dicuci',
            totalCount: report.motorCount,
            smallCount: report.motorSmallCount,
            mediumCount: report.motorMediumCount,
            largeCount: report.motorLargeCount,
          ),
        ],
      ),
    );
  }
}

class _VehicleBreakdownBox extends StatelessWidget {
  const _VehicleBreakdownBox({
    required this.icon,
    required this.title,
    required this.totalCount,
    required this.smallCount,
    required this.mediumCount,
    required this.largeCount,
  });

  final IconData icon;
  final String title;
  final int totalCount;
  final int smallCount;
  final int mediumCount;
  final int largeCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ClearWashTheme.canvas,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: ClearWashTheme.actionCobalt),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: ClearWashTheme.slateInk,
                  ),
                ),
              ),
              Text(
                '$totalCount Unit',
                style: ClearWashTheme.monoStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: ClearWashTheme.actionCobalt,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _TierChip(label: 'Kecil', count: smallCount)),
              const SizedBox(width: 6),
              Expanded(child: _TierChip(label: 'Sedang', count: mediumCount)),
              const SizedBox(width: 6),
              Expanded(child: _TierChip(label: 'Besar', count: largeCount)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TierChip extends StatelessWidget {
  const _TierChip({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: ClearWashTheme.surfaceCard,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: ClearWashTheme.borderHairline),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: ClearWashTheme.slateMuted,
            ),
          ),
          Text(
            '$count',
            style: ClearWashTheme.monoStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopServicesCard extends StatelessWidget {
  const _TopServicesCard({required this.breakdowns});

  final List<ServiceBreakdownItem> breakdowns;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ClearWashTheme.cardDecoration(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'LAYANAN TERLARIS',
            style: ClearWashTheme.sectionLabelStyle(),
          ),
          const SizedBox(height: 12),
          if (breakdowns.isEmpty)
            const Text(
              'Belum ada transaksi lunas pada shift ini.',
              style: TextStyle(
                fontSize: 13,
                color: ClearWashTheme.slateMuted,
              ),
            )
          else
            ...breakdowns.map((item) {
              final fraction = (item.percentage / 100.0).clamp(0.0, 1.0);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${item.packageName} (${item.count}x)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: ClearWashTheme.slateInk,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatRupiah(item.totalRevenue),
                          style: ClearWashTheme.monoStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${item.percentage.toStringAsFixed(0)}%',
                          style: ClearWashTheme.monoStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: ClearWashTheme.actionCobalt,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 7,
                        backgroundColor: ClearWashTheme.canvas,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          ClearWashTheme.actionCobalt,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _DrawerSummaryRow extends StatelessWidget {
  const _DrawerSummaryRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: emphasize ? 13 : 12.5,
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
                color: emphasize
                    ? ClearWashTheme.slateInk
                    : ClearWashTheme.slateMuted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: ClearWashTheme.monoStyle(
              fontSize: emphasize ? 14.5 : 13,
              fontWeight: FontWeight.w800,
              color: emphasize
                  ? ClearWashTheme.actionCobalt
                  : ClearWashTheme.slateInk,
            ),
          ),
        ],
      ),
    );
  }
}

class _VarianceBadge extends StatelessWidget {
  const _VarianceBadge({
    required this.isMatch,
    required this.variance,
  });

  final bool isMatch;
  final int variance;

  @override
  Widget build(BuildContext context) {
    final prefix = variance > 0 ? '+' : '';
    final label = isMatch
        ? 'MATCH (Rp 0)'
        : 'SELISIH $prefix${formatRupiah(variance)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isMatch ? ClearWashTheme.readyBg : ClearWashTheme.errorBg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: ClearWashTheme.monoStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: isMatch ? ClearWashTheme.readyText : ClearWashTheme.errorRed,
        ),
      ),
    );
  }
}
