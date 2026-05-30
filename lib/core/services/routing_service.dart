// Routing Service using OSRM
// Author: Lộc Vũ Trung

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Route profile (vehicle type)
enum RouteProfile {
  driving,   // Ô tô
  walking,   // Đi bộ
}

/// Route result data
class RouteResult {
  final List<LatLng> geometry;     // route polyline
  final double distanceMeters;     // total distance
  final double durationSeconds;    // total time
  final String distanceText;       // formatted: "12.5 km"
  final String durationText;       // formatted: "25 phút"
  final RouteProfile profile;

  RouteResult({
    required this.geometry,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.distanceText,
    required this.durationText,
    required this.profile,
  });
}

class RoutingService {
  static const _osrmBase = 'https://router.project-osrm.org';

  /// Get route between two points
  /// Uses OSRM demo server (free, no API key)
  /// Profile: driving or walking
  ///
  /// NOTE: OSRM demo server only reliably supports 'driving'.
  /// For walking, we use 'foot' profile but fallback to driving if unavailable.
  static Future<RouteResult?> getRoute({
    required LatLng origin,
    required LatLng destination,
    RouteProfile profile = RouteProfile.driving,
  }) async {
    final profileStr = profile == RouteProfile.walking ? 'foot' : 'driving';
    final coords = '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}';
    final url = '$_osrmBase/route/v1/$profileStr/$coords?overview=full&geometries=geojson&steps=false';

    try {
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode != 200) {
        debugPrint('Routing error: HTTP ${response.statusCode}');
        // Fallback to driving if foot failed
        if (profile == RouteProfile.walking) {
          return _getOsrmRoute(origin, destination, 'driving', RouteProfile.walking);
        }
        return null;
      }

      return _parseOsrmResponse(response.body, profile);
    } catch (e) {
      debugPrint('Routing error: $e');
      return null;
    }
  }

  static Future<RouteResult?> _getOsrmRoute(
    LatLng origin, LatLng destination, String profileStr, RouteProfile profile,
  ) async {
    final coords = '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}';
    final url = '$_osrmBase/route/v1/$profileStr/$coords?overview=full&geometries=geojson&steps=false';
    try {
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200) return null;
      return _parseOsrmResponse(response.body, profile);
    } catch (e) {
      debugPrint('Routing fallback error: $e');
      return null;
    }
  }

  static RouteResult? _parseOsrmResponse(String body, RouteProfile profile) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json['code'] != 'Ok') return null;

      final routes = json['routes'] as List;
      if (routes.isEmpty) return null;

      final route = routes[0] as Map<String, dynamic>;
      final distance = (route['distance'] as num).toDouble();
      final duration = (route['duration'] as num).toDouble();

      // Parse GeoJSON geometry
      final geometry = route['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;
      final points = coordinates.map((c) {
        final coord = c as List;
        return LatLng((coord[1] as num).toDouble(), (coord[0] as num).toDouble());
      }).toList();

      // Adjust duration for walking (OSRM driving speed / ~5 km/h walking)
      final adjustedDuration = profile == RouteProfile.walking
          ? distance / 1.39  // 5 km/h = 1.39 m/s
          : duration;

      return RouteResult(
        geometry: points,
        distanceMeters: distance,
        durationSeconds: adjustedDuration,
        distanceText: _formatDistance(distance),
        durationText: _formatDuration(adjustedDuration),
        profile: profile,
      );
    } catch (e) {
      debugPrint('Route parse error: $e');
      return null;
    }
  }

  static String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  static String _formatDuration(double seconds) {
    if (seconds < 60) return '${seconds.round()} giây';
    if (seconds < 3600) return '${(seconds / 60).round()} phút';
    final hours = (seconds / 3600).floor();
    final mins = ((seconds % 3600) / 60).round();
    return '${hours}h ${mins}p';
  }
}
