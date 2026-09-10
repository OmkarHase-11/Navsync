import 'package:flutter/material.dart' hide NavigationMode;
import 'package:mobile/models/navigation_output.dart';
import 'package:mobile/theme/navsync_theme.dart';

/// Clean, dense Consumer Side Navigation Drawer
///
/// Features:
/// - Compact brand header with reduced vertical space
/// - Primary navigation destinations grouped in a rounded surface
/// - Compact NavSync AI-IDR technology card with subtle blue styling
/// - Live system-status card reflecting canonical NavigationOutput state
/// - Secondary navigation group (Settings, About)
/// - Integrated footer without excessive empty space
class NavSyncDrawer extends StatelessWidget {
  final NavigationOutput? navigationOutput;
  final VoidCallback? onSelectHome;
  final VoidCallback? onSelectProfile;
  final VoidCallback? onSelectNavigation;
  final VoidCallback? onSelectTrips;
  final VoidCallback? onSelectDeadReckoning;
  final VoidCallback? onSelectSettings;
  final VoidCallback? onSelectAbout;
  final VoidCallback? onSelectLogout;

  const NavSyncDrawer({
    super.key,
    this.navigationOutput,
    this.onSelectHome,
    this.onSelectProfile,
    this.onSelectNavigation,
    this.onSelectTrips,
    this.onSelectDeadReckoning,
    this.onSelectSettings,
    this.onSelectAbout,
    this.onSelectLogout,
  });

