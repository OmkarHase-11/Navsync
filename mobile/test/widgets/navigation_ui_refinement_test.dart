import 'package:flutter/material.dart' hide NavigationMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/models/navigation_output.dart';
import 'package:mobile/theme/navsync_theme.dart';
import 'package:mobile/widgets/navigation_drawer.dart';

void main() {
  group('NavSyncDrawer Widget Unit Tests', () {
    testWidgets(
      'displays green GNSS ready state when NavigationMode is gnssIns',
      (WidgetTester tester) async {
        final gnssOutput = NavigationOutput(
          timestamp: 1725552000000,
          latitude: 18.5204,
          longitude: 73.8567,
          speedMps: 10.0,
          heading: 90.0,
          navigationMode: NavigationMode.gnssIns,
          gnssStatus: GnssStatus.available,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              drawer: NavSyncDrawer(navigationOutput: gnssOutput),
              body: const SizedBox.shrink(),
            ),
          ),
        );

        tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
        await tester.pumpAndSettle();

        expect(find.text('NAVSYNC'), findsOneWidget);
        expect(find.text('My Profile'), findsOneWidget);
        expect(find.text('AI DEAD RECKONING'), findsOneWidget);
        expect(find.text('Log Out'), findsOneWidget);
        expect(
          find.text(
            'Navigation continues through tunnels and GNSS-denied areas using onboard inertial estimation.',
          ),
          findsOneWidget,
        );
        expect(find.text('GNSS ready'), findsOneWidget);
        expect(find.text('Satellite positioning active'), findsOneWidget);
        expect(find.text('IDR active'), findsNothing);

        // Verify color of GNSS ready text
        final Text statusText = tester.widget<Text>(find.text('GNSS ready'));
        expect(statusText.style?.color, equals(NavSyncTheme.gnssGreen));
      },
    );

    testWidgets(
      'displays blue IDR active state when NavigationMode is deadReckoning',
      (WidgetTester tester) async {
        final drOutput = NavigationOutput(
          timestamp: 1725552000000,
          latitude: 18.5204,
          longitude: 73.8567,
          speedMps: 8.0,
          heading: 180.0,
          navigationMode: NavigationMode.deadReckoning,
          gnssStatus: GnssStatus.unavailable,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              drawer: NavSyncDrawer(navigationOutput: drOutput),
              body: const SizedBox.shrink(),
            ),
          ),
        );

        tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
        await tester.pumpAndSettle();

        expect(find.text('IDR active'), findsOneWidget);
        expect(find.text('Inertial Dead Reckoning engaged'), findsOneWidget);
        expect(find.text('GNSS ready'), findsNothing);

        // Verify color of IDR active text
        final Text statusText = tester.widget<Text>(find.text('IDR active'));
        expect(statusText.style?.color, equals(NavSyncTheme.idrBlueLight));
      },
    );

    testWidgets(
      'tapping My Profile opens polished placeholder sheet and dismisses cleanly',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(drawer: NavSyncDrawer(), body: SizedBox.shrink()),
          ),
        );

        tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
        await tester.pumpAndSettle();

        final profileItem = find.text('My Profile');
        expect(profileItem, findsOneWidget);
        await tester.tap(profileItem);
        await tester.pumpAndSettle();

        // Drawer closed, placeholder sheet opened
        expect(
          find.text(
            'Profile details will be available when account integration is connected.',
          ),
          findsOneWidget,
        );
        expect(find.text('Close'), findsOneWidget);

        // Tap Close button
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Profile details will be available when account integration is connected.',
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'tapping Log Out opens confirmation dialog and Cancel/OK dismiss safely',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(drawer: NavSyncDrawer(), body: SizedBox.shrink()),
          ),
        );

        // Test Cancel dismissal
        tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
        await tester.pumpAndSettle();

        final logoutItem = find.text('Log Out');
        expect(logoutItem, findsOneWidget);
        await tester.ensureVisible(logoutItem);
        await tester.pumpAndSettle();
        await tester.tap(logoutItem);
        await tester.pumpAndSettle();

        expect(find.text('Log out?'), findsOneWidget);
        expect(
          find.text(
            'Account authentication is not connected in this version of NavSync.',
          ),
          findsOneWidget,
        );
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('OK'), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(find.text('Log out?'), findsNothing);

        // Test OK dismissal
        tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Log Out'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Log Out'));
        await tester.pumpAndSettle();

        expect(find.text('Log out?'), findsOneWidget);
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        expect(find.text('Log out?'), findsNothing);
      },
    );
  });

  group('NavigationScreen UI Refinement Integration Tests', () {
    Future<void> pumpAndAdvancePastSplash(WidgetTester tester) async {
      await tester.pumpWidget(const NavSyncApp());
      await tester.pumpAndSettle(const Duration(seconds: 3));
    }

    testWidgets(
      'GNSS status chip displays GNSS ACTIVE (green) and IDR ACTIVE (blue) with compact width',
      (WidgetTester tester) async {
        await pumpAndAdvancePastSplash(tester);

        // Pre-navigation dedicated status chip exists
        final chipFinder = find.byKey(const ValueKey('navigation_status_pill'));
        expect(chipFinder, findsOneWidget);

        // Compact intrinsic width (less than half screen width)
        final chipSize = tester.getSize(chipFinder);
        expect(chipSize.width, lessThan(200.0));

        // GNSS Active is shown in green
        final gnssLabel = find.text('GNSS ACTIVE');
        expect(gnssLabel, findsOneWidget);
        final Text gnssWidget = tester.widget<Text>(gnssLabel);
        expect(gnssWidget.style?.color, equals(NavSyncTheme.gnssGreen));

        // Secondary text is removed from chip
        expect(find.text('GNSS + INS navigation'), findsNothing);
        expect(find.text('Position estimated by NavSync IDR'), findsNothing);

        // Start Navigation
        await tester.tap(find.text('START'));
        await tester.pump(const Duration(milliseconds: 100));

        // Status is NOT duplicated in bottom card (only in corner chip)
        expect(find.text('GNSS ACTIVE'), findsOneWidget);

        // Toggle to Dead Reckoning
        await tester.tap(chipFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Dead Reckoning Active is shown in blue as IDR ACTIVE
        final drLabel = find.text('IDR ACTIVE');
        expect(drLabel, findsOneWidget);
        final Text drWidget = tester.widget<Text>(drLabel);
        expect(drWidget.style?.color, equals(NavSyncTheme.idrBlueLight));
        expect(
          drWidget.style?.color,
          isNot(equals(NavSyncTheme.accent)),
        ); // NOT burnt orange

        // Secondary text remains absent
        expect(find.text('Position estimated by NavSync IDR'), findsNothing);
      },
    );

    testWidgets(
      'GNSS-to-IDR transition notification and IDR-to-GNSS restoration notification content',
      (WidgetTester tester) async {
        await pumpAndAdvancePastSplash(tester);

        await tester.tap(find.text('START'));
        await tester.pump(const Duration(milliseconds: 100));

        final chipFinder = find.byKey(const ValueKey('navigation_status_pill'));

        // Toggle GNSS loss
        await tester.tap(chipFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Verify transition notification
        expect(find.text('GNSS signal lost'), findsOneWidget);
        expect(
          find.text('NavSync IDR is continuing navigation'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.sensors_off_rounded), findsOneWidget);

        // Verify chip and notification positions do NOT overlap
        final chipRect = tester.getRect(chipFinder);
        final notifFinder = find.byKey(const ValueKey('notif_1'));
        final notifRect = tester.getRect(notifFinder);
        expect(notifRect.top, greaterThanOrEqualTo(chipRect.bottom));

        // Toggle GNSS restored
        await tester.tap(chipFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Verify restoration notification
        expect(find.text('GNSS restored'), findsOneWidget);
        expect(find.text('GNSS + INS navigation resumed'), findsOneWidget);
        expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

        // Test dismissing notification via its close button
        final dismissBtn = find.descendant(
          of: find.byType(IconButton),
          matching: find.byIcon(Icons.close_rounded),
        );
        expect(dismissBtn, findsOneWidget);
        await tester.tap(dismissBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Notification is dismissed
        expect(find.text('GNSS restored'), findsNothing);
      },
    );

    testWidgets('Repeated toggling does not throw or crash', (
      WidgetTester tester,
    ) async {
      await pumpAndAdvancePastSplash(tester);

      await tester.tap(find.text('START'));
      await tester.pump(const Duration(milliseconds: 100));

      final chipFinder = find.byKey(const ValueKey('navigation_status_pill'));

      for (int i = 0; i < 10; i++) {
        await tester.tap(chipFinder);
        await tester.pump(const Duration(milliseconds: 80));
      }

      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Active-navigation bottom card displays ETA label, arrival time, duration, distance, speed tile, and renders without overflow on narrow screens',
      (WidgetTester tester) async {
        // Test on narrow screen width (320 logical pixels width like iPhone 5/SE1)
        tester.view.physicalSize = const Size(320 * 2, 600 * 2);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await pumpAndAdvancePastSplash(tester);

        await tester.tap(find.text('START'));
        await tester.pump(const Duration(milliseconds: 100));

        // 1. Arrival time is displayed with ETA label
        expect(find.text('ETA'), findsOneWidget);
        final etaLabelWidget = tester.widget<Text>(find.text('ETA'));
        expect(etaLabelWidget.style?.color, equals(NavSyncTheme.maneuverGreen));

        // 2. Remaining distance and duration line is displayed
        expect(find.textContaining('min'), findsWidgets);
        expect(find.textContaining('km remaining'), findsOneWidget);

        // 3. Speed tile displays numeric speed and km/h unit
        expect(find.text('km/h'), findsOneWidget);

        // 4. Stop button has semantics and functions properly
        final stopButtonFinder = find.byKey(
          const ValueKey('stop_navigation_button'),
        );
        expect(stopButtonFinder, findsOneWidget);
        await tester.tap(stopButtonFinder);
        await tester.pump(const Duration(milliseconds: 100));

        // Returns to pre-navigation START view
        expect(find.text('START'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
