import 'dart:math';
import 'package:latlong2/latlong.dart';

/// Navigation calculations for field survey
/// Supports distance, bearing, proximity alerts, and time estimates.
///
/// Author: Lộc Vũ Trung
class NavigationService {
  static const double _earthRadius = 6371000; // meters

  /// Calculate distance in meters between two points (Haversine formula)
  static double calculateDistance(LatLng from, LatLng to) {
    final dLat = _toRadians(to.latitude - from.latitude);
    final dLon = _toRadians(to.longitude - from.longitude);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(from.latitude)) *
            cos(_toRadians(to.latitude)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return _earthRadius * c;
  }

  /// Calculate bearing (azimuth) in degrees from point A to point B
  /// Returns 0-360 degrees (0=North, 90=East, 180=South, 270=West)
  static double calculateBearing(LatLng from, LatLng to) {
    final dLon = _toRadians(to.longitude - from.longitude);
    final fromLat = _toRadians(from.latitude);
    final toLat = _toRadians(to.latitude);

    final y = sin(dLon) * cos(toLat);
    final x = cos(fromLat) * sin(toLat) -
        sin(fromLat) * cos(toLat) * cos(dLon);

    final bearing = atan2(y, x);
    return (_toDegrees(bearing) + 360) % 360;
  }

  /// Get cardinal direction string from bearing
  static String bearingToCardinal(double bearing) {
    const directions = ['B', 'ĐB', 'Đ', 'ĐN', 'N', 'TN', 'T', 'TB'];
    final index = ((bearing + 22.5) / 45).floor() % 8;
    return directions[index];
  }

  /// Get full cardinal direction name
  static String bearingToCardinalFull(double bearing) {
    const directions = [
      'Bắc', 'Đông Bắc', 'Đông', 'Đông Nam',
      'Nam', 'Tây Nam', 'Tây', 'Tây Bắc',
    ];
    final index = ((bearing + 22.5) / 45).floor() % 8;
    return directions[index];
  }

  /// Check proximity alert level
  /// Returns proximity level string
  static String proximityLevel(double distanceMeters) {
    if (distanceMeters < 10) return 'arrived';
    if (distanceMeters < 50) return 'close';
    if (distanceMeters < 100) return 'approaching';
    return 'far';
  }

  /// Get Vietnamese proximity label
  static String proximityLabel(double distanceMeters) {
    if (distanceMeters < 10) return 'Đã đến nơi!';
    if (distanceMeters < 50) return 'Rất gần';
    if (distanceMeters < 100) return 'Đang tiếp cận';
    return 'Đang di chuyển';
  }

  /// Format distance for display
  /// <1000m: '234 m', >=1000m: '1.23 km'
  static String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()} m';
    }
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }

  /// Estimate walking time (average 3.5 km/h in forest terrain)
  static String estimateWalkingTime(double meters) {
    const speedKmh = 3.5; // slower in forest
    final hours = meters / 1000 / speedKmh;
    final totalMinutes = (hours * 60).round();

    if (totalMinutes < 1) return '< 1 phút';
    if (totalMinutes < 60) return '$totalMinutes phút';

    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (m == 0) return '$h giờ';
    return '$h giờ $m phút';
  }

  // Helpers
  static double _toRadians(double degrees) => degrees * pi / 180;
  static double _toDegrees(double radians) => radians * 180 / pi;
}
