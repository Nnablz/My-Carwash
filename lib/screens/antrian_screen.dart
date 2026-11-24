import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../models/carwash_order.dart';
import '../models/wash_bay.dart';
import '../theme/clearwash_theme.dart';
import '../widgets/license_plate_badge.dart';

/// Tab 2 — Live carwash operational queue, bay allocation, and status pipeline.
class AntrianScreen extends ConsumerWidget {
  const AntrianScreen({super.key});

  static const List<String> _operatorPresets = [
    'Joko S.',
    'Asep',
    'Budi R.',
    'Rian',
  ];

  Future<void> _openStartWashSheet(
    BuildContext context,
    CarwashOrder order,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BayAssignmentSheet(
        order: order,
        operatorPresets: _operatorPresets,
      ),
    );
  }

  Future<void> _runOrderAction(
    BuildContext context,
    Future<void> Function() action, {
    required String successMessage,
    required String errorPrefix,
  }) async {
    try {
      await action();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$errorPrefix: $error')),
      );
    }
  }

  Future<void> _markReady(
    BuildContext context,
    WidgetRef ref,
    CarwashOrder order,
  ) => _runOrderAction(
    context,
    () => ref.read(carwashRepositoryProvider).markReadyForPickup(order.id),
    successMessage:
        '${order.licensePlate} (${order.queueNumber}) selesai dicuci dan siap diambil.',
    errorPrefix: 'Gagal memperbarui status',
  );

  Future<void> _completeHandover(
    BuildContext context,
    WidgetRef ref,
    CarwashOrder order,
  ) => _runOrderAction(
    context,
    () => ref.read(carwashRepositoryProvider).completeHandover(order.id),
    successMessage:
        'Serah terima kunci ${order.licensePlate} (${order.queueNumber}) selesai.',
    errorPrefix: 'Gagal menyelesaikan serah terima',
  );

  Future<void> _confirmCancel(
    BuildContext context,
    WidgetRef ref,
    CarwashOrder order,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Batalkan Antrian?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Batalkan pesanan ${order.queueNumber} (${order.vehicleTitle} • ${order.licensePlate}) dari antrian aktif?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Kembali'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: ClearWashTheme.errorRed,
            ),
            child: const Text('Ya, Batalkan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }

    await _runOrderAction(
      context,
      () => ref.read(carwashRepositoryProvider).cancelOrder(order.id),
      successMessage: 'Pesanan ${order.queueNumber} dibatalkan.',
      errorPrefix: 'Gagal membatalkan pesanan',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(queueStatsProvider);
    final activeFilter = ref.watch(queueFilterProvider);
    final ordersAsync = ref.watch(filteredQueueOrdersProvider);
    final baysAsync = ref.watch(baysProvider);
    final shiftReportAsync = ref.watch(shiftReportProvider);

    final bays = baysAsync.value ?? const <WashBay>[];
    final occupiedBays = bays
        .where((bay) => bay.status == BayStatus.occupied)
        .length;
    final avgMinutes = shiftReportAsync.value?.averageWashMinutes ?? 0;

    return ColoredBox(
      color: ClearWashTheme.canvas,
      child: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Live Header Counter Strip
                        _HeaderCounterStrip(stats: stats),
                        const SizedBox(height: 12),

                        // 4 Segmented Filter Buttons
                        _QueueFilterBar(
                          activeFilter: activeFilter,
                          onSelect: (filter) => ref
                              .read(queueFilterProvider.notifier)
                              .setFilter(filter),
                        ),
                        const SizedBox(height: 12),

                        // Operational Metrics Row
                        _OperationalMetricsRow(
                          avgMinutes: avgMinutes,
                          occupiedBays: occupiedBays,
                          totalBays: bays.length,
                          completedToday: stats.completedToday,
                        ),
                        const SizedBox(height: 14),

                        // Wash Bay Status Strip
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'STATUS BAY CUCI',
                              style: ClearWashTheme.sectionLabelStyle(),
                            ),
                            Text(
                              '${bays.length - occupiedBays} Bay Kosong',
                              style: ClearWashTheme.monoStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: ClearWashTheme.readyText,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _WashBayStatusStrip(baysAsync: baysAsync),
                        const SizedBox(height: 16),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'DAFTAR ANTRIAN (${activeFilter.label.toUpperCase()})',
                              style: ClearWashTheme.sectionLabelStyle(),
                            ),
                            if (ordersAsync.value != null)
                              Text(
                                '${ordersAsync.value!.length} Unit',
                                style: ClearWashTheme.monoStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: ClearWashTheme.actionCobalt,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),

                // Queue Cards Sliver
                ordersAsync.when(
                  loading: () => const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, _) => SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverToBoxAdapter(
                      child: _ErrorCard(message: 'Gagal memuat antrian: $error'),
                    ),
                  ),
                  data: (orders) {
                    if (orders.isEmpty) {
                      return SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                        sliver: SliverToBoxAdapter(
                          child: _EmptyQueueCard(
                            filter: activeFilter,
                            onResetFilter: activeFilter == QueueFilter.all
                                ? null
                                : () => ref
                                      .read(queueFilterProvider.notifier)
                                      .setFilter(QueueFilter.all),
                          ),
                        ),
                      );
                    }
                    return SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      sliver: SliverList.separated(
                        itemCount: orders.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final order = orders[index];
                          return _QueueOrderCard(
                            order: order,
                            onStartWash: () =>
                                _openStartWashSheet(context, order),
                            onCancel: () =>
                                _confirmCancel(context, ref, order),
                            onMarkReady: () =>
                                _markReady(context, ref, order),
                            onCompleteHandover: () =>
                                _completeHandover(context, ref, order),
                          );
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Sticky CTA Bar
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
            child: FilledButton.icon(
              onPressed: () {
                HapticFeedback.selectionClick();
                ref.read(activeTabIndexProvider.notifier).goToKasir();
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: ClearWashTheme.slateInk,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
              label: const Text(
                'INPUT KENDARAAN BARU',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCounterStrip extends StatelessWidget {
  const _HeaderCounterStrip({required this.stats});

  final QueueStats stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: ClearWashTheme.cardDecoration(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: ClearWashTheme.surfaceSubtle,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.local_car_wash_rounded,
                  color: ClearWashTheme.actionCobalt,
                  size: 17,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '${stats.totalActive} KENDARAAN AKTIF',
                  style: ClearWashTheme.monoStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: ClearWashTheme.slateInk,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: ClearWashTheme.readyBg,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text(
                  'LIVE QUEUE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: ClearWashTheme.readyText,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _CounterPill(
                  label: 'MENUNGGU',
                  count: stats.waiting,
                  bg: ClearWashTheme.waitingBg,
                  fg: ClearWashTheme.waitingText,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CounterPill(
                  label: 'DICUCI',
                  count: stats.washing,
                  bg: ClearWashTheme.washingBg,
                  fg: ClearWashTheme.washingText,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CounterPill(
                  label: 'SELESAI',
                  count: stats.ready,
                  bg: ClearWashTheme.readyBg,
                  fg: ClearWashTheme.readyText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CounterPill extends StatelessWidget {
  const _CounterPill({
    required this.label,
    required this.count,
    required this.bg,
    required this.fg,
  });

  final String label;
  final int count;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: ClearWashTheme.monoStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: fg,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueFilterBar extends StatelessWidget {
  const _QueueFilterBar({
    required this.activeFilter,
    required this.onSelect,
  });

  final QueueFilter activeFilter;
  final ValueChanged<QueueFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3.5),
      decoration: BoxDecoration(
        color: const Color(0x1F767680),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: QueueFilter.values
            .map((filter) {
              final selected = filter == activeFilter;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onSelect(filter);
                  },
                  child: AnimatedContainer(
                    duration: ClearWashTheme.motionDuration,
                    curve: ClearWashTheme.motionCurve,
                    constraints: const BoxConstraints(minHeight: 38),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? ClearWashTheme.surfaceCard
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      boxShadow: selected
                          ? const [
                              BoxShadow(
                                color: Color(0x16000000),
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      filter.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected
                            ? ClearWashTheme.slateInk
                            : ClearWashTheme.slateMuted,
                      ),
                    ),
                  ),
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class _OperationalMetricsRow extends StatelessWidget {
  const _OperationalMetricsRow({
    required this.avgMinutes,
    required this.occupiedBays,
    required this.totalBays,
    required this.completedToday,
  });

  final int avgMinutes;
  final int occupiedBays;
  final int totalBays;
  final int completedToday;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MetricTile(
            label: 'Rata-rata Waktu',
            value: '$avgMinutes Mnt',
            accent: ClearWashTheme.actionCobalt,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MetricTile(
            label: 'Slot Bay Terisi',
            value: '$occupiedBays / $totalBays',
            accent: ClearWashTheme.washingText,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MetricTile(
            label: 'Total Selesai',
            value: '$completedToday',
            accent: ClearWashTheme.readyText,
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: ClearWashTheme.cardDecoration(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: ClearWashTheme.slateSubtleText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ClearWashTheme.monoStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _WashBayStatusStrip extends StatelessWidget {
  const _WashBayStatusStrip({required this.baysAsync});

  final AsyncValue<List<WashBay>> baysAsync;

  @override
  Widget build(BuildContext context) {
    return baysAsync.when(
      loading: () => const SizedBox(
        height: 82,
        child: Center(child: LinearProgressIndicator()),
      ),
      error: (err, _) => _ErrorCard(message: 'Gagal memuat bay: $err'),
      data: (bays) {
        if (bays.isEmpty) {
          return const SizedBox(
            height: 60,
            child: Center(child: Text('Belum ada data bay cuci.')),
          );
        }
        return SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: bays.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final bay = bays[index];
              final isAvailable = bay.status == BayStatus.available;
              final isOccupied = bay.status == BayStatus.occupied;

              final statusBg = isAvailable
                  ? ClearWashTheme.readyBg
                  : isOccupied
                  ? ClearWashTheme.washingBg
                  : ClearWashTheme.waitingBg;
              final statusFg = isAvailable
                  ? ClearWashTheme.readyText
                  : isOccupied
                  ? ClearWashTheme.washingText
                  : ClearWashTheme.waitingText;
              final borderColor = isAvailable
                  ? ClearWashTheme.readyAccent.withValues(alpha: 0.45)
                  : isOccupied
                  ? ClearWashTheme.washingAccent
                  : ClearWashTheme.waitingAccent;

              return Container(
                width: 156,
                padding: const EdgeInsets.all(11),
                decoration: ClearWashTheme.cardDecoration(
                  radius: 16,
                  borderColor: borderColor.withValues(alpha: 0.45),
                  borderWidth: 1.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          bay.supportedType == VehicleType.motor
                              ? Icons.two_wheeler_rounded
                              : Icons.directions_car_rounded,
                          size: 15,
                          color: ClearWashTheme.slateInk,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            bay.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ClearWashTheme.monoStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            bay.status.label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: statusFg,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (isOccupied && bay.currentPlate != null) ...[
                      Text(
                        bay.currentPlate!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ClearWashTheme.monoStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: ClearWashTheme.washingText,
                        ),
                      ),
                      Text(
                        bay.operatorName ?? '-',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: ClearWashTheme.slateMuted,
                        ),
                      ),
                    ] else
                      Text(
                        isAvailable ? 'Siap Terima Unit' : 'Sedang Perbaikan',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: ClearWashTheme.slateMuted,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _QueueOrderCard extends StatelessWidget {
  const _QueueOrderCard({
    required this.order,
    required this.onStartWash,
    required this.onCancel,
    required this.onMarkReady,
    required this.onCompleteHandover,
  });

  final CarwashOrder order;
  final VoidCallback onStartWash;
  final VoidCallback onCancel;
  final VoidCallback onMarkReady;
  final VoidCallback onCompleteHandover;

  String _elapsedLabel(CarwashOrder order) {
    final now = DateTime.now();
    final refTime = switch (order.status) {
      OrderStatus.washing => order.startedWashingAt ?? order.createdAt,
      OrderStatus.ready => order.finishedAt ?? order.createdAt,
      _ => order.createdAt,
    };
    final mins = now.difference(refTime).inMinutes;
    final safeMins = mins < 0 ? 0 : mins;
    return switch (order.status) {
      OrderStatus.washing => 'Cuci ${safeMins}m',
      OrderStatus.ready => 'Siap ${safeMins}m',
      _ => 'Tunggu ${safeMins}m',
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = ClearWashTheme.statusPalette(order.status);
    final isPaid = order.paymentStatus == PaymentStatus.paid;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: ClearWashTheme.cardDecoration(
        radius: 18,
        borderColor: palette.accent.withValues(alpha: 0.3),
        borderWidth: 1.0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Strip: License Plate + Status & Queue # / Elapsed
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: LicensePlateBadge(
                  plate: order.licensePlate,
                  vehicleType: order.vehicleType,
                  compact: true,
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: palette.background,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      order.status.label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: palette.foreground,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${switch (extractQueueDigits(order.queueNumber)) {
                      final digits? => '#$digits',
                      null => order.queueNumber,
                    }} • ${_elapsedLabel(order)}',
                    style: ClearWashTheme.monoStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: ClearWashTheme.slateSubtleText,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Vehicle Title, Size & Payment Badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                    const SizedBox(height: 3),
                    Text(
                      '${order.packageName} • Ukuran ${order.vehicleSize.label}',
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatRupiah(order.price),
                    style: ClearWashTheme.monoStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: ClearWashTheme.slateInk,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isPaid
                          ? ClearWashTheme.readyBg
                          : ClearWashTheme.waitingBg,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '${order.paymentMethod.label} • ${isPaid ? 'Lunas' : 'Belum'}',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: isPaid
                            ? ClearWashTheme.readyText
                            : ClearWashTheme.waitingText,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Bay / Operator & Pickup Meta Strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: ClearWashTheme.canvas,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  order.bayName != null
                      ? Icons.water_drop_rounded
                      : Icons.schedule_rounded,
                  size: 15,
                  color: ClearWashTheme.actionCobalt,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    order.bayName != null
                        ? '${order.bayName} • Operator: ${order.operatorName ?? '-'}'
                        : 'Siap Ambil: ${order.pickupDisplay}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: ClearWashTheme.slateInk,
                    ),
                  ),
                ),
                if (order.bayName != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    order.pickupDisplay,
                    style: ClearWashTheme.monoStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: ClearWashTheme.slateMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Direct Action Trigger
          switch (order.status) {
            OrderStatus.waiting => Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onStartWash,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 50),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      backgroundColor: ClearWashTheme.actionCobalt,
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 21),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'MULAI CUCI - MASUKKAN KE BAY',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 50),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    side: const BorderSide(color: ClearWashTheme.errorBorder),
                    foregroundColor: ClearWashTheme.errorRed,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
            OrderStatus.washing => FilledButton.icon(
              onPressed: onMarkReady,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: ClearWashTheme.washingAccent,
              ),
              icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
              label: const Text(
                'SELESAI CUCI (KE FINISHING)',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            OrderStatus.ready => FilledButton.icon(
              onPressed: onCompleteHandover,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: ClearWashTheme.readyAccent,
              ),
              icon: const Icon(Icons.key_rounded, size: 20),
              label: const Text(
                'SERAHKAN KUNCI / AMBIL',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            OrderStatus.completed || OrderStatus.cancelled => const SizedBox.shrink(),
          },
        ],
      ),
    );
  }
}

class _BayAssignmentSheet extends ConsumerStatefulWidget {
  const _BayAssignmentSheet({
    required this.order,
    required this.operatorPresets,
  });

  final CarwashOrder order;
  final List<String> operatorPresets;

  @override
  ConsumerState<_BayAssignmentSheet> createState() =>
      _BayAssignmentSheetState();
}

class _BayAssignmentSheetState extends ConsumerState<_BayAssignmentSheet> {
  String? _selectedBayId;
  late String _selectedOperator;
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _selectedOperator = widget.operatorPresets.first;
  }

  Future<void> _confirmStart(List<WashBay> compatibleBays) async {
    if (_isSubmitting) {
      return;
    }
    final targetBay = compatibleBays.firstWhere(
      (b) => b.id == _selectedBayId,
      orElse: () => compatibleBays.first,
    );

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    try {
      await ref.read(carwashRepositoryProvider).startWash(
        orderId: widget.order.id,
        bayId: targetBay.id,
        operatorName: _selectedOperator,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '${widget.order.licensePlate} masuk ke ${targetBay.name} ($_selectedOperator).',
            ),
          ),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _errorText = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final baysAsync = ref.watch(baysProvider);
    final bays = baysAsync.value ?? const <WashBay>[];
    final compatibleBays = bays
        .where(
          (bay) =>
              bay.isAvailable &&
              bay.supportsVehicleType(widget.order.vehicleType),
        )
        .toList(growable: false);

    final activeBayId = compatibleBays.any((b) => b.id == _selectedBayId)
        ? _selectedBayId
        : (compatibleBays.isNotEmpty ? compatibleBays.first.id : null);

    return Container(
      decoration: ClearWashTheme.sheetDecoration(),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ALOKASI BAY & OPERATOR',
                          style: ClearWashTheme.sectionLabelStyle(
                            fontSize: 10.5,
                            color: ClearWashTheme.actionCobalt,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Mulai Cuci ${widget.order.queueNumber}',
                          style: ClearWashTheme.headingStyle(fontSize: 18),
                        ),
                      ],
                    ),
                  ),
                  LicensePlateBadge(
                    plate: widget.order.licensePlate,
                    vehicleType: widget.order.vehicleType,
                    compact: true,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'PILIH BAY TERSEDIA (${widget.order.vehicleType.label.toUpperCase()})',
                style: ClearWashTheme.sectionLabelStyle(),
              ),
              const SizedBox(height: 8),
              if (compatibleBays.isEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: ClearWashTheme.waitingBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ClearWashTheme.waitingAccent),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: ClearWashTheme.waitingText,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Semua bay untuk ${widget.order.vehicleType.label} sedang terisi. Selesaikan cucian aktif terlebih dahulu.',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: ClearWashTheme.waitingText,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: compatibleBays.map((bay) {
                    final selected = bay.id == activeBayId;
                    return ChoiceChip(
                      selected: selected,
                      showCheckmark: false,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      labelPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      selectedColor: ClearWashTheme.actionCobalt,
                      backgroundColor: ClearWashTheme.surfaceSubtle,
                      side: BorderSide(
                        color: selected
                            ? ClearWashTheme.actionCobalt
                            : ClearWashTheme.borderSlate,
                        width: 1.4,
                      ),
                      label: Text(
                        bay.name,
                        style: ClearWashTheme.monoStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: selected
                              ? Colors.white
                              : ClearWashTheme.slateInk,
                        ),
                      ),
                      onSelected: _isSubmitting
                          ? null
                          : (_) => setState(() => _selectedBayId = bay.id),
                    );
                  }).toList(growable: false),
                ),
              const SizedBox(height: 16),
              Text(
                'PILIH OPERATOR PENCUCI',
                style: ClearWashTheme.sectionLabelStyle(),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.operatorPresets.map((op) {
                  final selected = op == _selectedOperator;
                  return ChoiceChip(
                    selected: selected,
                    showCheckmark: false,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    labelPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    selectedColor: ClearWashTheme.slateInk,
                    backgroundColor: ClearWashTheme.canvas,
                    side: BorderSide(
                      color: selected
                          ? ClearWashTheme.slateInk
                          : ClearWashTheme.borderSlate,
                      width: 1.3,
                    ),
                    avatar: Icon(
                      Icons.person_rounded,
                      size: 16,
                      color: selected
                          ? Colors.white
                          : ClearWashTheme.slateMuted,
                    ),
                    label: Text(
                      op,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? Colors.white
                            : ClearWashTheme.slateInk,
                      ),
                    ),
                    onSelected: _isSubmitting
                        ? null
                        : (_) => setState(() => _selectedOperator = op),
                  );
                }).toList(growable: false),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorText!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: ClearWashTheme.errorRed,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: (compatibleBays.isEmpty || _isSubmitting)
                    ? null
                    : () => _confirmStart(compatibleBays),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: ClearWashTheme.actionCobalt,
                ),
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.water_drop_rounded),
                label: Text(
                  _isSubmitting
                      ? 'Menghubungkan ke Bay...'
                      : 'Konfirmasi & Mulai Cuci',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyQueueCard extends StatelessWidget {
  const _EmptyQueueCard({
    required this.filter,
    this.onResetFilter,
  });

  final QueueFilter filter;
  final VoidCallback? onResetFilter;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: ClearWashTheme.cardDecoration(radius: 18),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: ClearWashTheme.canvas,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.local_car_wash_outlined,
              size: 28,
              color: ClearWashTheme.slateSubtleText,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            filter == QueueFilter.all
                ? 'Belum ada kendaraan aktif di antrian'
                : 'Tidak ada kendaraan dengan status ${filter.label}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: ClearWashTheme.slateInk,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tambahkan kendaraan baru dari tab Kasir untuk mulai mencuci.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: ClearWashTheme.slateMuted,
            ),
          ),
          if (onResetFilter != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onResetFilter,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
              ),
              child: const Text('Tampilkan Semua Antrian'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ClearWashTheme.errorBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ClearWashTheme.errorBorder),
      ),
      child: Text(
        message,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: ClearWashTheme.errorRed,
        ),
      ),
    );
  }
}
