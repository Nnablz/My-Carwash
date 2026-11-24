import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../models/carwash_order.dart';
import '../theme/clearwash_theme.dart';
import '../widgets/license_plate_badge.dart';
import '../widgets/payment_modal.dart';
import '../widgets/receipt_modal.dart';

/// Tab 1 — Vehicle intake & instant registration POS terminal screen.
class KasirScreen extends ConsumerStatefulWidget {
  const KasirScreen({super.key});

  @override
  ConsumerState<KasirScreen> createState() => _KasirScreenState();
}

class _KasirScreenState extends ConsumerState<KasirScreen> {
  late final TextEditingController _modelController;
  late final TextEditingController _plateController;
  String? _localValidationError;
  bool _showFieldErrors = false;
  bool _isReopeningShift = false;

  @override
  void initState() {
    super.initState();
    final initial = ref.read(posRegistrationProvider);
    _modelController = TextEditingController(
      text: initial.isCustomSeries ? initial.modelName : '',
    );
    _plateController = TextEditingController(text: initial.licensePlate);
  }

  @override
  void dispose() {
    _modelController.dispose();
    _plateController.dispose();
    super.dispose();
  }

  Future<void> _handleReopenShift() async {
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
          content: Text('Shift baru berhasil dibuka dan siap menerima transaksi.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuka shift: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isReopeningShift = false);
      }
    }
  }

  Future<void> _pickCustomTime(TimeOfDay currentCustomTime) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: currentCustomTime,
      helpText: 'Pilih Jam Siap Ambil',
      cancelText: 'Batal',
      confirmText: 'Pilih',
    );
    if (!mounted || picked == null) {
      return;
    }
    ref.read(posRegistrationProvider.notifier).setCustomTime(picked);
  }

  Future<void> _handleOpenPayment() async {
    final regState = ref.read(posRegistrationProvider);
    final cleanBrand = regState.selectedBrand.trim();
    final cleanModel = regState.modelName.trim();
    final cleanPlate = regState.licensePlate.trim();

    ref.read(posRegistrationProvider.notifier).clearError();

    if (cleanBrand.isEmpty || cleanModel.isEmpty || cleanPlate.isEmpty) {
      final missingMsg = cleanModel.isEmpty && cleanPlate.isEmpty
          ? 'Lengkapi Seri / Model dan Plat Nomor kendaraan terlebih dahulu.'
          : cleanModel.isEmpty
          ? 'Seri / Model kendaraan wajib diisi (contoh: Avanza, Brio, NMAX).'
          : cleanPlate.isEmpty
          ? 'Plat nomor kendaraan wajib diisi (contoh: B1234ABC).'
          : 'Merek kendaraan wajib dipilih.';
      setState(() {
        _showFieldErrors = true;
        _localValidationError = missingMsg;
      });
      return;
    }

    setState(() {
      _showFieldErrors = false;
      _localValidationError = null;
    });

    final order = await showPaymentModal(context, ref);
    if (!mounted || order == null) {
      return;
    }

    setState(() {
      _showFieldErrors = false;
      _localValidationError = null;
    });

    final receiptService = ref.read(receiptServiceProvider);
    await showReceiptModal(
      context,
      order,
      receiptService: receiptService,
      onGoToQueue: () =>
          ref.read(activeTabIndexProvider.notifier).goToAntrian(),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PosRegistrationState>(posRegistrationProvider, (previous, next) {
      final expectedCustomModel = next.isCustomSeries ? next.modelName : '';
      if (_modelController.text != expectedCustomModel) {
        _modelController.value = TextEditingValue(
          text: expectedCustomModel,
          selection: TextSelection.collapsed(
            offset: expectedCustomModel.length,
          ),
        );
      }
      if (_plateController.text != next.licensePlate) {
        _plateController.value = TextEditingValue(
          text: next.licensePlate,
          selection: TextSelection.collapsed(offset: next.licensePlate.length),
        );
      }
    });

    final regState = ref.watch(posRegistrationProvider);
    final shiftAsync = ref.watch(activeShiftProvider);
    final isShiftClosed = shiftAsync.value?.isOpen == false;

    final brands = regState.availableBrands;
    final effectiveBrand = brands.contains(regState.selectedBrand)
        ? regState.selectedBrand
        : (brands.isNotEmpty ? brands.first : 'Lainnya');
    final seriesList = regState.availableSeries.toSet().toList(growable: false);
    final effectiveSeries = seriesList.contains(regState.selectedSeries)
        ? regState.selectedSeries
        : (seriesList.isNotEmpty ? seriesList.first : 'Lainnya');

    final selectedPkg = regState.selectedPackage;
    final activeError = _localValidationError ?? regState.errorMessage;
    final hasPlate = regState.licensePlate.trim().isNotEmpty;

    return ColoredBox(
      color: ClearWashTheme.canvas,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isShiftClosed) ...[
                    _ClosedShiftBanner(
                      isLoading: _isReopeningShift,
                      onReopen: _handleReopenShift,
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Section 1: Tipe Kendaraan
                  const _SectionHeader(
                    number: '01',
                    title: 'Tipe Kendaraan',
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _VehicleTypeCard(
                          icon: Icons.directions_car_rounded,
                          title: 'Mobil',
                          priceHint: 'Mulai Rp 50.000',
                          selected: regState.vehicleType == VehicleType.mobil,
                          onTap: () => ref
                              .read(posRegistrationProvider.notifier)
                              .selectVehicleType(VehicleType.mobil),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _VehicleTypeCard(
                          icon: Icons.two_wheeler_rounded,
                          title: 'Motor',
                          priceHint: 'Mulai Rp 20.000',
                          selected: regState.vehicleType == VehicleType.motor,
                          onTap: () => ref
                              .read(posRegistrationProvider.notifier)
                              .selectVehicleType(VehicleType.motor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Section 2: Merek & Model
                  const _SectionHeader(
                    number: '02',
                    title: 'Merek & Model',
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: ClearWashTheme.cardDecoration(radius: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<String>(
                          key: ValueKey(
                            'brand_${regState.vehicleType.name}_$effectiveBrand',
                          ),
                          initialValue: effectiveBrand,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Merek Kendaraan',
                            prefixIcon: Icon(Icons.branding_watermark_outlined),
                          ),
                          items: brands
                              .map(
                                (brand) => DropdownMenuItem<String>(
                                  value: brand,
                                  child: Text(
                                    brand,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: ClearWashTheme.slateInk,
                                    ),
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            ref
                                .read(posRegistrationProvider.notifier)
                                .setBrand(value);
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          key: ValueKey(
                            'series_${regState.vehicleType.name}_${effectiveBrand}_$effectiveSeries',
                          ),
                          initialValue: effectiveSeries,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Seri / Model',
                            prefixIcon: Icon(
                              Icons.directions_car_filled_outlined,
                            ),
                          ),
                          items: seriesList
                              .map(
                                (series) => DropdownMenuItem<String>(
                                  value: series,
                                  child: Text(
                                    series,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: ClearWashTheme.slateInk,
                                    ),
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            ref
                                .read(posRegistrationProvider.notifier)
                                .setSeries(value);
                            if (_localValidationError != null) {
                              setState(() => _localValidationError = null);
                            }
                          },
                        ),
                        if (regState.isCustomSeries) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _modelController,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              labelText: 'Seri / Model Lainnya',
                              hintText: regState.vehicleType == VehicleType.mobil
                                  ? 'Contoh: Avanza Veloz, Brio RS'
                                  : 'Contoh: NMAX, Vario 160, Vespa',
                              prefixIcon: const Icon(Icons.edit_note_rounded),
                              errorText: _showFieldErrors &&
                                      regState.modelName.trim().isEmpty
                                  ? 'Model kendaraan wajib diisi'
                                  : null,
                              suffixIcon: regState.modelName.isNotEmpty
                                  ? IconButton(
                                      tooltip: 'Hapus model',
                                      onPressed: () {
                                        _modelController.clear();
                                        ref
                                            .read(
                                              posRegistrationProvider.notifier,
                                            )
                                            .setModelName('');
                                        setState(
                                          () => _localValidationError = null,
                                        );
                                      },
                                      icon: const Icon(Icons.clear_rounded),
                                    )
                                  : null,
                            ),
                            onChanged: (value) {
                              ref
                                  .read(posRegistrationProvider.notifier)
                                  .setModelName(value);
                              if (_localValidationError != null) {
                                setState(() => _localValidationError = null);
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Section 3: Plat Nomor
                  const _SectionHeader(
                    number: '03',
                    title: 'Plat Nomor',
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: ClearWashTheme.cardDecoration(radius: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _plateController,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [
                            FilteringTextInputFormatter.deny(RegExp(r'\s')),
                            TextInputFormatter.withFunction(
                              (oldValue, newValue) => newValue.copyWith(
                                text: newValue.text.toUpperCase(),
                              ),
                            ),
                            LengthLimitingTextInputFormatter(14),
                          ],
                          style: ClearWashTheme.monoStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Nomor Polisi',
                            hintText: 'Contoh: B1234ABC',
                            prefixIcon: const Icon(Icons.badge_outlined),
                            errorText: _showFieldErrors &&
                                    regState.licensePlate.trim().isEmpty
                                ? 'Plat nomor wajib diisi'
                                : null,
                            suffixIcon: regState.licensePlate.isNotEmpty
                                ? IconButton(
                                    tooltip: 'Hapus plat',
                                    onPressed: () {
                                      _plateController.clear();
                                      ref
                                          .read(posRegistrationProvider.notifier)
                                          .setLicensePlate('');
                                      setState(() => _localValidationError = null);
                                    },
                                    icon: const Icon(Icons.clear_rounded),
                                  )
                                : null,
                          ),
                          onChanged: (value) {
                            ref
                                .read(posRegistrationProvider.notifier)
                                .setLicensePlate(value);
                            if (_localValidationError != null) {
                              setState(() => _localValidationError = null);
                            }
                          },
                        ),
                        if (hasPlate) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Text(
                                'PREVIEW PLAT:',
                                style: ClearWashTheme.sectionLabelStyle(
                                  fontSize: 10.5,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: LicensePlateBadge(
                                  plate: regState.licensePlate,
                                  vehicleType: regState.vehicleType,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Section 4: Ukuran & Paket Kendaraan
                  const _SectionHeader(
                    number: '04',
                    title: 'Ukuran & Paket Kendaraan',
                  ),
                  const SizedBox(height: 8),
                  ...regState.availablePackages.map((pkg) {
                    final selected = regState.selectedSize == pkg.size;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PackageOptionCard(
                        package: pkg,
                        selected: selected,
                        onTap: () => ref
                            .read(posRegistrationProvider.notifier)
                            .selectSize(pkg.size),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),

                  // Section 5: Waktu Pengambilan (Siap Ambil)
                  Row(
                    children: [
                      const Expanded(
                        child: _SectionHeader(
                          number: '05',
                          title: 'Waktu Pengambilan (Siap Ambil)',
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: ClearWashTheme.surfaceSubtle,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: ClearWashTheme.actionCobalt.withValues(
                              alpha: 0.25,
                            ),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          regState.pickupDisplayText,
                          style: ClearWashTheme.monoStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: ClearWashTheme.actionCobalt,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: ClearWashTheme.cardDecoration(radius: 16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _PickupChip(
                          label: PickupPreset.oneHour.label,
                          selected:
                              regState.pickupPreset == PickupPreset.oneHour,
                          onTap: () => ref
                              .read(posRegistrationProvider.notifier)
                              .selectPickupPreset(PickupPreset.oneHour),
                        ),
                        _PickupChip(
                          label: PickupPreset.afternoon.label,
                          selected:
                              regState.pickupPreset == PickupPreset.afternoon,
                          onTap: () => ref
                              .read(posRegistrationProvider.notifier)
                              .selectPickupPreset(PickupPreset.afternoon),
                        ),
                        _PickupChip(
                          label: PickupPreset.evening.label,
                          selected:
                              regState.pickupPreset == PickupPreset.evening,
                          onTap: () => ref
                              .read(posRegistrationProvider.notifier)
                              .selectPickupPreset(PickupPreset.evening),
                        ),
                        _PickupChip(
                          label: PickupPreset.queue.label,
                          selected: regState.pickupPreset == PickupPreset.queue,
                          onTap: () => ref
                              .read(posRegistrationProvider.notifier)
                              .selectPickupPreset(PickupPreset.queue),
                        ),
                        _PickupChip(
                          label: regState.pickupPreset == PickupPreset.custom
                              ? 'Jam Khusus (${_formatTimeOfDay(regState.customTime)})'
                              : PickupPreset.custom.label,
                          icon: Icons.schedule_rounded,
                          selected:
                              regState.pickupPreset == PickupPreset.custom,
                          onTap: () => _pickCustomTime(regState.customTime),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Persistent bottom CTA & inline validation bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              color: ClearWashTheme.surfaceCard,
              border: Border(
                top: BorderSide(
                  color: ClearWashTheme.borderHairline,
                  width: 0.8,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x0A0F172A),
                  blurRadius: 16,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (activeError != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: ClearWashTheme.errorBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: ClearWashTheme.errorBorder),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 18,
                          color: ClearWashTheme.errorRed,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            activeError,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: ClearWashTheme.errorRed,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${selectedPkg.name} • ±${selectedPkg.estimatedMinutes} mnt',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: ClearWashTheme.slateMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatRupiah(selectedPkg.price),
                      style: ClearWashTheme.monoStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: ClearWashTheme.actionCobalt,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: (isShiftClosed || regState.isSubmitting)
                      ? null
                      : _handleOpenPayment,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: ClearWashTheme.actionCobalt,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Flexible(
                        child: Text(
                          'Pilih Metode Pembayaran',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatRupiah(selectedPkg.price),
                            style: ClearWashTheme.monoStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_forward_rounded, size: 20),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

class _ClosedShiftBanner extends StatelessWidget {
  const _ClosedShiftBanner({
    required this.isLoading,
    required this.onReopen,
  });

  final bool isLoading;
  final VoidCallback onReopen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: ClearWashTheme.cardDecoration(
        color: ClearWashTheme.waitingBg,
        borderColor: ClearWashTheme.waitingAccent.withValues(alpha: 0.4),
        radius: 18,
        elevated: false,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(
                Icons.lock_clock_rounded,
                color: ClearWashTheme.waitingText,
                size: 22,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Shift Kasir Sudah Ditutup',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: ClearWashTheme.waitingText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Terminal kasir terkunci karena shift aktif telah ditutup. Buka shift baru untuk mulai mencatat transaksi kendaraan.',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: ClearWashTheme.slateInk,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: isLoading ? null : onReopen,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: ClearWashTheme.slateInk,
            ),
            icon: isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.lock_open_rounded),
            label: Text(
              isLoading ? 'Membuka Shift...' : 'Buka Shift Baru',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.number, required this.title});

  final String number;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: ClearWashTheme.actionCobalt.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            number,
            style: ClearWashTheme.monoStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: ClearWashTheme.actionCobalt,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            title,
            style: ClearWashTheme.headingStyle(fontSize: 15),
          ),
        ),
      ],
    );
  }
}

class _VehicleTypeCard extends StatelessWidget {
  const _VehicleTypeCard({
    required this.icon,
    required this.title,
    required this.priceHint,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String priceHint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: ClearWashTheme.motionDuration,
        curve: ClearWashTheme.motionCurve,
        constraints: const BoxConstraints(minHeight: 102),
        padding: const EdgeInsets.all(14),
        decoration: ClearWashTheme.cardDecoration(
          color: selected
              ? ClearWashTheme.surfaceSubtle
              : ClearWashTheme.surfaceCard,
          borderColor: selected
              ? ClearWashTheme.actionCobalt
              : ClearWashTheme.borderHairline,
          borderWidth: selected ? 1.6 : 0.8,
          radius: 18,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                AnimatedContainer(
                  duration: ClearWashTheme.motionDuration,
                  curve: ClearWashTheme.motionCurve,
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: selected
                        ? ClearWashTheme.actionCobalt
                        : ClearWashTheme.canvas,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    size: 23,
                    color: selected
                        ? Colors.white
                        : ClearWashTheme.actionCobalt,
                  ),
                ),
                AnimatedOpacity(
                  duration: ClearWashTheme.motionDuration,
                  opacity: selected ? 1 : 0,
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: ClearWashTheme.actionCobalt,
                    size: 22,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: selected
                    ? ClearWashTheme.actionCobalt
                    : ClearWashTheme.slateInk,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              priceHint,
              style: ClearWashTheme.monoStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: ClearWashTheme.slateMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PackageOptionCard extends StatelessWidget {
  const _PackageOptionCard({
    required this.package,
    required this.selected,
    required this.onTap,
  });

  final WashPackage package;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: ClearWashTheme.motionDuration,
        curve: ClearWashTheme.motionCurve,
        constraints: const BoxConstraints(minHeight: 74),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: ClearWashTheme.cardDecoration(
          color: selected
              ? ClearWashTheme.surfaceSubtle
              : ClearWashTheme.surfaceCard,
          borderColor: selected
              ? ClearWashTheme.actionCobalt
              : ClearWashTheme.borderHairline,
          borderWidth: selected ? 1.6 : 0.8,
          radius: 16,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: ClearWashTheme.motionDuration,
              curve: ClearWashTheme.motionCurve,
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? ClearWashTheme.actionCobalt : Colors.white,
                border: Border.all(
                  color: selected
                      ? ClearWashTheme.actionCobalt
                      : ClearWashTheme.borderSlate,
                  width: 1.8,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          package.name,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? ClearWashTheme.actionCobalt
                                : ClearWashTheme.slateInk,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? Colors.white
                              : ClearWashTheme.canvas,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '±${package.estimatedMinutes} mnt',
                          style: ClearWashTheme.monoStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: ClearWashTheme.slateMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    package.description,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: ClearWashTheme.slateMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              formatRupiah(package.price),
              style: ClearWashTheme.monoStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: selected
                    ? ClearWashTheme.actionCobalt
                    : ClearWashTheme.slateInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickupChip extends StatelessWidget {
  const _PickupChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      labelPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      shape: const StadiumBorder(),
      selectedColor: ClearWashTheme.actionCobalt,
      backgroundColor: ClearWashTheme.canvas,
      side: BorderSide(
        color: selected
            ? ClearWashTheme.actionCobalt
            : ClearWashTheme.borderHairline,
        width: 0.9,
      ),
      avatar: icon != null
          ? Icon(
              icon,
              size: 16,
              color: selected ? Colors.white : ClearWashTheme.actionCobalt,
            )
          : null,
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : ClearWashTheme.slateInk,
        ),
      ),
      onSelected: (_) {
        HapticFeedback.selectionClick();
        onTap();
      },
    );
  }
}
