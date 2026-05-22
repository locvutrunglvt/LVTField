import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/gps_service.dart';

/// Global GPS service provider
final gpsServiceProvider = Provider<GpsService>((ref) {
  final service = GpsService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// GPS position stream provider
final gpsPositionProvider = StreamProvider<GpsPosition>((ref) {
  final gpsService = ref.watch(gpsServiceProvider);
  return gpsService.positionStream;
});

/// GPS tracking state provider
final gpsTrackingProvider = StateProvider<bool>((ref) => false);
