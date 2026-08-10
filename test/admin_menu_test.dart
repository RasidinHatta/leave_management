import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leave_management/core/constants.dart';
import 'package:leave_management/screens/home_screen.dart';

void main() {
  tearDown(() => kAdminMenuEnabled = false);

  void useDesktopSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('Admin=1 shows configured admin menus for a USER role', (
    tester,
  ) async {
    useDesktopSurface(tester);
    kAdminMenuEnabled = true;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(username: 'TEST', role: 'USER', onLogout: () {}),
      ),
    );

    expect(find.text('Leave Report Config'), findsOneWidget);
    expect(find.text('Manage Users'), findsOneWidget);
    expect(find.text('BF / Credit Leave'), findsOneWidget);
    expect(find.text('Bring Forward & Credit Leave'), findsOneWidget);
  });

  testWidgets('missing Admin=1 hides configured menus for a USER role', (
    tester,
  ) async {
    useDesktopSurface(tester);
    kAdminMenuEnabled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(username: 'TEST', role: 'USER', onLogout: () {}),
      ),
    );

    expect(find.text('Leave Report Config'), findsNothing);
    expect(find.text('Manage Users'), findsNothing);
  });

  testWidgets('missing Admin=1 also hides configured menus for ADMIN role', (
    tester,
  ) async {
    useDesktopSurface(tester);
    kAdminMenuEnabled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(username: 'SUPER', role: 'ADMIN', onLogout: () {}),
      ),
    );

    expect(find.text('DB Targets'), findsOneWidget);
    expect(find.text('Leave Report Config'), findsNothing);
    expect(find.text('Manage Users'), findsNothing);
  });
}
