import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/theme/navsync_theme.dart';

void main() {
  testWidgets(
    'NavSync consumer navigation launch, guidance, and Dead Reckoning test',
    (WidgetTester tester) async {
      // 1. Launch the app (begins on SplashScreen)
      await tester.pumpWidget(const NavSyncApp());

      // Verify initial splash state
      expect(find.text('Where do you want to go?'), findsNothing);

      // 2. Advance past 2-second splash timer and fade animation
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // 3. Verify Pre-Navigation elements: Search bar, Start button, & Dedicated Status Pill
      expect(find.text('Where do you want to go?'), findsOneWidget);
      expect(find.text('START'), findsOneWidget);
      expect(find.text('Pune Central Railway Station'), findsOneWidget);

      // Verify dedicated status chip displays GNSS ACTIVE in green and has compact intrinsic width
      final gnssTextFinder = find.text('GNSS ACTIVE');
      expect(gnssTextFinder, findsOneWidget);
      final Text gnssTextWidget = tester.widget<Text>(gnssTextFinder);
      expect(gnssTextWidget.style?.color, equals(NavSyncTheme.gnssGreen));

      final statusChipFinder = find.byKey(
        const ValueKey('navigation_status_pill'),
      );
      final chipSize = tester.getSize(statusChipFinder);
      expect(
        chipSize.width,
        lessThan(200.0),
      ); // Intrinsic/compact, not full-width
      expect(find.text('GNSS + INS navigation'), findsNothing);

      // 4. Test opening the side navigation drawer with GNSS active
      tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await tester.pumpAndSettle();

      expect(find.text('NAVSYNC'), findsOneWidget);
      expect(find.text('My Profile'), findsOneWidget);
      expect(find.text('Trips & History'), findsOneWidget);
      expect(find.text('AI DEAD RECKONING'), findsOneWidget);
      expect(find.text('Log Out'), findsOneWidget);
      // Drawer shows backend-neutral GNSS ready state
      expect(find.text('GNSS ready'), findsOneWidget);
      expect(find.text('Satellite positioning active'), findsOneWidget);

      // Close drawer
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();

      // 5. Start Navigation
      await tester.tap(find.text('START'));
      await tester.pump(const Duration(milliseconds: 100));

      // Guidance card should be visible
      expect(find.text('Head south on Shivaji Nagar Blvd'), findsOneWidget);
      expect(find.text('GNSS ACTIVE'), findsOneWidget);

      // Verify refined compact bottom card contains ETA, duration/distance, and speed tile
      expect(find.text('ETA'), findsOneWidget);
      expect(find.textContaining('min'), findsWidgets);
      expect(find.textContaining('km remaining'), findsOneWidget);
      expect(find.text('km/h'), findsOneWidget);

      // 6. Test GNSS Signal Loss transition (Dead Reckoning active)
      await tester.tap(find.text('GNSS ACTIVE'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify status chip transitions to IDR ACTIVE in blue
      final drTextFinder = find.text('IDR ACTIVE');
      expect(drTextFinder, findsOneWidget);
      final Text drTextWidget = tester.widget<Text>(drTextFinder);
      expect(drTextWidget.style?.color, equals(NavSyncTheme.idrBlueLight));
      expect(find.text('Position estimated by NavSync IDR'), findsNothing);

      // Verify top transient in-app notification appears
      expect(find.text('GNSS signal lost'), findsOneWidget);
      expect(find.text('NavSync IDR is continuing navigation'), findsOneWidget);

      // Verify drawer now shows IDR active
      tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await tester.pumpAndSettle();
      expect(find.text('IDR active'), findsOneWidget);
      expect(find.text('Inertial Dead Reckoning engaged'), findsOneWidget);

      // Close drawer
      final navigator2 = tester.state<NavigatorState>(find.byType(Navigator));
      navigator2.pop();
      await tester.pumpAndSettle();

      // 7. Test GNSS Signal Restoration by tapping the status indicator
      await tester.tap(statusChipFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify status chip transitions back to GNSS ACTIVE
      expect(find.text('GNSS ACTIVE'), findsOneWidget);

      // Verify restoration notification
      expect(find.text('GNSS restored'), findsOneWidget);
      expect(find.text('GNSS + INS navigation resumed'), findsOneWidget);

      // 8. Test repeated toggling does not throw or crash
      for (int i = 0; i < 6; i++) {
        await tester.tap(statusChipFinder);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 250));

      // 9. End Navigation
      await tester.tap(find.byKey(const ValueKey('stop_navigation_button')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('START'), findsOneWidget);
    },
  );
}
