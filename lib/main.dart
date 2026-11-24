import 'package:cloud_firestore/cloud_firestore.dart'
    show FirebaseFirestore, Settings;
import 'package:firebase_core/firebase_core.dart' show Firebase;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'di/providers.dart';
import 'firebase/firebase_options.dart';
import 'screens/home_screen.dart';
import 'theme/clearwash_theme.dart';

/// Bootstrap entrypoint initializing Firebase for the active [AppEnvironment]
/// when live credentials exist, falling back cleanly to demo mode otherwise.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final appEnv = AppEnvironment.fromDefine();
  final firebaseReady = await _bootstrapFirebase(appEnv);

  runApp(
    ProviderScope(
      overrides: [
        appEnvironmentProvider.overrideWithValue(appEnv),
        isFirebaseReadyProvider.overrideWithValue(firebaseReady),
      ],
      child: const ClearWashApp(),
    ),
  );
}

Future<bool> _bootstrapFirebase(AppEnvironment appEnv) async {
  try {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    final options = DefaultFirebaseOptions.forEnvironment(appEnv);
    if (options.apiKey.startsWith('AIzaSyDummyKey')) {
      return false;
    }
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: options);
    }
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );
    return true;
  } catch (_) {
    return false;
  }
}

/// Root widget for the ClearWash POS application.
class ClearWashApp extends StatelessWidget {
  const ClearWashApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: ClearWashTheme.actionCobalt,
      primary: ClearWashTheme.actionCobalt,
      secondary: ClearWashTheme.slateInk,
      surface: Colors.white,
    );

    return MaterialApp(
      title: 'ClearWash POS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: ClearWashTheme.canvas,
        splashFactory: InkSparkle.splashFactory,
        appBarTheme: const AppBarTheme(
          backgroundColor: ClearWashTheme.surfaceCard,
          foregroundColor: ClearWashTheme.slateInk,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: ClearWashTheme.surfaceCard,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(
              color: ClearWashTheme.borderHairline,
              width: 0.8,
            ),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: ClearWashTheme.surfaceCard,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: ClearWashTheme.slateInk,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF9F9FB),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: ClearWashTheme.borderHairline,
              width: 0.9,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: ClearWashTheme.borderHairline,
              width: 0.9,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: ClearWashTheme.actionCobalt,
              width: 1.6,
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: ClearWashTheme.actionCobalt,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 50),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: ClearWashTheme.actionCobalt,
            minimumSize: const Size(0, 48),
            side: const BorderSide(
              color: ClearWashTheme.borderSlate,
              width: 0.9,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: ClearWashTheme.borderHairline,
          thickness: 0.7,
          space: 1,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
