import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../di/providers.dart';
import '../models/carwash_order.dart';
import '../theme/clearwash_theme.dart';
import 'license_plate_badge.dart';

const String _clearWashQrisNmid = 'ID1029384756382';

/// Builds an EMVCo-formatted QRIS payload string embedding merchant [nmid],
/// transaction [amount] in IDR, order [reference], and a CRC-16/CCITT checksum.
String buildQrisPayload({
  required int amount,
  required String nmid,
  required String reference,
}) {
  String tlv(String tag, String value) {
    final len = value.length.toString().padLeft(2, '0');
    return '$tag$len$value';
  }

  final cleanNmid = nmid.trim();
  final cleanRef = reference.trim().isEmpty ? 'CLEARWASH' : reference.trim();
  final truncatedRef =
      cleanRef.length > 25 ? cleanRef.substring(0, 25) : cleanRef;
  final safeAmount = amount < 0 ? 0 : amount;

  final merchantInfo = [
    tlv('00', 'ID.CO.QRIS.WWW'),
    tlv('01', cleanNmid),
    tlv('02', truncatedRef),
    tlv('03', 'UMI'),
  ].join();

  final additionalData = tlv('01', truncatedRef);

  final bodyWithoutCrc = [
    tlv('00', '01'),
    tlv('01', '12'),
    tlv('26', merchantInfo),
    tlv('52', '7542'),
    tlv('53', '360'),
    if (safeAmount > 0) tlv('54', '$safeAmount'),
    tlv('58', 'ID'),
    tlv('59', 'CLEARWASH CAR & BIKE POS'),
    tlv('60', 'JAKARTA'),
    tlv('62', additionalData),
    '6304',
  ].join();

  var crc = 0xFFFF;
  for (final codeUnit in bodyWithoutCrc.codeUnits) {
    crc ^= (codeUnit & 0xFF) << 8;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) : (crc << 1);
      crc &= 0xFFFF;
    }
  }
  final crcHex = crc.toRadixString(16).toUpperCase().padLeft(4, '0');
  return '$bodyWithoutCrc$crcHex';
}

enum _PaymentStep { selectMethod, cash, qris }

/// Displays the two-step ClearWash POS checkout bottom sheet for Cash or QRIS
/// settlement and returns the newly created [CarwashOrder] upon confirmation.
Future<CarwashOrder?> showPaymentModal(BuildContext context, WidgetRef ref) {
  final initialRegistration = ref.read(posRegistrationProvider);
  return showModalBottomSheet<CarwashOrder>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _PaymentModalSheet(
      initialState: initialRegistration,
    ),
  );
}

class _PaymentModalSheet extends ConsumerStatefulWidget {
  const _PaymentModalSheet({
    required this.initialState,
  });

  final PosRegistrationState initialState;

  @override
  ConsumerState<_PaymentModalSheet> createState() => _PaymentModalSheetState();
}

class _PaymentModalSheetState extends ConsumerState<_PaymentModalSheet> {
  late final TextEditingController _nominalController;
  _PaymentStep _step = _PaymentStep.selectMethod;
  String? _qrisProofFileName;
  int _proofCaptureCount = 0;
  String? _localError;

  @override
  void initState() {
    super.initState();
    final price = widget.initialState.selectedPackage.price;
    _nominalController = TextEditingController(text: '$price');
  }

  @override
  void dispose() {
    _nominalController.dispose();
    super.dispose();
  }

  int get _parsedCashTendered =>
      int.tryParse(_nominalController.text.trim()) ?? 0;

