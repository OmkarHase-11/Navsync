import 'dart:async';

import 'package:flutter/material.dart' hide NavigationMode;
import 'package:mobile/controllers/sensor_runtime_controller.dart';
import 'package:mobile/models/navigation_output.dart';
import 'package:mobile/models/navigation_state.dart';
import 'package:mobile/navigation/integration/navigation_pipeline.dart';
import 'package:mobile/theme/navsync_theme.dart';
import 'package:mobile/widgets/navigation_drawer.dart';
import 'package:mobile/widgets/navigation_map.dart';

/// Main Consumer Navigation Screen
///
/// Features:
/// - Full-screen Google Map as the centerpiece
/// - Seamless transition from Destination Search to Active Navigation
/// - Turn-by-turn guidance header card
/// - Subtle, impressive AI Dead Reckoning alert and visual transition
/// - Google Maps-familiar bottom navigation card with ETA, distance, and speed
/// - Clean side drawer menu with Real Sensor Readiness status
class NavigationScreen extends StatefulWidget {
  final SensorRuntimeController? sensorController;

  /// Null preserves the demo. Supplied pipelines require a real host adapter.
  final NavigationPipeline? navigationPipeline;

  const NavigationScreen({
    super.key,
    this.sensorController,
    this.navigationPipeline,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _InAppNotification {
  final Key key;
  final bool isGnssLost;
  final String title;
  final String message;
  final IconData icon;
  final Color backgroundColor;
  final Color textColor;
  final Color iconColor;
  final Color borderColor;

  const _InAppNotification({
    required this.key,
    required this.isGnssLost,
    required this.title,
    required this.message,
    required this.icon,
    required this.backgroundColor,
    required this.textColor,
    required this.iconColor,
    required this.borderColor,
  });
}

class _NavigationScreenState extends State<NavigationScreen>
    with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final NavigationState _navState = NavigationState();
  late final SensorRuntimeController _sensorController;
  SensorPipelineStatus? _lastNotifiedPipelineStatus;

  _InAppNotification? _activeNotification;

  Timer? _simulationTimer;
  Timer? _notificationTimer;

  bool _isAutoTracking = true;
  int _statusAnimationEpoch = 0;
  int? _lastNavigationTimestamp;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sensorController = widget.sensorController ?? SensorRuntimeController();
    _sensorController.addListener(_onSensorPipelineStatusChanged);
    widget.navigationPipeline?.addListener(_onNavigationResult);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.navigationPipeline?.removeListener(_onNavigationResult);
    widget.navigationPipeline?.stop();
    _sensorController.removeListener(_onSensorPipelineStatusChanged);
    if (widget.sensorController == null) {
      _sensorController.dispose();
    }
    _simulationTimer?.cancel();
    _notificationTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      if (_navState.navigationActive) {
        _sensorController.pause();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_navState.navigationActive) {
        _sensorController.resume();
      }
    }
  }

  void _showNotificationBanner({
    required String title,
    required String message,
    required IconData icon,
    required Color backgroundColor,
    required Color textColor,
    required Color iconColor,
    required Color borderColor,
    Duration duration = const Duration(milliseconds: 2200),
    bool isGnssLost = false,
  }) {
    _notificationTimer?.cancel();
    setState(() {
      _activeNotification = _InAppNotification(
        key: ValueKey('sensor_notif_$title'),
        isGnssLost: isGnssLost,
        title: title,
        message: message,
        icon: icon,
        backgroundColor: backgroundColor,
        textColor: textColor,
        iconColor: iconColor,
        borderColor: borderColor,
      );
    });

    _notificationTimer = Timer(duration, () {
      if (!mounted) return;
      setState(() {
        _activeNotification = null;
      });
    });
  }