  @override
  Widget build(BuildContext context) {
    final isDeadReckoning =
        navigationOutput?.navigationMode == NavigationMode.deadReckoning;

    return Drawer(
      backgroundColor: NavSyncTheme.background,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // A. Compact Brand Header
              _buildCompactHeader(context),
              const SizedBox(height: 12),

              // B. Primary Navigation Group in one rounded surface
              Material(
                color: NavSyncTheme.surface,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: NavSyncTheme.cardBorder),
                  ),
                  child: Column(
                    children: [
                      _buildMenuItem(
                        icon: Icons.home_rounded,
                        title: 'Home',
                        onTap: () {
                          Navigator.pop(context);
                          onSelectHome?.call();
                        },
                        isSelected: true,
                      ),
                      const Divider(color: NavSyncTheme.divider, height: 1),
                      _buildMenuItem(
                        icon: Icons.person_outline_rounded,
                        title: 'My Profile',
                        subtitle: 'Account & preferences',
                        onTap: () {
                          Navigator.pop(context);
                          if (onSelectProfile != null) {
                            onSelectProfile!.call();
                          } else {
                            _showProfilePlaceholder(context);
                          }
                        },
                      ),
                      const Divider(color: NavSyncTheme.divider, height: 1),
                      _buildMenuItem(
                        icon: Icons.navigation_rounded,
                        title: 'Active Navigation',
                        onTap: () {
                          Navigator.pop(context);
                          onSelectNavigation?.call();
                        },
                      ),
                      const Divider(color: NavSyncTheme.divider, height: 1),
                      _buildMenuItem(
                        icon: Icons.history_rounded,
                        title: 'Trips & History',
                        subtitle: 'Past routes & saved places',
                        onTap: () {
                          Navigator.pop(context);
                          onSelectTrips?.call();
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // C. Compact NavSync Technology Card
              _buildTechnologyCard(context),
              const SizedBox(height: 12),

              // D. Compact System-Status Card
              _buildSystemStatusCard(isDeadReckoning),
              const SizedBox(height: 12),

              // E. Secondary Navigation Group in rounded surface
              Material(
                color: NavSyncTheme.surface,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: NavSyncTheme.cardBorder),
                  ),
                  child: Column(
                    children: [
                      _buildMenuItem(
                        icon: Icons.settings_outlined,
                        title: 'Settings',
                        onTap: () {
                          Navigator.pop(context);
                          onSelectSettings?.call();
                        },
                      ),
                      const Divider(color: NavSyncTheme.divider, height: 1),
                      _buildMenuItem(
                        icon: Icons.info_outline_rounded,
                        title: 'About NavSync',
                        onTap: () {
                          Navigator.pop(context);
                          onSelectAbout?.call();
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // F. Destructive Actions Group: Log Out
              Material(
                color: NavSyncTheme.surface,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: NavSyncTheme.cardBorder),
                  ),
                  child: _buildMenuItem(
                    icon: Icons.logout_rounded,
                    title: 'Log Out',
                    iconColor: const Color(0xFFFF5252),
                    textColor: const Color(0xFFFF8A80),
                    onTap: () {
                      Navigator.pop(context);
                      if (onSelectLogout != null) {
                        onSelectLogout!.call();
                      } else {
                        _showLogoutConfirmation(context);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // G. Compact Integrated Footer
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text(
                  'NavSync Mobile v1.0.0 • AI-IDR Engine\nGoogle Maps Platform',
                  style: NavSyncTheme.label.copyWith(
                    color: NavSyncTheme.tertiaryText,
                    fontSize: 10,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: NavSyncTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NavSyncTheme.cardBorder),
            ),
            child: const Center(
              child: Icon(
                Icons.navigation_rounded,
                color: NavSyncTheme.accent,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('NAVSYNC', style: NavSyncTheme.headingMedium),
                const SizedBox(height: 1),
                Text(
                  'Intelligent Dead Reckoning Navigation',
                  style: NavSyncTheme.label.copyWith(
                    color: NavSyncTheme.secondaryText,
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool isSelected = false,
    Color? iconColor,
    Color? textColor,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color:
            iconColor ??
            (isSelected ? NavSyncTheme.accent : NavSyncTheme.secondaryText),
        size: 20,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: textColor ?? NavSyncTheme.primaryText,
          fontSize: 13.5,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: const TextStyle(
                color: NavSyncTheme.tertiaryText,
                fontSize: 10.5,
              ),
            )
          : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      tileColor: isSelected
          ? NavSyncTheme.surfaceElevated.withValues(alpha: 0.7)
          : Colors.transparent,
      dense: true,
      onTap: onTap,
    );
  }

  Widget _buildTechnologyCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NavSyncTheme.idrCardBg.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NavSyncTheme.idrBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.radar_rounded,
                color: NavSyncTheme.idrBlueLight,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                'AI DEAD RECKONING',
                style: NavSyncTheme.label.copyWith(
                  color: NavSyncTheme.idrBlueLight,
                  fontWeight: FontWeight.w800,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Navigation continues through tunnels and GNSS-denied areas using onboard inertial estimation.',
            style: TextStyle(
              color: NavSyncTheme.secondaryText,
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemStatusCard(bool isDeadReckoning) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: NavSyncTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NavSyncTheme.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isDeadReckoning
                  ? NavSyncTheme.idrBlue
                  : NavSyncTheme.gnssGreen,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: isDeadReckoning
                      ? NavSyncTheme.idrBlueGlow
                      : NavSyncTheme.gnssGreenGlow,
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isDeadReckoning ? 'IDR active' : 'GNSS ready',
                  style: TextStyle(
                    color: isDeadReckoning
                        ? NavSyncTheme.idrBlueLight
                        : NavSyncTheme.gnssGreen,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                Text(
                  isDeadReckoning
                      ? 'Inertial Dead Reckoning engaged'
                      : 'Satellite positioning active',
                  style: const TextStyle(
                    color: NavSyncTheme.secondaryText,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showProfilePlaceholder(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: NavSyncTheme.surfaceElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: NavSyncTheme.cardBorder),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: NavSyncTheme.cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // Avatar placeholder
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: NavSyncTheme.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: NavSyncTheme.cardBorder),
                ),
                child: const Center(
                  child: Icon(
                    Icons.person_rounded,
                    size: 32,
                    color: NavSyncTheme.accent,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              const Text('My Profile', style: NavSyncTheme.headingMedium),
              const SizedBox(height: 8),

              const Text(
                'Profile details will be available when account integration is connected.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: NavSyncTheme.secondaryText,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NavSyncTheme.surface,
                    foregroundColor: NavSyncTheme.primaryText,
                    side: const BorderSide(color: NavSyncTheme.cardBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NavSyncTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Log out?',
          style: TextStyle(
            color: NavSyncTheme.primaryText,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'Account authentication is not connected in this version of NavSync.',
          style: TextStyle(
            color: NavSyncTheme.secondaryText,
            fontSize: 14,
            height: 1.35,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: NavSyncTheme.secondaryText),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'OK',
              style: TextStyle(
                color: Color(0xFFFF5252),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
