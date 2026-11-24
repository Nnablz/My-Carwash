import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protein/di/providers.dart';
import 'package:protein/main.dart';
import 'package:protein/services/export_service.dart';
import 'package:qr_flutter/qr_flutter.dart';

Directory _createTempExportDir() {
  final baseTmp = Directory(r'd:\code\Protein\build\.tmp');
  if (!baseTmp.existsSync()) {
    baseTmp.createSync(recursive: true);
  }
  final dir = baseTmp.createTempSync('widget_export_');
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  return dir;
}

Future<void> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final exportDir = _createTempExportDir();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isFirebaseReadyProvider.overrideWithValue(false),
        exportServiceProvider.overrideWithValue(
          CsvExportService(directoryResolver: () async => exportDir.path),
        ),
      ],
      child: const ClearWashApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('ClearWash POS End-to-End Widget Tests', () {
    testWidgets(
      'Kasir cash registration: shows DEV • LOCAL, toggles Mobil/Motor, cascades brand/series/Lainnya, normalizes plate, processes cash payment, and opens receipt modal',
      (WidgetTester tester) async {
        await _pumpApp(tester);

        // Initial app bar & Kasir shell verification
        expect(find.text('Andi Wijaya'), findsOneWidget);
        expect(find.text('DEV • LOCAL'), findsOneWidget);
        expect(find.text('Tipe Kendaraan'), findsOneWidget);
        expect(find.text('Toyota'), findsOneWidget);
        expect(find.text('Agya'), findsOneWidget);
        expect(find.text('Cuci Mobil Kecil'), findsOneWidget);

        // Toggle Motor / Mobil and verify catalog + package updates
        await _tapVisible(tester, find.text('Motor'));
        expect(find.text('Honda'), findsOneWidget);
        expect(find.text('Beat'), findsOneWidget);
        expect(find.text('Cuci Motor Kecil'), findsOneWidget);
        expect(find.text('Cuci Motor Sedang'), findsOneWidget);
        expect(find.text('Cuci Motor Besar'), findsOneWidget);

        await _tapVisible(tester, find.text('Mobil'));
        expect(find.text('Cuci Mobil Kecil'), findsOneWidget);
        expect(find.text('Cuci Mobil Sedang'), findsOneWidget);
        expect(find.text('Cuci Mobil Besar'), findsOneWidget);

        // Select Fortuner from Seri / Model dropdown -> O(1) auto-selects Besar (Rp 100.000)
        await _tapVisible(
          tester,
          find.byKey(const ValueKey('series_mobil_Toyota_Agya')),
        );
        await _tapVisible(tester, find.text('Fortuner').last);
        expect(find.text('Rp 100.000'), findsWidgets);

        // Select 'Lainnya' -> reveals custom 'Seri / Model Lainnya' TextField
        await _tapVisible(
          tester,
          find.byKey(const ValueKey('series_mobil_Toyota_Fortuner')),
        );
        await _tapVisible(tester, find.text('Lainnya').last);
        expect(find.text('Seri / Model Lainnya'), findsOneWidget);

        // Empty submission when custom series is selected shows inline validation error
        await tester.tap(find.text('Pilih Metode Pembayaran'));
        await tester.pumpAndSettle();
        expect(
          find.text('Lengkapi Seri / Model dan Plat Nomor kendaraan terlebih dahulu.'),
          findsOneWidget,
        );

        // Fill Seri / Model Lainnya and Nomor Polisi (stripped spaces + uppercased)
        final modelField = find.byType(TextField).at(0);
        final plateField = find.byType(TextField).at(1);
        await tester.ensureVisible(modelField);
        await tester.enterText(modelField, 'Avanza Veloz');
        await tester.ensureVisible(plateField);
        await tester.enterText(plateField, 'b 7777 cw');
        await tester.pumpAndSettle();

        expect(find.text('PREVIEW PLAT:'), findsOneWidget);
        expect(find.text('B7777CW'), findsNWidgets(2));

        // Open Payment Modal
        await tester.tap(find.text('Pilih Metode Pembayaran'));
        await tester.pumpAndSettle();

        expect(find.text('Tunai (Cash)'), findsOneWidget);
        expect(find.text('QRIS'), findsOneWidget);

        // Select Cash method & pay Rp 150.000 for Rp 100.000 large package
        await _tapVisible(tester, find.text('Tunai (Cash)'));
        expect(find.text('Pembayaran Tunai (Cash)'), findsOneWidget);

        await _tapVisible(tester, find.text('150rb'));
        expect(find.text('Kembalian'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text('Rp 50.000'),
          ),
          findsOneWidget,
        );

        await _tapVisible(tester, find.text('Konfirmasi & Cetak Tiket'));

        // Verify Receipt Modal
        expect(find.text('Tiket Berhasil Dicetak!'), findsOneWidget);
        expect(find.text('ANTRIAN #007'), findsOneWidget);
        expect(find.text('LUNAS'), findsOneWidget);
        expect(find.text('Toyota Avanza Veloz'), findsOneWidget);
        expect(find.text('B7777CW'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text('Rp 50.000'),
          ),
          findsOneWidget,
        );

        // Toggle 58mm thermal preview and finish registration
        await _tapVisible(tester, find.text('Preview 58mm'));
        expect(find.textContaining('CLEARWASH POS'), findsOneWidget);

        await _tapVisible(tester, find.text('Selesai & Registrasi Baru'));
        expect(find.text('Tiket Berhasil Dicetak!'), findsNothing);
        // Active queue badge updated from 4 to 5
        expect(find.text('5'), findsOneWidget);
      },
    );

    testWidgets(
      'Kasir QRIS flow: renders QrImageView and gates Cetak Tiket until Foto Bukti Pembayaran is attached',
      (WidgetTester tester) async {
        await _pumpApp(tester);

        // Switch to Motor and pick Vario 160 from catalog dropdown
        await _tapVisible(tester, find.text('Motor'));
        await _tapVisible(
          tester,
          find.byKey(const ValueKey('series_motor_Honda_Beat')),
        );
        await _tapVisible(tester, find.text('Vario 160').last);

        // Enter license plate (auto-uppercased & stripped of spaces)
        final plateField = find.byType(TextField).first;
        await tester.ensureVisible(plateField);
        await tester.enterText(plateField, 'b 5555 mtr');
        await tester.pumpAndSettle();
        expect(find.text('B5555MTR'), findsNWidgets(2));

        // Open Payment Modal and choose QRIS
        await tester.tap(find.text('Pilih Metode Pembayaran'));
        await tester.pumpAndSettle();
        await _tapVisible(tester, find.text('QRIS'));

        expect(find.text('Pembayaran QRIS'), findsOneWidget);
        expect(find.byType(QrImageView), findsOneWidget);
        expect(find.text('Menunggu Pembayaran Customer...'), findsOneWidget);

        // Cetak Tiket must be disabled before proof attachment
        final printButtonFinder = find.ancestor(
          of: find.text('Cetak Tiket'),
          matching: find.bySubtype<ButtonStyleButton>(),
        );
        expect(printButtonFinder, findsOneWidget);
        expect(
          tester.widget<ButtonStyleButton>(printButtonFinder).onPressed,
          isNull,
        );

        // Attach QRIS proof
        await _tapVisible(tester, find.text('Foto Bukti Pembayaran'));
        expect(find.text('Bukti Pembayaran Terlampir'), findsOneWidget);
        expect(find.text('Ganti'), findsOneWidget);
        expect(
          tester.widget<ButtonStyleButton>(printButtonFinder).onPressed,
          isNotNull,
        );

        // Submit QRIS order and verify Receipt Modal
        await _tapVisible(tester, find.text('Cetak Tiket'));
        expect(find.text('Tiket Berhasil Dicetak!'), findsOneWidget);
        expect(find.text('ANTRIAN #007'), findsOneWidget);
        expect(find.text('LUNAS'), findsOneWidget);
        expect(find.text('B5555MTR'), findsOneWidget);

        // Jump to Antrian directly from Receipt Modal
        await _tapVisible(tester, find.text('Lihat Antrian'));
        expect(find.text('5 KENDARAAN AKTIF'), findsOneWidget);
      },
    );

    testWidgets(
      'Antrian flow: filters queue, assigns bay, marks washing ready, hands over key, and jumps back to Kasir',
      (WidgetTester tester) async {
        await _pumpApp(tester);

        // Navigate to Antrian tab
        await tester.tap(find.text('Antrian'));
        await tester.pumpAndSettle();

        expect(find.text('4 KENDARAAN AKTIF'), findsOneWidget);
        expect(find.text('DAFTAR ANTRIAN (SEMUA)'), findsOneWidget);
        expect(find.text('4 Unit'), findsOneWidget);

        // Switch through all filter chips
        await _tapVisible(tester, find.text('Tunggu'));
        expect(find.text('DAFTAR ANTRIAN (TUNGGU)'), findsOneWidget);
        expect(find.text('1 Unit'), findsOneWidget);
        expect(find.text('D 1092 ABT'), findsOneWidget);

        await _tapVisible(tester, find.text('Cuci'));
        expect(find.text('DAFTAR ANTRIAN (CUCI)'), findsOneWidget);
        expect(find.text('2 Unit'), findsOneWidget);
        expect(find.text('B 2841 SKZ'), findsWidgets);
        // Second washing order (CW-005 / B 4992 KLA) is below the fold in SliverList
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -350));
        await tester.pumpAndSettle();
        expect(find.text('B 4992 KLA'), findsWidgets);
        // Scroll back to top so filter bar is visible
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 350));
        await tester.pumpAndSettle();

        await _tapVisible(tester, find.text('Siap'));
        expect(find.text('DAFTAR ANTRIAN (SIAP)'), findsOneWidget);
        expect(find.text('1 Unit'), findsOneWidget);
        expect(find.text('B 8831 ZXP'), findsOneWidget);

        await _tapVisible(tester, find.text('Semua'));
        expect(find.text('DAFTAR ANTRIAN (SEMUA)'), findsOneWidget);
        expect(find.text('4 Unit'), findsOneWidget);

        // Assign waiting vehicle (CW-006 / D 1092 ABT) to available BAY 03
        await _tapVisible(tester, find.text('Tunggu'));
        await _tapVisible(tester, find.text('MULAI CUCI - MASUKKAN KE BAY'));

        expect(find.text('ALOKASI BAY & OPERATOR'), findsOneWidget);
        expect(find.text('Mulai Cuci CW-006'), findsOneWidget);

        await _tapVisible(
          tester,
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.widgetWithText(ChoiceChip, 'BAY 03'),
          ),
        );
        await _tapVisible(
          tester,
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.widgetWithText(ChoiceChip, 'Asep'),
          ),
        );
        await _tapVisible(tester, find.text('Konfirmasi & Mulai Cuci'));

        expect(find.text('D 1092 ABT masuk ke BAY 03 (Asep).'), findsOneWidget);
        expect(find.text('0 Unit'), findsOneWidget);

        // Mark a washing vehicle ready
        await _tapVisible(tester, find.text('Cuci'));
        expect(find.text('3 Unit'), findsOneWidget);
        await _tapVisible(
          tester,
          find.text('SELESAI CUCI (KE FINISHING)').first,
        );
        expect(
          find.textContaining('selesai dicuci dan siap diambil.'),
          findsOneWidget,
        );
        expect(find.text('2 Unit'), findsOneWidget);

        // Hand over a ready vehicle's key
        await _tapVisible(tester, find.text('Siap'));
        expect(find.text('2 Unit'), findsOneWidget);
        await _tapVisible(
          tester,
          find.text('SERAHKAN KUNCI / AMBIL').first,
        );
        expect(
          find.textContaining('Serah terima kunci'),
          findsOneWidget,
        );
        expect(find.text('1 Unit'), findsOneWidget);

        // Allow the handover SnackBar to auto-dismiss before tapping the bottom CTA
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();

        // Tap INPUT KENDARAAN BARU to jump back to Kasir
        await _tapVisible(tester, find.text('INPUT KENDARAAN BARU'));
        expect(find.text('Tipe Kendaraan'), findsOneWidget);
        expect(find.text('Pilih Metode Pembayaran'), findsOneWidget);
      },
    );

    testWidgets(
      'Shift flow: exports CSV/Excel dialog, checks Samakan Saldo for MATCH, enters notes, closes shift with receipt modal, and reopens demo shift',
      (WidgetTester tester) async {
        await _pumpApp(tester);

        // Switch to Shift tab
        await tester.tap(find.text('Shift'));
        await tester.pumpAndSettle();

        expect(find.text('Andi Wijaya'), findsWidgets);
        expect(find.text('AKTIF'), findsOneWidget);
        expect(find.text('Rp 360.000'), findsOneWidget);
        expect(find.text('6 Unit'), findsOneWidget);
        expect(find.text('MATCH (Rp 0)'), findsOneWidget);

        // Export CSV / Excel & verify export dialog + Salin CSV
        String? copiedClipboardText;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (MethodCall call) async {
            if (call.method == 'Clipboard.setData') {
              copiedClipboardText =
                  (call.arguments as Map<Object?, Object?>)['text'] as String?;
            }
            return null;
          },
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          );
        });

        final exportButton = find.text('Export CSV / Excel');
        await tester.ensureVisible(exportButton);
        await tester.pumpAndSettle();
        await tester.tap(exportButton);
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (find.text('Export Laporan Excel / CSV').evaluate().isNotEmpty) {
            break;
          }
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
        }
        await tester.pumpAndSettle();

        expect(find.text('Export Laporan Excel / CSV'), findsOneWidget);
        expect(find.text('6 transaksi'), findsOneWidget);
        expect(
          find.text('UTF-8 BOM Excel-ready (siap dibuka langsung di Microsoft Excel)'),
          findsOneWidget,
        );
        expect(find.text('PREVIEW CSV'), findsOneWidget);
        expect(find.text('Salin CSV'), findsOneWidget);

        await tester.tap(find.text('Salin CSV'));
        await tester.pumpAndSettle();
        expect(find.text('CSV Disalin'), findsOneWidget);
        expect(
          copiedClipboardText,
          startsWith(CsvExportService.utf8Bom),
        );
        expect(
          copiedClipboardText,
          contains('LAPORAN TRANSAKSI SHIFT CLEARWASH POS'),
        );
        expect(
          find.text('Isi CSV berhasil disalin ke clipboard.'),
          findsOneWidget,
        );

        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Tutup'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Export Laporan Excel / CSV'), findsNothing);

        // Introduce discrepancy, then tap Samakan Saldo to restore MATCH
        final cashCountField = find.byType(TextField).at(0);
        await tester.ensureVisible(cashCountField);
        await tester.pumpAndSettle();
        await tester.enterText(cashCountField, '300000');
        await tester.pumpAndSettle();
        expect(find.text('SELISIH -Rp 55.000'), findsOneWidget);

        await _tapVisible(tester, find.text('Samakan Saldo'));
        expect(find.text('MATCH (Rp 0)'), findsOneWidget);

        // Enter supervisor notes
        final notesField = find.byType(TextField).at(1);
        await tester.ensureVisible(notesField);
        await tester.pumpAndSettle();
        await tester.enterText(
          notesField,
          'Kas laci cocok dan semua unit terdata.',
        );
        await tester.pumpAndSettle();

        // Close shift and confirm dialog
        await _tapVisible(
          tester,
          find.text('TUTUP SHIFT & CETAK REKAPITULASI'),
        );
        expect(find.text('Tutup Shift & Cetak Rekap?'), findsOneWidget);
        await _tapVisible(tester, find.text('Ya, Tutup Shift'));

        // Verify shift closing receipt modal (showShiftReceiptModal)
        expect(find.text('Rekapitulasi Tutup Shift'), findsOneWidget);
        expect(find.text('MATCH'), findsOneWidget);
        expect(find.textContaining('LAPORAN TUTUP SHIFT'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.textContaining('Kas laci cocok dan semua unit'),
          ),
          findsOneWidget,
        );

        await _tapVisible(tester, find.text('Tutup'));
        expect(find.text('Rekapitulasi Tutup Shift'), findsNothing);

        // Closed shift UI state
        expect(find.text('TUTUP'), findsOneWidget);
        expect(find.text('Lihat Rekapitulasi Tutup Shift'), findsOneWidget);

        // Reopen demo shift
        await _tapVisible(tester, find.text('BUKA SHIFT BARU (DEMO)'));
        expect(
          find.text('Shift baru (demo) dibuka dan siap digunakan.'),
          findsOneWidget,
        );
        expect(find.text('AKTIF'), findsOneWidget);
        expect(find.text('Shift Berikutnya'), findsWidgets);
        expect(find.text('0 Unit'), findsNWidgets(3));
      },
    );

    testWidgets(
      'Cross-tab operational guards: cancels waiting order in Antrian and blocks/reopens Kasir when shift is closed',
      (WidgetTester tester) async {
        await _pumpApp(tester);

        // 1. Cancel waiting order CW-006 from Antrian
        await tester.tap(find.text('Antrian'));
        await tester.pumpAndSettle();
        await _tapVisible(tester, find.text('Tunggu'));
        expect(find.text('1 Unit'), findsOneWidget);

        await _tapVisible(tester, find.byIcon(Icons.close_rounded));
        expect(find.text('Batalkan Antrian?'), findsOneWidget);
        await _tapVisible(tester, find.text('Ya, Batalkan'));
        expect(find.text('Pesanan CW-006 dibatalkan.'), findsOneWidget);
        expect(find.text('0 Unit'), findsOneWidget);

        // 2. Close shift from Shift tab
        await tester.tap(find.text('Shift'));
        await tester.pumpAndSettle();
        await _tapVisible(
          tester,
          find.text('TUTUP SHIFT & CETAK REKAPITULASI'),
        );
        await _tapVisible(tester, find.text('Ya, Tutup Shift'));
        await _tapVisible(tester, find.text('Tutup'));

        // 3. Switch back to Kasir and verify locked banner + reopen from Kasir
        await tester.tap(find.text('Kasir'));
        await tester.pumpAndSettle();
        expect(find.text('Shift Kasir Sudah Ditutup'), findsOneWidget);

        final checkoutButton = find.ancestor(
          of: find.text('Pilih Metode Pembayaran'),
          matching: find.bySubtype<ButtonStyleButton>(),
        );
        expect(
          tester.widget<ButtonStyleButton>(checkoutButton).onPressed,
          isNull,
        );

        await _tapVisible(tester, find.text('Buka Shift Baru'));
        expect(
          find.text('Shift baru berhasil dibuka dan siap menerima transaksi.'),
          findsOneWidget,
        );
        expect(find.text('Shift Kasir Sudah Ditutup'), findsNothing);
        expect(
          tester.widget<ButtonStyleButton>(checkoutButton).onPressed,
          isNotNull,
        );
      },
    );
  });
}
