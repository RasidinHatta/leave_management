import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leave_management/screens/home_screen.dart';

void main() {
  testWidgets('settings palette cards do not overflow with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(
              textScaler: const TextScaler.linear(1.15),
            ),
            child: child!,
          );
        },
        home: HomeScreen(username: 'TEST', role: 'USER', onLogout: () {}),
      ),
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('COLOR THEME'), findsOneWidget);
    expect(find.text('Lavender dusk'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
