import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/navigation_screen.dart';
import 'package:mobile/screens/splash_screen.dart';
import 'package:mobile/theme/navsync_theme.dart';

void main() {
  group('SplashScreen Widget Tests', () {
    testWidgets(
      'renders full-screen negative-space splash image with BoxFit.cover and without duplicate overlays',
      (WidgetTester tester) async {
        await tester.pumpWidget(const MaterialApp(home: SplashScreen()));

        // Verify Image.asset is present and configured with BoxFit.cover
        final imageFinder = find.byType(Image);
        expect(imageFinder, findsOneWidget);

        final Image imageWidget = tester.widget<Image>(imageFinder);
        expect(imageWidget.image, isA<AssetImage>());
        final AssetImage assetImage = imageWidget.image as AssetImage;
        expect(assetImage.assetName, equals('assets/images/splash_screen.png'));
        expect(imageWidget.fit, equals(BoxFit.cover));

        // Verify Scaffold has the exact background matching the splash asset ink
        final scaffoldFinder = find.byType(Scaffold);
        expect(scaffoldFinder, findsOneWidget);
        final Scaffold scaffold = tester.widget<Scaffold>(scaffoldFinder);
        expect(scaffold.backgroundColor, equals(NavSyncTheme.splashBackground));

        // Verify no duplicate text or logo widgets are overlaid on top of the image
        expect(find.byType(Text), findsNothing);
        expect(find.text('NAVSYNC'), findsNothing);
        expect(find.text('by CTRL Freaks'), findsNothing);

        // Verify transition to NavigationScreen after 2000ms + fade
        await tester.pump(const Duration(milliseconds: 2000));
        await tester.pumpAndSettle();

        expect(find.byType(NavigationScreen), findsOneWidget);
      },
    );
  });
}
