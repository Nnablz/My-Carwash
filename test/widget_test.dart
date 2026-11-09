import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protein/main.dart';

void main() {
  testWidgets(
    'MyApp renders HomeScreen inside ProviderScope and increments counter',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MyApp(),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Base Flutter App'), findsOneWidget);
      expect(find.text('Riverpod Dependency Injection'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
    },
  );
}
