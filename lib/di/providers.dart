import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Contract for an abstract repository / service in this base app.
abstract interface class AppRepository {
  Future<String> fetchAppTitle();
  Stream<int> watchCounter();
  void incrementCounter();
}

/// In-memory implementation of [AppRepository].
class InMemoryAppRepository implements AppRepository {
  int _counter = 0;
  final _streamController = StreamController<int>.broadcast();

  @override
  Future<String> fetchAppTitle() async => 'Base Flutter App';

  @override
  Stream<int> watchCounter() async* {
    yield _counter;
    yield* _streamController.stream;
  }

  @override
  void incrementCounter() {
    _counter++;
    _streamController.add(_counter);
  }
}

// ---------------------------------------------------------------------------
// Dependency Injection Container via Riverpod Providers
// ---------------------------------------------------------------------------

/// Dependency Injection provider for [AppRepository].
/// Can be overridden in `ProviderScope(overrides: [...])` for testing or production.
final appRepositoryProvider = Provider<AppRepository>((ref) {
  return InMemoryAppRepository();
});

/// Async provider resolving app title from the injected repository.
final appTitleProvider = FutureProvider<String>((ref) {
  final repo = ref.watch(appRepositoryProvider);
  return repo.fetchAppTitle();
});

/// Stream provider listening to counter changes from the injected repository.
final counterStreamProvider = StreamProvider<int>((ref) {
  final repo = ref.watch(appRepositoryProvider);
  return repo.watchCounter();
});
