import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../constants/app_sizes.dart';

/// GPS accuracy classification
enum GpsQuality { good, moderate, poor, noSignal }

/// GPS position data with accuracy info
class GpsPosition {
  final LatLng latLng;
  final double accuracy;
  final double? altitude;
  final double? speed;
  final double? heading;
  final int? satelliteCount;
  final DateTime timestamp;

  GpsPosition({
    required this.latLng,
    required this.accuracy,
    this.altitude,
    this.speed,
    this.heading,
    this.satelliteCount,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Classify GPS accuracy quality
  GpsQuality get quality {
    if (accuracy <= AppSizes.gpsGoodThreshold) return GpsQuality.good;
    if (accuracy <= AppSizes.gpsModerateThreshold) return GpsQuality.moderate;
    return GpsQuality.poor;
  }

  /// Human-readable accuracy string
  String get accuracyText => '${accuracy.toStringAsFixed(1)} m';

  @override
  String toString() => 'GpsPosition(${latLng.latitude.toStringAsFixed(6)}, ${latLng.longitude.toStringAsFixed(6)}, acc: $accuracyText)';
}

/// Service for managing GPS location tracking
/// Optimized for forest survey with high accuracy settings
class GpsService {
  StreamSubscription<Position>? _positionSubscription;
  final _positionController = StreamController<GpsPosition>.broadcast();
  GpsPosition? _lastPosition;
  bool _isTracking = false;

  /// Stream of GPS positions
  Stream<GpsPosition> get positionStream => _positionController.stream;

  /// Last known position
  GpsPosition? get lastPosition => _lastPosition;

  /// Whether GPS is actively tracking
  bool get isTracking => _isTracking;

  /// Check and request location permissions
  Future<bool> checkPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  /// Get current position with high accuracy
  Future<GpsPosition?> getCurrentPosition() async {
    try {
      final hasPermission = await checkPermissions();
      if (!hasPermission) return null;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 15),
        ),
      );

      final gpsPos = _toGpsPosition(position);
      _lastPosition = gpsPos;
      return gpsPos;
    } catch (e) {
      debugPrint('GPS getCurrentPosition error: $e');
      return null;
    }
  }

  /// Start continuous GPS tracking optimized for field survey
  /// Uses bestForNavigation accuracy for maximum satellite usage
  Future<bool> startTracking({
    int distanceFilter = 1,
    int intervalMs = 1000,
  }) async {
    if (_isTracking) return true;

    final hasPermission = await checkPermissions();
    if (!hasPermission) return false;

    _isTracking = true;

    // Platform-specific settings for optimal satellite reception
    late LocationSettings locationSettings;

    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: distanceFilter,
        intervalDuration: Duration(milliseconds: intervalMs),
        // Keep GPS active even when app is in background
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: 'LVTField đang thu thập dữ liệu GPS',
          notificationTitle: 'LVTField GPS',
          enableWakeLock: true,
          notificationIcon: AndroidResource(
            name: 'ic_launcher',
            defType: 'mipmap',
          ),
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: distanceFilter,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      locationSettings = LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: distanceFilter,
      );
    }

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (position) {
        final gpsPos = _toGpsPosition(position);
        _lastPosition = gpsPos;
        _positionController.add(gpsPos);
      },
      onError: (error) {
        debugPrint('GPS stream error: $error');
      },
    );

    return true;
  }

  /// Stop GPS tracking
  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _isTracking = false;
  }

  /// Calculate distance between two points in meters
  double distanceBetween(LatLng from, LatLng to) {
    return Geolocator.distanceBetween(
      from.latitude, from.longitude,
      to.latitude, to.longitude,
    );
  }

  /// Average multiple GPS readings for better accuracy
  /// Takes [count] readings over [durationMs] and returns the average
  Future<GpsPosition?> getAveragedPosition({
    int count = 5,
    int intervalMs = 1000,
  }) async {
    final positions = <GpsPosition>[];

    for (int i = 0; i < count; i++) {
      final pos = await getCurrentPosition();
      if (pos != null) {
        positions.add(pos);
      }
      if (i < count - 1) {
        await Future.delayed(Duration(milliseconds: intervalMs));
      }
    }

    if (positions.isEmpty) return null;

    // Calculate weighted average (weight by accuracy - lower = better)
    double totalWeight = 0;
    double weightedLat = 0;
    double weightedLng = 0;
    double weightedAlt = 0;
    int altCount = 0;

    for (final pos in positions) {
      final weight = 1.0 / (pos.accuracy * pos.accuracy);
      totalWeight += weight;
      weightedLat += pos.latLng.latitude * weight;
      weightedLng += pos.latLng.longitude * weight;
      if (pos.altitude != null) {
        weightedAlt += pos.altitude! * weight;
        altCount++;
      }
    }

    // Best accuracy from all readings
    final bestAccuracy = positions
        .map((p) => p.accuracy)
        .reduce((a, b) => a < b ? a : b);

    return GpsPosition(
      latLng: LatLng(weightedLat / totalWeight, weightedLng / totalWeight),
      accuracy: bestAccuracy,
      altitude: altCount > 0 ? weightedAlt / totalWeight : null,
    );
  }

  /// Convert Geolocator Position to our GpsPosition
  GpsPosition _toGpsPosition(Position position) {
    return GpsPosition(
      latLng: LatLng(position.latitude, position.longitude),
      accuracy: position.accuracy,
      altitude: position.altitude,
      speed: position.speed,
      heading: position.heading,
      timestamp: position.timestamp,
    );
  }

  /// Dispose of GPS resources
  void dispose() {
    stopTracking();
    _positionController.close();
  }
}
