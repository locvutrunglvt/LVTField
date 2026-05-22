import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

/// Represents a geographic feature (point, line, or polygon) with attributes
class FeatureModel {
  final String id;
  final String layerId;
  final List<LatLng> coordinates;
  final Map<String, dynamic> attributes;
  final DateTime collectedAt;
  final String? collectedBy;
  final double? gpsAccuracy;
  final bool isModified;
  final bool isSynced;
  final DateTime createdAt;
  final DateTime updatedAt;

  FeatureModel({
    String? id,
    required this.layerId,
    required this.coordinates,
    Map<String, dynamic>? attributes,
    DateTime? collectedAt,
    this.collectedBy,
    this.gpsAccuracy,
    this.isModified = false,
    this.isSynced = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  })
      : id = id ?? const Uuid().v4(),
        attributes = attributes ?? {},
        collectedAt = collectedAt ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Get the centroid of the feature
  LatLng get centroid {
    if (coordinates.isEmpty) return const LatLng(0, 0);
    if (coordinates.length == 1) return coordinates.first;

    double latSum = 0, lngSum = 0;
    for (final coord in coordinates) {
      latSum += coord.latitude;
      lngSum += coord.longitude;
    }
    return LatLng(latSum / coordinates.length, lngSum / coordinates.length);
  }

  /// Convert coordinates to GeoJSON geometry string
  String toGeoJsonGeometry(String geometryType) {
    switch (geometryType) {
      case 'point':
        final c = coordinates.first;
        return jsonEncode({
          'type': 'Point',
          'coordinates': [c.longitude, c.latitude],
        });
      case 'line':
        return jsonEncode({
          'type': 'LineString',
          'coordinates':
              coordinates.map((c) => [c.longitude, c.latitude]).toList(),
        });
      case 'polygon':
        final ring =
            coordinates.map((c) => [c.longitude, c.latitude]).toList();
        // Close the ring if not already closed
        if (ring.isNotEmpty && ring.first != ring.last) {
          ring.add(ring.first);
        }
        return jsonEncode({
          'type': 'Polygon',
          'coordinates': [ring],
        });
      default:
        return '{}';
    }
  }

  factory FeatureModel.fromMap(Map<String, dynamic> map) {
    // Parse coordinates from JSON string
    List<LatLng> coords = [];
    if (map['coordinates_json'] != null) {
      final coordList =
          jsonDecode(map['coordinates_json'] as String) as List<dynamic>;
      coords = coordList.map((c) {
        final pair = c as List<dynamic>;
        return LatLng(
          (pair[1] as num).toDouble(),
          (pair[0] as num).toDouble(),
        );
      }).toList();
    }

    // Parse attributes from JSON string
    Map<String, dynamic> attrs = {};
    if (map['attributes_json'] != null) {
      attrs =
          jsonDecode(map['attributes_json'] as String) as Map<String, dynamic>;
    }

    return FeatureModel(
      id: map['id'] as String,
      layerId: map['layer_id'] as String,
      coordinates: coords,
      attributes: attrs,
      collectedAt: DateTime.parse(map['collected_at'] as String),
      collectedBy: map['collected_by'] as String?,
      gpsAccuracy: (map['gps_accuracy'] as num?)?.toDouble(),
      isModified: (map['is_modified'] as int?) == 1,
      isSynced: (map['is_synced'] as int?) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    // Store coordinates as JSON array of [lng, lat] pairs
    final coordsJson = jsonEncode(
      coordinates.map((c) => [c.longitude, c.latitude]).toList(),
    );

    return {
      'id': id,
      'layer_id': layerId,
      'coordinates_json': coordsJson,
      'attributes_json': jsonEncode(attributes),
      'collected_at': collectedAt.toIso8601String(),
      'collected_by': collectedBy,
      'gps_accuracy': gpsAccuracy,
      'is_modified': isModified ? 1 : 0,
      'is_synced': isSynced ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  FeatureModel copyWith({
    List<LatLng>? coordinates,
    Map<String, dynamic>? attributes,
    String? collectedBy,
    double? gpsAccuracy,
    bool? isModified,
    bool? isSynced,
  }) {
    return FeatureModel(
      id: id,
      layerId: layerId,
      coordinates: coordinates ?? this.coordinates,
      attributes: attributes ?? this.attributes,
      collectedAt: collectedAt,
      collectedBy: collectedBy ?? this.collectedBy,
      gpsAccuracy: gpsAccuracy ?? this.gpsAccuracy,
      isModified: isModified ?? true,
      isSynced: isSynced ?? this.isSynced,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  @override
  String toString() => 'FeatureModel(id: $id, layerId: $layerId, coords: ${coordinates.length})';
}