  void _showInAppNotification(bool isGnssLost) {
    _notificationTimer?.cancel();
    _statusAnimationEpoch++;
    setState(() {
      _activeNotification = isGnssLost
          ? _InAppNotification(
              key: ValueKey('notif_$_statusAnimationEpoch'),
              isGnssLost: true,
              title: 'GNSS signal lost',
              message: 'NavSync IDR is continuing navigation',
              icon: Icons.sensors_off_rounded,
              backgroundColor: NavSyncTheme.idrNotificationBg,
              textColor: NavSyncTheme.idrNotificationText,
              iconColor: NavSyncTheme.idrBlue,
              borderColor: NavSyncTheme.idrNotificationBorder,
            )
          : _InAppNotification(
              key: ValueKey('notif_$_statusAnimationEpoch'),
              isGnssLost: false,
              title: 'GNSS restored',
              message: 'GNSS + INS navigation resumed',
              icon: Icons.check_circle_rounded,
              backgroundColor: NavSyncTheme.gnssNotificationBg,
              textColor: NavSyncTheme.gnssNotificationText,
              iconColor: NavSyncTheme.gnssGreen,
              borderColor: NavSyncTheme.gnssNotificationBorder,
            );
    });

    final duration = isGnssLost
        ? const Duration(milliseconds: 2800)
        : const Duration(milliseconds: 2200);

    _notificationTimer = Timer(duration, () {
      if (!mounted) return;
      setState(() {
        _activeNotification = null;
      });
    });
  }

  void _onSensorPipelineStatusChanged() {
    final status = _sensorController.pipelineStatus;
    if (status == _lastNotifiedPipelineStatus) return;
    _lastNotifiedPipelineStatus = status;

    if (status == SensorPipelineStatus.permissionDenied) {
      _showNotificationBanner(
        title: 'Location permission denied',
        message: 'IMU remains active for Dead Reckoning',
        icon: Icons.location_off_rounded,
        backgroundColor: NavSyncTheme.idrNotificationBg,
        textColor: NavSyncTheme.idrNotificationText,
        iconColor: NavSyncTheme.warning,
        borderColor: NavSyncTheme.idrNotificationBorder,
        duration: const Duration(milliseconds: 2800),
      );
    } else if (status == SensorPipelineStatus.locationServicesDisabled) {
      _showNotificationBanner(
        title: 'Location Services disabled',
        message: 'IMU remains active for Dead Reckoning',
        icon: Icons.location_disabled_rounded,
        backgroundColor: NavSyncTheme.idrNotificationBg,
        textColor: NavSyncTheme.idrNotificationText,
        iconColor: NavSyncTheme.warning,
        borderColor: NavSyncTheme.idrNotificationBorder,
        duration: const Duration(milliseconds: 2800),
      );
    } else if (status == SensorPipelineStatus.error) {
      _showNotificationBanner(
        title: 'Sensor collection error',
        message:
            _sensorController.lastErrorMessage ?? 'Recoverable sensor error',
        icon: Icons.error_outline_rounded,
        backgroundColor: const Color(0xFF2C1616),
        textColor: const Color(0xFFFF8A80),
        iconColor: const Color(0xFFFF5252),
        borderColor: const Color(0xFF5A2222),
        duration: const Duration(milliseconds: 2800),
      );
    }
  }

  void _onNavigationResult() {
    if (!mounted || !_navState.navigationActive) return;
    final pipeline = widget.navigationPipeline!;
    final result = pipeline.latest;
    setState(() {
      if (result != null && result.raw.timestamp != _lastNavigationTimestamp) {
        _navState.applyPipelineResult(result);
        _lastNavigationTimestamp = result.raw.timestamp;
      }
    });
  }

