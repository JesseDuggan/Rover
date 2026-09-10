import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rover/src/active_roam/active_roam_repository.dart';
import 'package:rover/src/app.dart';
import 'package:rover/src/preferences/preferences_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('starts and completes a mock active ROAM', (tester) async {
    tester.view.physicalSize = const Size(430, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      RoverTestApp(
        preferencesRepository: MemoryPreferencesRepository(),
        activeRoamRepository: MemoryActiveRoamRepository(),
        initialLocation: '/home/active-roam',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Start demo ROAM'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Current stop: Union Square'), findsOneWidget);

    for (var index = 0; index < 5; index++) {
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Complete stop').first,
      );
      await tester.pumpAndSettle();
    }

    expect(find.textContaining('ROAM complete'), findsOneWidget);
  });
}