  void _setNominal(int amount) {
    final text = '$amount';
    _nominalController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() {
      _localError = null;
    });
  }

  void _attachSimulatedProof() {
    _proofCaptureCount++;
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final suffix = _proofCaptureCount > 1 ? '_v$_proofCaptureCount' : '';
    setState(() {
      _qrisProofFileName = 'QRIS_ClearWash_$hh$mm$suffix.jpg';
      _localError = null;
    });
  }

  Future<void> _submitOrder({
    required PaymentMethod paymentMethod,
    int cashTendered = 0,
    String? qrisProofFileName,
    required String fallbackError,
  }) async {
    setState(() => _localError = null);
    final order = await ref.read(posRegistrationProvider.notifier).submitOrder(
      paymentMethod: paymentMethod,
      cashTendered: cashTendered,
      qrisProofFileName: qrisProofFileName,
    );
    if (!mounted) {
      return;
    }
    if (order != null) {
      Navigator.of(context).pop(order);
    } else {
      final err = ref.read(posRegistrationProvider).errorMessage;
      setState(() => _localError = err ?? fallbackError);
    }
  }

  Future<void> _submitCash(int totalPrice) async {
    final tendered = _parsedCashTendered;
    if (tendered < totalPrice) {
      setState(() {
        _localError =
            'Nominal tunai kurang ${formatRupiah(totalPrice - tendered)} dari total tagihan.';
      });
      return;
    }
    await _submitOrder(
      paymentMethod: PaymentMethod.cash,
      cashTendered: tendered,
      fallbackError: 'Gagal memproses pembayaran tunai.',
    );
  }

  Future<void> _submitQris() async {
    final proof = _qrisProofFileName;
    if (proof == null || proof.isEmpty) {
      setState(() {
        _localError = 'Lampirkan foto bukti pembayaran QRIS terlebih dahulu.';
      });
      return;
    }
    await _submitOrder(
      paymentMethod: PaymentMethod.qris,
      qrisProofFileName: proof,
      fallbackError: 'Gagal memproses pembayaran QRIS.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final regState = ref.watch(posRegistrationProvider);
    final displayState = regState.licensePlate.trim().isNotEmpty
        ? regState
        : widget.initialState;
    final pkg = displayState.selectedPackage;
    final vehicleTitle =
        '${displayState.selectedBrand} ${displayState.modelName.trim()}'.trim();
    final isSubmitting = regState.isSubmitting;
    final viewInsetsBottom = MediaQuery.viewInsetsOf(context).bottom;

    final stepTitle = switch (_step) {
      _PaymentStep.selectMethod => 'Pilih Metode Pembayaran',
      _PaymentStep.cash => 'Pembayaran Tunai (Cash)',
      _PaymentStep.qris => 'Pembayaran QRIS',
    };

    return Container(
      decoration: ClearWashTheme.sheetDecoration(),
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsetsBottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClearWashTheme.sheetGrabber(),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (_step != _PaymentStep.selectMethod) ...[
                    IconButton(
                      onPressed: isSubmitting
                          ? null
                          : () => setState(() {
                              _step = _PaymentStep.selectMethod;
                              _localError = null;
                            }),
                      tooltip: 'Kembali',
                      style: IconButton.styleFrom(
                        backgroundColor: ClearWashTheme.canvas,
                        shape: const CircleBorder(),
                        minimumSize: const Size(40, 40),
                      ),
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        size: 20,
                        color: ClearWashTheme.slateInk,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _step == _PaymentStep.selectMethod
                              ? 'LANGKAH 1 • PEMBAYARAN'
                              : 'LANGKAH 2 • KONFIRMASI',
                          style: ClearWashTheme.sectionLabelStyle(
                            fontSize: 10.5,
                            color: ClearWashTheme.actionCobalt,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          stepTitle,
                          style: ClearWashTheme.headingStyle(fontSize: 18),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed:
                        isSubmitting ? null : () => Navigator.of(context).pop(),
                    tooltip: 'Tutup',
                    style: IconButton.styleFrom(
                      minimumSize: const Size(44, 44),
                    ),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: ClearWashTheme.slateMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _OrderSummaryBanner(
                package: pkg,
                vehicleTitle: vehicleTitle,
                licensePlate: displayState.licensePlate,
                vehicleType: displayState.vehicleType,
              ),
              if (_localError != null) ...[
                const SizedBox(height: 12),
                _ModalErrorBanner(message: _localError!),
              ],
              const SizedBox(height: 16),
              switch (_step) {
                _PaymentStep.selectMethod => _buildMethodSelector(),
                _PaymentStep.cash => _buildCashStep(pkg, isSubmitting),
                _PaymentStep.qris => _buildQrisStep(
                  pkg,
                  displayState.licensePlate,
                  isSubmitting,
                ),
              },
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMethodSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PaymentMethodTile(
          icon: Icons.payments_rounded,
          iconBg: ClearWashTheme.readyBg,
          iconColor: ClearWashTheme.readyText,
          title: 'Tunai (Cash)',
          subtitle: 'Hitung nominal diterima & kembalian kasir secara otomatis',
          badge: 'INSTAN',
          onTap: () => setState(() {
            _step = _PaymentStep.cash;
            _localError = null;
          }),
        ),
        const SizedBox(height: 12),
        _PaymentMethodTile(
          icon: Icons.qr_code_2_rounded,
          iconBg: ClearWashTheme.surfaceSubtle,
          iconColor: ClearWashTheme.actionCobalt,
          title: 'QRIS',
          subtitle: 'Tampilkan QR ClearWash & lampirkan foto bukti transfer',
          badge: 'DIGITAL',
          onTap: () => setState(() {
            _step = _PaymentStep.qris;
            _localError = null;
          }),
        ),
      ],
    );
  }

  Widget _buildCashStep(WashPackage pkg, bool isSubmitting) {
    final tendered = _parsedCashTendered;
    final isEnough = tendered >= pkg.price;
    final change = tendered - pkg.price;

    final quickChips = <({String label, int amount})>[
      (label: 'Uang Pas', amount: pkg.price),
      (label: '50rb', amount: 50000),
      (label: '100rb', amount: 100000),
      (label: '150rb', amount: 150000),
      (label: '200rb', amount: 200000),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'NOMINAL CEPAT',
          style: ClearWashTheme.sectionLabelStyle(),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: quickChips.map((chip) {
            final selected = tendered == chip.amount;
            return ChoiceChip(
              selected: selected,
              showCheckmark: false,
              shape: const StadiumBorder(),
              materialTapTargetSize: MaterialTapTargetSize.padded,
              labelPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              selectedColor: ClearWashTheme.actionCobalt,
              backgroundColor: ClearWashTheme.canvas,
              side: BorderSide(
                color: selected
                    ? ClearWashTheme.actionCobalt
                    : ClearWashTheme.borderHairline,
                width: 0.9,
              ),
              label: Text(
                chip.label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : ClearWashTheme.slateInk,
                ),
              ),
              onSelected: isSubmitting
                  ? null
                  : (_) {
                      HapticFeedback.selectionClick();
                      _setNominal(chip.amount);
                    },
            );
          }).toList(growable: false),
        ),
        const SizedBox(height: 14),
        Text(
          'NOMINAL TUNAI DITERIMA',
          style: ClearWashTheme.sectionLabelStyle(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nominalController,
          enabled: !isSubmitting,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: ClearWashTheme.monoStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
          decoration: InputDecoration(
            prefixText: 'Rp ',
            prefixStyle: ClearWashTheme.monoStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: ClearWashTheme.slateMuted,
            ),
            hintText: '0',
            suffixIcon: _nominalController.text.isNotEmpty
                ? IconButton(
                    onPressed: isSubmitting
                        ? null
                        : () {
                            _nominalController.clear();
                            setState(() {});
                          },
                    icon: const Icon(Icons.clear_rounded),
                  )
                : null,
          ),
          onChanged: (_) => setState(() {
            _localError = null;
          }),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isEnough ? ClearWashTheme.readyBg : ClearWashTheme.errorBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isEnough
                  ? ClearWashTheme.readyAccent
                  : ClearWashTheme.errorBorder,
              width: 1.3,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEnough ? 'Kembalian' : 'Nominal Belum Cukup',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: isEnough
                            ? ClearWashTheme.readyText
                            : ClearWashTheme.errorRed,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isEnough
                          ? 'Siap dicetak sebagai tiket LUNAS'
                          : 'Minimal ${formatRupiah(pkg.price)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isEnough
                            ? ClearWashTheme.readyText
                            : ClearWashTheme.errorRed,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isEnough
                    ? formatRupiah(change)
                    : '-${formatRupiah(pkg.price - tendered)}',
                style: ClearWashTheme.monoStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: isEnough
                      ? ClearWashTheme.readyText
                      : ClearWashTheme.errorRed,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: isSubmitting ? null : () => _submitCash(pkg.price),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            backgroundColor: ClearWashTheme.actionCobalt,
          ),
          icon: isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.print_rounded),
          label: Text(
            isSubmitting ? 'Memproses Tiket...' : 'Konfirmasi & Cetak Tiket',
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }

  Widget _buildQrisStep(
    WashPackage pkg,
    String licensePlate,
    bool isSubmitting,
  ) {
    final proof = _qrisProofFileName;
    final hasProof = proof != null && proof.isNotEmpty;
    final cleanPlate = normalizeLicensePlate(licensePlate);
    final payload = buildQrisPayload(
      amount: pkg.price,
      nmid: _clearWashQrisNmid,
      reference: cleanPlate.isEmpty ? pkg.id : '${pkg.id}-$cleanPlate',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: ClearWashTheme.cardDecoration(
            color: ClearWashTheme.canvas,
            radius: 18,
            elevated: false,
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ClearWash Car & Bike POS',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: ClearWashTheme.slateInk,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'NMID: $_clearWashQrisNmid',
                          style: ClearWashTheme.monoStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: ClearWashTheme.slateMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: ClearWashTheme.errorRed,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'QRIS',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ClearWashTheme.borderHairline),
                ),
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        QrImageView(
                          data: payload,
                          version: QrVersions.auto,
                          size: 192,
                          padding: const EdgeInsets.all(6),
                          errorCorrectionLevel: QrErrorCorrectLevel.M,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: ClearWashTheme.slateInk,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: ClearWashTheme.slateInk,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: ClearWashTheme.errorRed,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'QRIS',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      formatRupiah(pkg.price),
                      style: ClearWashTheme.monoStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: ClearWashTheme.actionCobalt,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: hasProof
                      ? ClearWashTheme.readyBg
                      : ClearWashTheme.waitingBg,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: hasProof
                        ? ClearWashTheme.readyAccent
                        : ClearWashTheme.waitingAccent,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      hasProof
                          ? Icons.verified_rounded
                          : Icons.hourglass_top_rounded,
                      size: 16,
                      color: hasProof
                          ? ClearWashTheme.readyText
                          : ClearWashTheme.waitingText,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        hasProof
                            ? 'Bukti Pembayaran Terlampir'
                            : 'Menunggu Pembayaran Customer...',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: hasProof
                              ? ClearWashTheme.readyText
                              : ClearWashTheme.waitingText,
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
        if (!hasProof)
          OutlinedButton.icon(
            onPressed: isSubmitting ? null : _attachSimulatedProof,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              side: const BorderSide(
                color: ClearWashTheme.actionCobalt,
                width: 1.5,
              ),
              foregroundColor: ClearWashTheme.actionCobalt,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.camera_alt_rounded),
            label: const Text(
              'Foto Bukti Pembayaran',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: ClearWashTheme.surfaceSubtle,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ClearWashTheme.brightCobalt),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: ClearWashTheme.readyBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: ClearWashTheme.readyText,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        proof,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ClearWashTheme.monoStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Bukti transfer QRIS siap dilampirkan',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: ClearWashTheme.slateMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: isSubmitting ? null : _attachSimulatedProof,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(64, 48),
                    foregroundColor: ClearWashTheme.actionCobalt,
                  ),
                  child: const Text(
                    'Ganti',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: (!hasProof || isSubmitting) ? null : _submitQris,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            backgroundColor: ClearWashTheme.actionCobalt,
          ),
          icon: isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.print_rounded),
          label: Text(
            isSubmitting ? 'Memproses Tiket...' : 'Cetak Tiket',
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _OrderSummaryBanner extends StatelessWidget {
  const _OrderSummaryBanner({
    required this.package,
    required this.vehicleTitle,
    required this.licensePlate,
    required this.vehicleType,
  });

  final WashPackage package;
  final String vehicleTitle;
  final String licensePlate;
  final VehicleType vehicleType;

  @override
  Widget build(BuildContext context) {
    return Container(
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
                      package.name,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: ClearWashTheme.slateInk,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      vehicleTitle.isEmpty ? vehicleType.label : vehicleTitle,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: ClearWashTheme.slateMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatRupiah(package.price),
                style: ClearWashTheme.monoStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: ClearWashTheme.actionCobalt,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                LicensePlateBadge(
                  plate: licensePlate,
                  vehicleType: vehicleType,
                  compact: true,
                ),
                Text(
                  'Estimasi ±${package.estimatedMinutes} mnt',
                  style: ClearWashTheme.monoStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ClearWashTheme.slateMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodTile extends StatelessWidget {
  const _PaymentMethodTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 84),
          padding: const EdgeInsets.all(14),
          decoration: ClearWashTheme.cardDecoration(radius: 16),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 26, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: ClearWashTheme.slateInk,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: ClearWashTheme.surfaceSubtle,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            badge,
                            style: ClearWashTheme.monoStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: ClearWashTheme.actionCobalt,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: ClearWashTheme.slateMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: ClearWashTheme.slateMuted,
                size: 26,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModalErrorBanner extends StatelessWidget {
  const _ModalErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              message,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: ClearWashTheme.errorRed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
