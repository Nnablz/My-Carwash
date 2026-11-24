import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../theme/clearwash_theme.dart';
import '../widgets/clearwash_app_bar.dart';
import 'antrian_screen.dart';
import 'kasir_screen.dart';
import 'shift_screen.dart';

/// Root 3-tab ClearWash POS shell housing Kasir, Antrian, and Shift tabs.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTab = ref.watch(activeTabIndexProvider);
    final stats = ref.watch(queueStatsProvider);

    return Scaffold(
      backgroundColor: ClearWashTheme.canvas,
      appBar: const ClearWashAppBar(),
      body: IndexedStack(
        index: activeTab,
        children: const [
          KasirScreen(),
          AntrianScreen(),
          ShiftScreen(),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: ClearWashTheme.surfaceCard,
          border: Border(
            top: BorderSide(
              color: ClearWashTheme.borderHairline,
              width: 0.8,
            ),
          ),
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            height: 66,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            indicatorColor: ClearWashTheme.actionCobalt.withValues(alpha: 0.12),
            indicatorShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? ClearWashTheme.actionCobalt
                    : ClearWashTheme.slateSubtleText,
              );
            }),
            iconTheme: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return IconThemeData(
                size: 23,
                color: selected
                    ? ClearWashTheme.actionCobalt
                    : ClearWashTheme.slateSubtleText,
              );
            }),
          ),
          child: NavigationBar(
            selectedIndex: activeTab,
            elevation: 0,
            onDestinationSelected: (index) {
              HapticFeedback.selectionClick();
              ref.read(activeTabIndexProvider.notifier).setTab(index);
            },
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.point_of_sale_outlined),
                selectedIcon: Icon(Icons.point_of_sale_rounded),
                label: 'Kasir',
              ),
              NavigationDestination(
                icon: Badge.count(
                  count: stats.totalActive,
                  isLabelVisible: stats.totalActive > 0,
                  backgroundColor: ClearWashTheme.actionCobalt,
                  child: const Icon(Icons.local_car_wash_outlined),
                ),
                selectedIcon: Badge.count(
                  count: stats.totalActive,
                  isLabelVisible: stats.totalActive > 0,
                  backgroundColor: ClearWashTheme.actionCobalt,
                  child: const Icon(Icons.local_car_wash_rounded),
                ),
                label: 'Antrian',
              ),
              const NavigationDestination(
                icon: Icon(Icons.assessment_outlined),
                selectedIcon: Icon(Icons.assessment_rounded),
                label: 'Shift',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