  void _startNavigation() {
    setState(() {
      _lastNavigationTimestamp = null;
      _navState.start();
      _isAutoTracking = true;
    });

    if (widget.navigationPipeline != null) {
      _startIntegratedSensors();
    } else {
      _sensorController.start();
    }
    _showNotificationBanner(
      title: 'Sensor collection started',
      message: 'Foreground sensor pipeline active',
      icon: Icons.sensors_rounded,
      backgroundColor: NavSyncTheme.gnssNotificationBg,
      textColor: NavSyncTheme.gnssNotificationText,
      iconColor: NavSyncTheme.gnssGreen,
      borderColor: NavSyncTheme.gnssNotificationBorder,
      duration: const Duration(milliseconds: 2000),
    );

    _simulationTimer?.cancel();
    if (widget.navigationPipeline != null) return;
    // 20Hz update loop (50ms) for smooth vehicle progress along roads
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      final prevStatus = _navState.navigationOutput.gnssStatus;
      setState(() {
        _navState.stepSimulation(0.05);
      });
      final newStatus = _navState.navigationOutput.gnssStatus;
      if (prevStatus != newStatus) {
        _showInAppNotification(newStatus == GnssStatus.unavailable);
      }
    });
  }

  Future<void> _startIntegratedSensors() async {
    await widget.navigationPipeline!.start(_sensorController.sensorDataStream);
    if (mounted &&
        _navState.navigationActive &&
        widget.navigationPipeline!.running) {
      await _sensorController.start();
    }
  }

  void _stopNavigation() {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _notificationTimer?.cancel();
    _statusAnimationEpoch++;
    widget.navigationPipeline?.stop();
    _sensorController.stop();

    setState(() {
      _lastNavigationTimestamp = null;
      _navState.stop();
      _activeNotification = null;
      _isAutoTracking = true;
    });

    _showNotificationBanner(
      title: 'Sensor collection stopped',
      message: 'Foreground sensor pipeline stopped',
      icon: Icons.sensors_off_rounded,
      backgroundColor: NavSyncTheme.surfaceElevated,
      textColor: NavSyncTheme.secondaryText,
      iconColor: NavSyncTheme.tertiaryText,
      borderColor: NavSyncTheme.cardBorder,
      duration: const Duration(milliseconds: 1800),
    );
  }

  void _toggleGnssFailure() {
    if (widget.navigationPipeline != null) return;
    setState(() {
      _navState.toggleManualGnss();
    });

    final isLost =
        _navState.navigationOutput.gnssStatus == GnssStatus.unavailable;
    _showInAppNotification(isLost);
  }

  @override
  Widget build(BuildContext context) {
    final isNavActive = _navState.navigationActive;
    final navOutput = _navState.navigationOutput;
    final isDeadReckoning =
        navOutput.navigationMode == NavigationMode.deadReckoning;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: NavSyncTheme.background,
      drawer: NavSyncDrawer(
        navigationOutput: navOutput,
        sensorController: _sensorController,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Full-Screen OpenStreetMap Navigation View — MUST be first and fill entire screen
          if (widget.navigationPipeline != null &&
              _navState.navigationActive &&
              widget.navigationPipeline!.latest == null)
            const Center(child: Text('Waiting for live navigation'))
          else
            NavigationMap(
              state: _navState,
              isAutoTracking: _isAutoTracking,
              onRecenter: () {
                setState(() => _isAutoTracking = true);
              },
              onUserPan: () {
                if (_isAutoTracking) {
                  setState(() => _isAutoTracking = false);
                }
              },
            ),

          if (widget.navigationPipeline != null && _navState.navigationActive)
            Positioned(
              left: 16,
              right: 16,
              bottom: 185,
              child: Text(
                widget.navigationPipeline!.error ?? 'Live navigation',
                style: const TextStyle(
                  backgroundColor: Colors.black,
                  color: Colors.white,
                ),
              ),
            ),
          // 2. Dead Reckoning Ambient Aura Halo (Visual Wow Factor - IDR Blue)
          if (isDeadReckoning && _isAutoTracking)
            Center(
              child: IgnorePointer(
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: NavSyncTheme.idrBlue.withValues(alpha: 0.6),
                      width: 2.0,
                    ),
                    color: NavSyncTheme.idrBlue.withValues(alpha: 0.08),
                  ),
                ),
              ),
            ),

          // 3. Top Header Elements: Search Bar or Turn Guidance + Dedicated Status Pill + In-App Notification
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isNavActive)
                      _buildTurnGuidanceCard(isDeadReckoning)
                    else
                      _buildDestinationSearchBar(),

                    const SizedBox(height: 8),

                    // Compact Corner Navigation Status Chip (aligned to top-right)
                    Align(
                      alignment: Alignment.centerRight,
                      child: _buildNavigationStatusChip(navOutput),
                    ),

                    // Top Transient In-App Notification
                    _buildTopInAppNotification(),
                  ],
                ),
              ),
            ),
          ),

          // 4. Bottom Navigation Card (Persistent trip info or start controls)
          Positioned(
            left: 16,
            right: 16,
            bottom: 0,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 18),
              child: isNavActive
                  ? _buildActiveNavigationBottomCard()
                  : _buildPreNavigationBottomCard(),
            ),
          ),

          // 5. Floating Re-Center Button (Appears when user pans away)
          if (!_isAutoTracking)
            Positioned(
              right: 16,
              bottom: isNavActive ? 150 : 130,
              child: FloatingActionButton.small(
                heroTag: 'recenter_btn',
                backgroundColor: NavSyncTheme.surfaceElevated,
                foregroundColor: NavSyncTheme.primaryText,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: NavSyncTheme.cardBorder),
                ),
                onPressed: () {
                  setState(() => _isAutoTracking = true);
                },
                child: const Icon(
                  Icons.my_location_rounded,
                  size: 20,
                  color: NavSyncTheme.accentLight,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Pre-Navigation Widgets ────────────────────────────────────────────────

  Widget _buildDestinationSearchBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: NavSyncTheme.floatingCard(),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.menu_rounded,
                  color: NavSyncTheme.primaryText,
                ),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
              Expanded(
                child: Text(
                  'Where do you want to go?',
                  style: NavSyncTheme.headingMedium.copyWith(
                    fontSize: 16,
                    color: NavSyncTheme.secondaryText,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.search_rounded,
                  color: NavSyncTheme.primaryText,
                ),
                onPressed: () {},
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Quick destination chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildQuickChip('Pune Central Station', Icons.train_rounded),
              _buildQuickChip('FC Road Cafe', Icons.restaurant_rounded),
              _buildQuickChip('Deccan Gymkhana', Icons.sports_tennis_rounded),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickChip(String label, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: NavSyncTheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NavSyncTheme.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: NavSyncTheme.accentLight),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: NavSyncTheme.primaryText,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreNavigationBottomCard() {
    return Container(
      decoration: NavSyncTheme.floatingCard(
        borderRadius: NavSyncTheme.radiusMajorCard,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _navState.destinationName,
                  style: NavSyncTheme.headingMedium.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Text(
                        '${_navState.remainingMinutes} min',
                        style: const TextStyle(
                          color: NavSyncTheme.maneuverGreen,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '•',
                        style: TextStyle(color: NavSyncTheme.secondaryText),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${_navState.totalTripDistanceKm} km',
                        style: NavSyncTheme.tripSubtext.copyWith(fontSize: 13),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '•',
                        style: TextStyle(color: NavSyncTheme.secondaryText),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Fast Route',
                        style: TextStyle(
                          color: NavSyncTheme.secondaryText,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: NavSyncTheme.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(NavSyncTheme.radiusButton),
              ),
              elevation: 2,
            ),
            onPressed: _startNavigation,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.navigation_rounded, size: 16),
                SizedBox(width: 6),
                Text(
                  'START',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Active Navigation Widgets ─────────────────────────────────────────────

  Widget _buildTurnGuidanceCard(bool isDeadReckoning) {
    final guidance = _navState.currentGuidance;
    final distMeters = _navState.distanceToNextTurnMeters;

    return Container(
      decoration: NavSyncTheme.guidanceCard(isDeadReckoning: isDeadReckoning),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Maneuver Icon Box
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isDeadReckoning
                  ? NavSyncTheme.idrBlue.withValues(alpha: 0.15)
                  : NavSyncTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDeadReckoning
                    ? NavSyncTheme.idrBlue
                    : NavSyncTheme.cardBorder,
                width: 1.0,
              ),
            ),
            child: Icon(
              guidance.maneuverIcon,
              size: 26,
              color: isDeadReckoning
                  ? NavSyncTheme.idrBlueLight
                  : NavSyncTheme.maneuverGreen,
            ),
          ),
          const SizedBox(width: 14),

          // Maneuver text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$distMeters m',
                  style: NavSyncTheme.maneuverDistance.copyWith(
                    color: isDeadReckoning
                        ? NavSyncTheme.idrBlueLight
                        : NavSyncTheme.maneuverGreen,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  guidance.instruction,
                  style: NavSyncTheme.maneuverInstruction.copyWith(
                    fontSize: 17,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Menu button
          IconButton(
            icon: const Icon(
              Icons.more_vert_rounded,
              color: NavSyncTheme.secondaryText,
            ),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
        ],
      ),
    );
  }

  /// Compact top-right corner status chip sized to content
  Widget _buildNavigationStatusChip(NavigationOutput output) {
    if (widget.navigationPipeline != null &&
        widget.navigationPipeline!.latest == null) {
      return const Text('WAITING FOR LIVE NAVIGATION');
    }
    final isDeadReckoning =
        output.navigationMode == NavigationMode.deadReckoning;

    return Semantics(
      label: widget.navigationPipeline != null
          ? (isDeadReckoning ? 'IDR active' : 'GNSS active')
          : isDeadReckoning
          ? 'IDR active. Tap to simulate GNSS restoration'
          : 'GNSS active. Tap to simulate GNSS signal loss',
      button: true,
      child: GestureDetector(
        key: const ValueKey('navigation_status_pill'),
        onTap: widget.navigationPipeline == null ? _toggleGnssFailure : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: isDeadReckoning
                ? NavSyncTheme.idrCardBg.withValues(alpha: 0.95)
                : NavSyncTheme.surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDeadReckoning
                  ? NavSyncTheme.idrBorder
                  : NavSyncTheme.gnssGreen.withValues(alpha: 0.4),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Status Icon / Glowing Dot
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: isDeadReckoning
                    ? Icon(
                        Icons.radar_rounded,
                        key: ValueKey('dr_dot_$_statusAnimationEpoch'),
                        size: 15,
                        color: NavSyncTheme.idrBlueLight,
                      )
                    : Container(
                        key: ValueKey('gnss_dot_$_statusAnimationEpoch'),
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: NavSyncTheme.gnssGreen,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: NavSyncTheme.gnssGreenGlow,
                              blurRadius: 5,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(width: 8),

              // One-line status label (GNSS ACTIVE / IDR ACTIVE)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  isDeadReckoning ? 'IDR ACTIVE' : 'GNSS ACTIVE',
                  key: ValueKey('status_labels_$_statusAnimationEpoch'),
                  style: TextStyle(
                    color: isDeadReckoning
                        ? NavSyncTheme.idrBlueLight
                        : NavSyncTheme.gnssGreen,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Transient In-Page Top Notification (replaces bottom SnackBar)
  Widget _buildTopInAppNotification() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            alignment: Alignment.topCenter,
            child: child,
          ),
        );
      },
      child: _activeNotification == null
          ? const SizedBox.shrink(key: ValueKey('empty_notif'))
          : Container(
              key: _activeNotification!.key,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _activeNotification!.backgroundColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _activeNotification!.borderColor,
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    _activeNotification!.icon,
                    color: _activeNotification!.iconColor,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _activeNotification!.title,
                          style: TextStyle(
                            color: _activeNotification!.textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          _activeNotification!.message,
                          style: TextStyle(
                            color: _activeNotification!.textColor.withValues(
                              alpha: 0.85,
                            ),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: _activeNotification!.textColor.withValues(
                        alpha: 0.6,
                      ),
                    ),
                    onPressed: () {
                      _notificationTimer?.cancel();
                      setState(() => _activeNotification = null);
                    },
                  ),
                ],
              ),
            ),
    );
  }

  /// Compact, refined Active Navigation Bottom Card
  Widget _buildActiveNavigationBottomCard() {
    if (widget.navigationPipeline != null &&
        widget.navigationPipeline!.latest == null) {
      return Container(
        decoration: NavSyncTheme.floatingCard(borderRadius: 26),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Expanded(child: Text('Waiting for navigation estimates')),
            IconButton(
              key: const ValueKey('stop_navigation_button'),
              tooltip: 'Stop navigation',
              onPressed: _stopNavigation,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: NavSyncTheme.floatingCard(borderRadius: 26.0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Left Two-Line ETA Summary Column (Expanded)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top line: Arrival time (calm green) + ETA label
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        _navState.formattedEta,
                        style: const TextStyle(
                          color: NavSyncTheme.maneuverGreen,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: NavSyncTheme.maneuverGreen.withValues(
                            alpha: 0.15,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'ETA',
                          style: TextStyle(
                            color: NavSyncTheme.maneuverGreen,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 3),

                // Bottom line: Duration & remaining distance
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_navState.remainingMinutes} min  •  ${_navState.remainingDistanceKm.toStringAsFixed(1)} km remaining',
                    style: const TextStyle(
                      color: NavSyncTheme.secondaryText,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // 2. Refined Compact Speed Tile (rounded square)
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: NavSyncTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: NavSyncTheme.cardBorder),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _navState.navigationOutput.speedKmh.toStringAsFixed(0),
                  style: const TextStyle(
                    color: NavSyncTheme.primaryText,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'km/h',
                  style: TextStyle(
                    color: NavSyncTheme.secondaryText,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // 3. Destructive Circular Stop Control
          Semantics(
            label: 'Stop navigation',
            button: true,
            child: Tooltip(
              message: 'Stop navigation',
              child: InkWell(
                key: const ValueKey('stop_navigation_button'),
                onTap: _stopNavigation,
                borderRadius: BorderRadius.circular(26),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C1616),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF5A2222)),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.close_rounded,
                      color: Color(0xFFFF5252),
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
