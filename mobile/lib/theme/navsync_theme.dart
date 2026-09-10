import 'package:flutter/material.dart';

/// Centralized Design System for NavSync
///
/// Aesthetic: Clean Modern Navigation (Google Maps-familiar) with
/// a premium dark navy foundation and signature NavSync burnt orange accents.
class NavSyncTheme {
  NavSyncTheme._();

  // ── Color Palette ─────────────────────────────────────────────────────────

  /// Deep slate/navy background
  static const Color background = Color(0xFF0B101A);

  /// Exact background ink for negative-space splash
  static const Color splashBackground = Color(0xFF0E1318);

  /// Floating card / sheet surface
  static const Color surface = Color(0xFF141C2B);

  /// Slightly elevated sub-surface
  static const Color surfaceElevated = Color(0xFF1A2436);

  /// Primary text - warm off-white
  static const Color primaryText = Color(0xFFF6F8FA);

  /// Secondary text - soft cool gray
  static const Color secondaryText = Color(0xFF8B9CB0);

  /// Subtle tertiary text / placeholders
  static const Color tertiaryText = Color(0xFF536477);

  /// Signature NavSync Accent - Burnt Orange
  static const Color accent = Color(0xFFE65100);

  /// Accent light / highlight
  static const Color accentLight = Color(0xFFFF7D47);

  /// Navigation maneuver / progress green (familiar Google Maps color)
  static const Color maneuverGreen = Color(0xFF00A86B);

  /// Alert / warning state
  static const Color warning = Color(0xFFD85A20);

  /// Semantic GNSS active green
  static const Color gnssGreen = Color(0xFF00C853);
  static const Color gnssGreenLight = Color(0xFF69F0AE);
  static const Color gnssGreenGlow = Color(0x3300C853);

  /// GNSS restored transient notification background (light green) and text (dark navy)
  static const Color gnssNotificationBg = Color(0xFFE8F5E9);
  static const Color gnssNotificationText = Color(0xFF0A2E16);
  static const Color gnssNotificationBorder = Color(0xFFA5D6A7);

  /// Semantic Dead Reckoning / IDR active blue (distinctive, calm, not orange)
  static const Color idrBlue = Color(0xFF2979FF);
  static const Color idrBlueLight = Color(0xFF82B1FF);
  static const Color idrBlueGlow = Color(0x332979FF);

  /// IDR active card background and subtle border
  static const Color idrCardBg = Color(0xFF0F1B2D);
  static const Color idrBorder = Color(0xFF1E3C66);

  /// IDR transition notification background (light blue) and text (dark navy)
  static const Color idrNotificationBg = Color(0xFFE3F2FD);
  static const Color idrNotificationText = Color(0xFF0D253F);
  static const Color idrNotificationBorder = Color(0xFF90CAF9);

  /// Subtle card border
  static const Color cardBorder = Color(0xFF233045);

  /// Subtle divider line
  static const Color divider = Color(0xFF1E293B);

  // ── Corner Radii ──────────────────────────────────────────────────────────
  static const double radiusMajorCard = 24.0;
  static const double radiusStatusPill = 20.0;
  static const double radiusButton = 18.0;
  static const double radiusChip = 18.0;
  static const double radiusMenuItem = 16.0;

  // ── Typography ────────────────────────────────────────────────────────────

  /// Clean, readable headline style
  static const TextStyle headingLarge = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: primaryText,
    letterSpacing: -0.2,
  );

  /// App bar / title style
  static const TextStyle headingMedium = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: primaryText,
    letterSpacing: 0.2,
  );

  /// Turn maneuver instruction (bold, large, legible while driving)
  static const TextStyle maneuverInstruction = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: primaryText,
    letterSpacing: -0.1,
    height: 1.2,
  );

  /// Maneuver distance (e.g. "500 m")
  static const TextStyle maneuverDistance = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: accentLight,
  );

  /// Trip duration readout (e.g. "12 min")
  static const TextStyle tripDuration = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    color: primaryText,
    letterSpacing: -0.3,
  );

  /// Trip secondary stats (distance, ETA)
  static const TextStyle tripSubtext = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: secondaryText,
  );

  /// Speed display
  static const TextStyle speedValue = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    color: primaryText,
  );

  /// Standard label
  static const TextStyle label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: secondaryText,
    letterSpacing: 0.5,
  );

  /// Button text
  static const TextStyle button = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    letterSpacing: 0.5,
  );

  // ── Card & Surface Styling ────────────────────────────────────────────────

  /// Modern floating navigation card decoration
  static BoxDecoration floatingCard({
    Color? color,
    Color? borderColor,
    double? borderRadius,
  }) {
    return BoxDecoration(
      color: color ?? surface,
      borderRadius: BorderRadius.circular(borderRadius ?? radiusMajorCard),
      border: Border.all(color: borderColor ?? cardBorder, width: 1.0),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.35),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  /// Turn-by-turn guidance banner card decoration
  static BoxDecoration guidanceCard({bool isDeadReckoning = false}) {
    return BoxDecoration(
      color: isDeadReckoning ? idrCardBg : surface,
      borderRadius: BorderRadius.circular(radiusMajorCard),
      border: Border.all(
        color: isDeadReckoning ? idrBlue : cardBorder,
        width: isDeadReckoning ? 1.5 : 1.0,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.4),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  // ── Dark Google Maps Styling JSON ─────────────────────────────────────────

  /// Premium dark navigation map theme for Google Maps SDK
  static const String darkMapStyle = '''
[
  {
    "elementType": "geometry",
    "stylers": [{"color": "#121926"}]
  },
  {
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#8b9cb0"}]
  },
  {
    "elementType": "labels.text.stroke",
    "stylers": [{"color": "#121926"}]
  },
  {
    "featureType": "administrative.locality",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#f6f8fa"}]
  },
  {
    "featureType": "poi",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#627387"}]
  },
  {
    "featureType": "poi.park",
    "elementType": "geometry",
    "stylers": [{"color": "#16232d"}]
  },
  {
    "featureType": "road",
    "elementType": "geometry",
    "stylers": [{"color": "#1e293b"}]
  },
  {
    "featureType": "road",
    "elementType": "geometry.stroke",
    "stylers": [{"color": "#0d131f"}]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry",
    "stylers": [{"color": "#2c3b52"}]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry.stroke",
    "stylers": [{"color": "#1a2436"}]
  },
  {
    "featureType": "transit",
    "elementType": "geometry",
    "stylers": [{"color": "#192233"}]
  },
  {
    "featureType": "water",
    "elementType": "geometry",
    "stylers": [{"color": "#0a0e17"}]
  }
]
''';
}
