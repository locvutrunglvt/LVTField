import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/navigation_service.dart';

/// Navigation info panel overlay displayed on the map during navigation mode.
/// Shows distance, bearing, ETA, and proximity alert.
///
/// Author: Lộc Vũ Trung
class NavigationOverlay extends StatelessWidget {
  final LatLng currentPosition;
  final LatLng targetPosition;
  final String? targetName;
  final VoidCallback onStop;

  const NavigationOverlay({
    super.key,
    required this.currentPosition,
    required this.targetPosition,
    this.targetName,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final distance = NavigationService.calculateDistance(
        currentPosition, targetPosition);
    final bearing = NavigationService.calculateBearing(
        currentPosition, targetPosition);
    final proximity = NavigationService.proximityLevel(distance);

    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: _proximityColor(proximity).withValues(alpha: 0.3),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
          border: Border.all(
            color: _proximityColor(proximity).withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Target name + stop button
            Row(
              children: [
                Icon(Icons.flag, color: _proximityColor(proximity), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    targetName ?? 'Đích đến',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: onStop,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.close, color: AppColors.error, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'Dừng',
                          style: TextStyle(
                            color: AppColors.error,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Main info row: distance + compass + ETA
            Row(
              children: [
                // Distance (large)
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        NavigationService.formatDistance(distance),
                        style: TextStyle(
                          color: _proximityColor(proximity),
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        NavigationService.proximityLabel(distance),
                        style: TextStyle(
                          color: _proximityColor(proximity).withValues(alpha: 0.8),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                // Compass arrow
                SizedBox(
                  width: 56,
                  height: 56,
                  child: CustomPaint(
                    painter: _CompassArrowPainter(
                      bearing: bearing,
                      color: _proximityColor(proximity),
                    ),
                  ),
                ),

                // Bearing + ETA
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${bearing.round()}°',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        NavigationService.bearingToCardinalFull(bearing),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.directions_walk,
                              size: 14,
                              color: Colors.white.withValues(alpha: 0.6)),
                          const SizedBox(width: 4),
                          Text(
                            NavigationService.estimateWalkingTime(distance),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Proximity bar
            _buildProximityBar(proximity, distance),
          ],
        ),
      ),
    );
  }

  Color _proximityColor(String proximity) {
    switch (proximity) {
      case 'arrived':
        return const Color(0xFF4CAF50);
      case 'close':
        return const Color(0xFFFF5722);
      case 'approaching':
        return const Color(0xFFFFC107);
      default:
        return const Color(0xFF42A5F5);
    }
  }

  Widget _buildProximityBar(String proximity, double distance) {
    // Map distance to 0..1 (0=far, 1=close)
    final progress = (1 - (distance / 200).clamp(0, 1)).toDouble();
    final color = _proximityColor(proximity);

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 4,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '200m',
              style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.4)),
            ),
            Text(
              '100m',
              style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.4)),
            ),
            Text(
              '0m',
              style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.4)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Compass arrow painter - rotates based on bearing
class _CompassArrowPainter extends CustomPainter {
  final double bearing;
  final Color color;

  _CompassArrowPainter({required this.bearing, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Outer circle
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Rotate canvas
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(bearing * math.pi / 180);

    // Arrow (pointing up = north direction)
    final path = ui.Path();
    path.moveTo(0, -radius + 4);
    path.lineTo(-6, 8);
    path.lineTo(0, 2);
    path.lineTo(6, 8);
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );

    // Small south marker
    canvas.drawCircle(
      Offset(0, radius - 6),
      2,
      Paint()..color = color.withValues(alpha: 0.5),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CompassArrowPainter oldDelegate) {
    return oldDelegate.bearing != bearing || oldDelegate.color != color;
  }
}
