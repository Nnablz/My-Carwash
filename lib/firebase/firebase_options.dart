import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Target Firebase environment selected via `--dart-define=APP_ENV=dev|prod`.
enum AppEnvironment {
  dev('DEV'),
  prod('PROD');

  const AppEnvironment(this.label);

  /// Uppercase short display label for diagnostics (`'DEV'` or `'PROD'`).
  final String label;

  /// Resolves the active environment from `APP_ENV` compile-time define.
  static AppEnvironment fromDefine() {
    const rawEnv = String.fromEnvironment('APP_ENV', defaultValue: 'dev');
    return switch (rawEnv.trim().toLowerCase()) {
      'prod' || 'production' => AppEnvironment.prod,
      _ => AppEnvironment.dev,
    };
  }
}

/// Default [FirebaseOptions] for use with ClearWash POS Firebase projects.
///
/// Example:
/// ```dart
/// import 'firebase/firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  /// Returns [FirebaseOptions] for the current platform and active [AppEnvironment].
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'you can reconfigure this by running the FlutterFire CLI again.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return forEnvironment(AppEnvironment.fromDefine());
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for '
          '${defaultTargetPlatform.name} - '
          'only Android is configured for ClearWash POS.',
        );
    }
  }

  /// Resolves Android [FirebaseOptions] for the specified [env].
  static FirebaseOptions forEnvironment(AppEnvironment env) {
    return switch (env) {
      AppEnvironment.dev => dev,
      AppEnvironment.prod => prod,
    };
  }

  /// Active Android [FirebaseOptions] resolved from [AppEnvironment.fromDefine].
  static FirebaseOptions get android =>
      forEnvironment(AppEnvironment.fromDefine());

  /// Development (`clearwash-pos-dev`) Firebase stub until `flutterfire configure`.
  static const FirebaseOptions dev = FirebaseOptions(
    apiKey: 'AIzaSyDummyKeyForDevelopmentBuildOnly00000',
    appId: '1:123456789000:android:0000000000000000000000',
    messagingSenderId: '123456789000',
    projectId: 'clearwash-pos-dev',
    storageBucket: 'clearwash-pos-dev.firebasestorage.app',
  );

  /// Production (`clearwash-pos-prod`) Firebase stub until `flutterfire configure`.
  static const FirebaseOptions prod = FirebaseOptions(
    apiKey: 'AIzaSyDummyKeyForProductionBuildOnly000000',
    appId: '1:987654321000:android:0000000000000000000000',
    messagingSenderId: '987654321000',
    projectId: 'clearwash-pos-prod',
    storageBucket: 'clearwash-pos-prod.firebasestorage.app',
  );
}
