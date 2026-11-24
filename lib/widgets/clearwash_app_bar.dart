import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../models/shift_summary.dart';
import '../theme/clearwash_theme.dart';

/// Apple-inspired frosted translucent top app bar displaying active cashier,
/// bay context, shift status, and Firestore vs local runtime status pill.
class ClearWashAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const ClearWashAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(68);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shiftAsync = ref.watch(activeShiftProvider);
    final isFirebaseReady = ref.watch(isFirebaseReadyProvider);
    final appEnv = ref.watch(appEnvironmentProvider);

    final shift = shiftAsync.value;
    final cashierName = shift?.cashierName.trim().isNotEmpty == true
        ? shift!.cashierName.trim()
        : (shiftAsync.isLoading ? 'Memuat Shift...' : 'Kasir POS');
    final initial = cashierName.substring(0, 1).toUpperCase();
    final bayLabel = shift?.bayLabel ?? 'ClearWash POS';
    final shiftLabel = shift?.shiftLabel ?? 'Menghubungkan terminal...';
    final isClosed = shift?.status == ShiftStatus.closed;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: ClearWashTheme.surfaceCard.withValues(alpha: 0.90),
            border: const Border(
              bottom: BorderSide(
                color: ClearWashTheme.borderHairline,
                width: 0.8,
              ),
            ),
          ),
          child: AppBar(
            toolbarHeight: 68,
            automaticallyImplyLeading: false,
            backgroundColor: Colors.transparent,
            foregroundColor: ClearWashTheme.slateInk,
            titleSpacing: 16,
            title: Row(
              children: [
                _CashierAvatar(initial: initial, isShiftOpen: !isClosed),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              cashierName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: ClearWashTheme.slateInk,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: ClearWashTheme.canvas,
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(
                                  color: ClearWashTheme.borderHairline,
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                bayLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: ClearWashTheme.slateMuted,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: isClosed
                                  ? ClearWashTheme.waitingAccent
                                  : ClearWashTheme.readyAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              isClosed ? '$shiftLabel • TUTUP' : shiftLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isClosed
                                    ? ClearWashTheme.waitingText
                                    : ClearWashTheme.slateSubtleText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _DataModeChip(
                  envLabel: appEnv.label,
                  isFirebaseReady: isFirebaseReady,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CashierAvatar extends StatelessWidget {
  const _CashierAvatar({required this.initial, required this.isShiftOpen});

  final String initial;
  final bool isShiftOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isShiftOpen
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [ClearWashTheme.brightCobalt, Color(0xFF0055D4)],
              )
            : null,
        color: isShiftOpen ? null : ClearWashTheme.slateSubtleText,
        boxShadow: isShiftOpen
            ? [
                BoxShadow(
                  color: ClearWashTheme.actionCobalt.withValues(alpha: 0.22),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 16.5,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _DataModeChip extends StatelessWidget {
  const _DataModeChip({
    required this.envLabel,
    required this.isFirebaseReady,
  });

  final String envLabel;
  final bool isFirebaseReady;

  @override
  Widget build(BuildContext context) {
    final bgColor = isFirebaseReady
        ? ClearWashTheme.readyBg
        : ClearWashTheme.canvas;
    final borderColor = isFirebaseReady
        ? ClearWashTheme.readyAccent.withValues(alpha: 0.35)
        : ClearWashTheme.borderHairline;
    final dotColor = isFirebaseReady
        ? ClearWashTheme.readyAccent
        : ClearWashTheme.waitingAccent;
    final textColor = isFirebaseReady
        ? ClearWashTheme.readyText
        : ClearWashTheme.slateMuted;
    final modeLabel = isFirebaseReady ? 'FIRESTORE' : 'LOCAL';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            '$envLabel • $modeLabel',
            style: ClearWashTheme.monoStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: textColor,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
