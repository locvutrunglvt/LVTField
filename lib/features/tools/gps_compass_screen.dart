import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/gps_service.dart';
import '../../core/services/crs_service.dart';

/// GPS Information & Compass screen with 2 tabs
/// Reuses the app's existing GpsService for instant GPS data
///
/// Author: Loc Vu Trung
class GpsCompassScreen extends StatefulWidget {
  final GpsService? gpsService;
  
  const GpsCompassScreen({super.key, this.gpsService});

  @override
  State<GpsCompassScreen> createState() => _GpsCompassScreenState();
}

class _GpsCompassScreenState extends State<GpsCompassScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // GPS state — reuse from GpsService
  GpsPosition? _position;
  StreamSubscription<GpsPosition>? _gpsSub;
  DateTime? _lastFix;
  CrsDisplayMode _crsMode = CrsDisplayMode.wgs84;
  
  // Compass state
  double _heading = 0;
  double _smoothedHeading = 0;
  StreamSubscription<CompassEvent>? _compassSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _connectGps();
    _startCompass();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _gpsSub?.cancel(); // Only cancel our listener, not the service
    _compassSub?.cancel();
    super.dispose();
  }

  void _connectGps() {
    final svc = widget.gpsService;
    if (svc != null) {
      // Use existing GPS data immediately
      final last = svc.lastPosition;
      if (last != null) {
        _position = _fromGpsPosition(last);
        _lastFix = last.timestamp;
      }
      // Listen for updates from the shared service
      _gpsSub = svc.positionStream.listen((gpsPos) {
        if (!mounted) return;
        setState(() {
          _position = _fromGpsPosition(gpsPos);
          _lastFix = gpsPos.timestamp;
        });
      });
    }
  }

  /// Convert GpsPosition to our local position format
  GpsPosition _fromGpsPosition(GpsPosition gps) => gps;

  void _startCompass() {
    _compassSub = FlutterCompass.events?.listen((event) {
      if (!mounted) return;
      final raw = event.heading ?? 0;
      // Exponential moving average for smooth compass
      // Handle wrap-around (359° → 1°)
      double diff = raw - _smoothedHeading;
      if (diff > 180) diff -= 360;
      if (diff < -180) diff += 360;
      _smoothedHeading = (_smoothedHeading + diff * 0.15) % 360;
      if (_smoothedHeading < 0) _smoothedHeading += 360;
      setState(() => _heading = _smoothedHeading);
    });
  }

  int _estimateSatellites(double? accuracy) {
    if (accuracy == null) return 0;
    if (accuracy < 3) return 12;
    if (accuracy < 5) return 10;
    if (accuracy < 10) return 8;
    if (accuracy < 20) return 5;
    if (accuracy < 50) return 3;
    return 1;
  }

  String _directionLabel(double heading) {
    if (heading >= 337.5 || heading < 22.5) return 'N';
    if (heading < 67.5) return 'NE';
    if (heading < 112.5) return 'E';
    if (heading < 157.5) return 'SE';
    if (heading < 202.5) return 'S';
    if (heading < 247.5) return 'SW';
    if (heading < 292.5) return 'W';
    return 'NW';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GPS & La bàn', style: TextStyle(fontWeight: FontWeight.w600)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          tabs: const [
            Tab(text: 'GPS'),
            Tab(text: 'LA BÀN'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildGpsTab(),
          _buildCompassTab(),
        ],
      ),
    );
  }

  // ─── GPS Tab ─────────────────────────────────────────────────────────

  Widget _buildGpsTab() {
    final pos = _position;
    final accuracy = pos?.accuracy ?? 0;
    final satCount = _estimateSatellites(pos?.accuracy);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Coordinates display
          _buildCoordinatesCard(isDark),

          const SizedBox(height: 16),

          // Accuracy card
          _buildAccuracyCard(accuracy, isDark),

          const SizedBox(height: 16),

          // Signal bars card
          _buildSignalCard(satCount, isDark),

          // Indoor warning
          if (accuracy > 30) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.signal_wifi_connected_no_internet_4, color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '📡 Tín hiệu yếu (trong nhà?) — Độ cao và tốc độ không chính xác',
                      style: TextStyle(color: Colors.orange.shade700, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Info cards
          _buildInfoCards(isDark),
        ],
      ),
    );
  }

  Widget _buildCoordinatesCard(bool isDark) {
    final pos = _position;
    String coordText = 'Đang tìm vị trí...';
    if (pos != null) {
      coordText = CrsService.formatCoordinate(
        pos.latLng.latitude, pos.latLng.longitude, _crsMode,
      );
    }
    final modeLabel = CrsService.displayModeLabel(_crsMode);
    final cardBg = isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white;
    final borderClr = isDark ? Colors.white10 : AppColors.divider;

    return GestureDetector(
      onTap: () {
        setState(() => _crsMode = CrsService.nextDisplayMode(_crsMode));
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderClr),
        ),
        child: Column(
          children: [
            Text(modeLabel,
                style: TextStyle(
                    color: isDark ? Colors.white54 : AppColors.textSecondary,
                    fontSize: 12)),
            const SizedBox(height: 6),
            Text(coordText,
                style: TextStyle(
                  color: isDark ? Colors.white : AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                )),
            const SizedBox(height: 4),
            Text('▸ Chạm để đổi CRS',
                style: TextStyle(
                    color: isDark ? Colors.white30 : AppColors.textSecondary,
                    fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildAccuracyCard(double accuracy, bool isDark) {
    final accuracyText = accuracy > 0 ? '${accuracy.toStringAsFixed(1)} m' : '---';
    final qualityLabel = accuracy < 5 ? 'Tốt' : accuracy < 15 ? 'Trung bình' : 'Yếu';
    final qualityColor = accuracy < 5
        ? AppColors.gpsGood
        : accuracy < 15
            ? AppColors.gpsModerate
            : AppColors.gpsPoor;
    final cardBg = isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white;
    final borderClr = isDark ? Colors.white10 : AppColors.divider;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderClr),
      ),
      child: Column(
        children: [
          Text('Độ chính xác GPS',
              style: TextStyle(
                  color: isDark ? Colors.white54 : AppColors.textSecondary,
                  fontSize: 12)),
          const SizedBox(height: 8),
          Text(accuracyText,
              style: TextStyle(
                color: qualityColor,
                fontSize: 40,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              )),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: qualityColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(qualityLabel,
                style: TextStyle(
                    color: qualityColor, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildSignalCard(int satCount, bool isDark) {
    final cardBg = isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white;
    final borderClr = isDark ? Colors.white10 : AppColors.divider;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderClr),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tín hiệu GPS (~$satCount vệ tinh)',
              style: TextStyle(
                  color: isDark ? Colors.white54 : AppColors.textSecondary,
                  fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          Row(
            children: List.generate(12, (i) {
              final isActive = i < satCount;
              final height = 12.0 + (i * 2.5);
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: height,
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.primary.withValues(alpha: 0.7)
                          : (isDark ? Colors.white10 : Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCards(bool isDark) {
    final pos = _position;
    final altitude = pos?.altitude ?? 0;
    final rawSpeed = pos?.speed ?? 0;
    final speedKmh = rawSpeed < 0.3 ? 0.0 : rawSpeed * 3.6; // Filter GPS drift
    final accuracy = pos?.accuracy ?? 0;
    final satCount = _estimateSatellites(pos?.accuracy);
    final fixTime = _lastFix != null
        ? '${_lastFix!.hour.toString().padLeft(2, '0')}:'
          '${_lastFix!.minute.toString().padLeft(2, '0')}:'
          '${_lastFix!.second.toString().padLeft(2, '0')}'
        : '--:--:--';

    return Column(
      children: [
        Row(children: [
          _infoCard('Độ cao', accuracy > 20 ? '~${altitude.toStringAsFixed(0)} m' : '${altitude.toStringAsFixed(0)} m', Icons.terrain, isDark),
          const SizedBox(width: 8),
          _infoCard('Tốc độ', '${speedKmh.toStringAsFixed(1)} km/h', Icons.speed, isDark),
          const SizedBox(width: 8),
          _infoCard('Accuracy', '${accuracy.toStringAsFixed(1)} m', Icons.gps_fixed, isDark),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _infoCard('Vệ tinh', '~$satCount', Icons.satellite_alt, isDark),
          const SizedBox(width: 8),
          _infoCard('GPS fix', fixTime, Icons.access_time, isDark),
        ]),
      ],
    );
  }

  // ─── Compass Tab ─────────────────────────────────────────────────────

  Widget _buildCompassTab() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildCoordinatesCard(isDark),
          const SizedBox(height: 20),
          _buildCompassRose(),
          const SizedBox(height: 20),
          _buildCompassInfoCards(isDark),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildCompassRose() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return SizedBox(
      width: 280,
      height: 280,
      child: CustomPaint(
        painter: _CompassRosePainter(heading: _heading),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Azimuth',
                  style: TextStyle(
                      color: isDark ? Colors.white54 : AppColors.textSecondary,
                      fontSize: 12)),
              Text('${_heading.toStringAsFixed(0)}°',
                  style: TextStyle(
                    color: isDark ? Colors.white : AppColors.textPrimary,
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                  )),
              Text(_directionLabel(_heading),
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompassInfoCards(bool isDark) {
    return Row(children: [
      _infoCard('Hướng', '${_heading.toStringAsFixed(0)}° ${_directionLabel(_heading)}',
          Icons.explore, isDark),
      const SizedBox(width: 8),
      _infoCard('Từ thiên', '0°', Icons.south, isDark),
    ]);
  }

  // ─── Shared widgets ──────────────────────────────────────────────────

  Widget _infoCard(String label, String value, IconData icon, bool isDark) {
    final cardBg = isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white;
    final borderClr = isDark ? Colors.white10 : AppColors.divider;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderClr),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14,
                    color: isDark ? Colors.white38 : AppColors.textSecondary),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(label,
                      style: TextStyle(
                        color: isDark ? Colors.white54 : AppColors.textSecondary,
                        fontSize: 10,
                      ),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                  color: isDark ? Colors.white : AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                )),
          ],
        ),
      ),
    );
  }

  Widget _divider() => const SizedBox(width: 8);
}

// ═══════════════════════════════════════════════════════════════════════
// Custom Painters
// ═══════════════════════════════════════════════════════════════════════

/// GPS accuracy circle visualization
class _GpsAccuracyPainter extends CustomPainter {
  final double accuracy;
  final double maxAccuracy;

  _GpsAccuracyPainter({required this.accuracy, required this.maxAccuracy});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Draw concentric rings
    for (int i = 3; i >= 1; i--) {
      final r = radius * (i / 3);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.05)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    // Draw accuracy indicator ring
    final accuracyRatio = (accuracy / maxAccuracy).clamp(0.05, 1.0);
    final accuracyColor = accuracy < 5
        ? Colors.greenAccent
        : accuracy < 15
            ? Colors.yellowAccent
            : Colors.redAccent;

    canvas.drawCircle(
      center,
      radius * accuracyRatio,
      Paint()
        ..color = accuracyColor.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      radius * accuracyRatio,
      Paint()
        ..color = accuracyColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Center dot
    canvas.drawCircle(
      center,
      4,
      Paint()..color = Colors.cyanAccent,
    );

    // Cross lines
    final crossPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), crossPaint);
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), crossPaint);
  }

  @override
  bool shouldRepaint(covariant _GpsAccuracyPainter old) =>
      old.accuracy != accuracy;
}

/// Full compass rose with degree markings and N/S/E/W labels
class _CompassRosePainter extends CustomPainter {
  final double heading;

  _CompassRosePainter({required this.heading});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Save and rotate canvas (opposite of heading so compass needle points north)
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-heading * math.pi / 180);

    // Outer ring (dark)
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()
        ..color = const Color(0xFF2A2A3E)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Inner rings
    canvas.drawCircle(
      Offset.zero,
      radius * 0.85,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.05)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset.zero,
      radius * 0.85,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Draw degree ticks
    for (int deg = 0; deg < 360; deg += 5) {
      final rad = deg * math.pi / 180;
      final isCardinal = deg % 90 == 0;
      final isMajor = deg % 30 == 0;
      final isMinor = deg % 15 == 0;

      final outerR = radius * 0.95;
      final innerR = isCardinal
          ? radius * 0.75
          : isMajor
              ? radius * 0.82
              : isMinor
                  ? radius * 0.87
                  : radius * 0.90;

      final tickPaint = Paint()
        ..color = isCardinal
            ? Colors.white
            : isMajor
                ? Colors.white70
                : Colors.white30
        ..strokeWidth = isCardinal ? 2.5 : isMajor ? 1.5 : 0.8;

      canvas.drawLine(
        Offset(math.sin(rad) * innerR, -math.cos(rad) * innerR),
        Offset(math.sin(rad) * outerR, -math.cos(rad) * outerR),
        tickPaint,
      );

      // Degree labels for major ticks
      if (isMajor && !isCardinal) {
        final labelR = radius * 0.70;
        final tp = TextPainter(
          text: TextSpan(
            text: '$deg',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        canvas.save();
        canvas.translate(
          math.sin(rad) * labelR,
          -math.cos(rad) * labelR,
        );
        canvas.rotate(rad);
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
        canvas.restore();
      }
    }

    // Cardinal labels N/S/E/W
    final cardinals = [
      (0.0, 'N', Colors.red),
      (90.0, 'E', Colors.white),
      (180.0, 'S', Colors.white),
      (270.0, 'W', Colors.white),
    ];

    for (final (deg, label, color) in cardinals) {
      final rad = deg * math.pi / 180;
      final labelR = radius * 0.58;

      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: color,
            fontSize: label == 'N' ? 24 : 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      canvas.save();
      canvas.translate(
        math.sin(rad) * labelR,
        -math.cos(rad) * labelR,
      );
      // Counter-rotate text so it's always upright
      canvas.rotate(rad);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    // North indicator triangle (red)
    final northPath = Path()
      ..moveTo(0, -radius * 0.97)
      ..lineTo(-6, -radius * 0.88)
      ..lineTo(6, -radius * 0.88)
      ..close();
    canvas.drawPath(
      northPath,
      Paint()..color = Colors.red,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CompassRosePainter old) =>
      old.heading != heading;
}
