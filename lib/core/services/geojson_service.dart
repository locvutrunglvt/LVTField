import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../data/models/feature_model.dart';
import '../../data/models/layer_model.dart';
import '../../data/models/form_field_model.dart';

/// Service for exporting data as GeoJSON
class GeoJsonService {
  /// Export a single layer as GeoJSON FeatureCollection
  static Future<String?> exportLayer({
    required LayerModel layer,
    required List<FeatureModel> features,
    String? outputPath,
    List<FormFieldModel>? fieldDefs,
  }) async {
    try {
      final geoJson = _buildFeatureCollection(layer, features, fieldDefs: fieldDefs);

      // Determine output path
      if (outputPath == null) {
        final appDir = await getApplicationDocumentsDirectory();
        final exportDir = Directory(p.join(appDir.path, 'LVTField', 'exports'));
        if (!await exportDir.exists()) {
          await exportDir.create(recursive: true);
        }

        final safeName = layer.name.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        outputPath = p.join(exportDir.path, '${safeName}_$timestamp.geojson');
      }

      final file = File(outputPath);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(geoJson),
      );

      debugPrint('GeoJSON: Exported ${features.length} features to $outputPath');
      return outputPath;
    } catch (e) {
      debugPrint('GeoJSON: Export failed - $e');
      return null;
    }
  }

  /// Build a GeoJSON FeatureCollection
  static Map<String, dynamic> _buildFeatureCollection(
    LayerModel layer,
    List<FeatureModel> features, {
    List<FormFieldModel>? fieldDefs,
  }) {
    final collection = <String, dynamic>{
      'type': 'FeatureCollection',
      'name': layer.name,
      'crs': {
        'type': 'name',
        'properties': {
          'name': 'urn:ogc:def:crs:OGC:1.3:CRS84',
        },
      },
      'features': features.map((f) => _buildFeature(f, layer.geometryType)).toList(),
    };

    // Embed field schema for sharing/import
    if (fieldDefs != null && fieldDefs.isNotEmpty) {
      collection['_field_schema'] = fieldDefs.map((f) => {
        'field_name': f.fieldName,
        'label': f.label,
        'field_type': f.fieldType.name,
        'sort_order': f.sortOrder,
        if (f.defaultValue != null) 'default_value': f.defaultValue,
        if (f.hint != null) 'hint': f.hint,
        if (f.autoSource != null) 'auto_source': f.autoSource,
        if (f.isRequired) 'is_required': true,
        if (f.options != null) 'options': f.options,
      }).toList();
      collection['_geometry_type'] = layer.geometryType.name;
    }

    return collection;
  }

  /// Build a single GeoJSON Feature
  static Map<String, dynamic> _buildFeature(
    FeatureModel feature,
    GeometryType geometryType,
  ) {
    return {
      'type': 'Feature',
      'properties': {
        'id': feature.id,
        'collected_at': feature.collectedAt.toIso8601String(),
        'collected_by': feature.collectedBy,
        'gps_accuracy': feature.gpsAccuracy,
        ...feature.attributes,
      },
      'geometry': _buildGeometry(feature, geometryType),
    };
  }

  /// Build GeoJSON geometry based on type
  static Map<String, dynamic> _buildGeometry(
    FeatureModel feature,
    GeometryType geometryType,
  ) {
    switch (geometryType) {
      case GeometryType.point:
        final c = feature.coordinates.first;
        return {
          'type': 'Point',
          'coordinates': [c.longitude, c.latitude],
        };
      case GeometryType.line:
        return {
          'type': 'LineString',
          'coordinates': feature.coordinates
              .map((c) => [c.longitude, c.latitude])
              .toList(),
        };
      case GeometryType.polygon:
        final ring = feature.coordinates
            .map((c) => [c.longitude, c.latitude])
            .toList();
        // Ensure polygon is closed
        if (ring.isNotEmpty &&
            (ring.first[0] != ring.last[0] || ring.first[1] != ring.last[1])) {
          ring.add(List.from(ring.first));
        }
        return {
          'type': 'Polygon',
          'coordinates': [ring],
        };
    }
  }

  /// Calculate area of a polygon in hectares using Shoelace formula
  static double calculateAreaHectares(List<List<double>> coordinates) {
    if (coordinates.length < 3) return 0;

    double area = 0;
    final n = coordinates.length;

    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      // Convert degrees to approximate meters at equator
      final x1 = coordinates[i][0] * 111320;
      final y1 = coordinates[i][1] * 110540;
      final x2 = coordinates[j][0] * 111320;
      final y2 = coordinates[j][1] * 110540;

      area += x1 * y2 - x2 * y1;
    }

    area = area.abs() / 2;
    return area / 10000; // Convert m² to hectares
  }
}
