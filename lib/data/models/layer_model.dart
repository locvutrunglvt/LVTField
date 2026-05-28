import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

/// Geometry types supported by LVTField
enum GeometryType { point, line, polygon }

/// Represents a data layer within a project
class LayerModel {
  final String id;
  final String projectId;
  final String name;
  final GeometryType geometryType;
  final Map<String, dynamic> styleConfig;
  final int zOrder;
  final bool isVisible;
  final double opacity;
  final DateTime createdAt;

  LayerModel({
    String? id,
    required this.projectId,
    required this.name,
    required this.geometryType,
    Map<String, dynamic>? styleConfig,
    this.zOrder = 0,
    this.isVisible = true,
    this.opacity = 1.0,
    DateTime? createdAt,
  })
      : id = id ?? const Uuid().v4(),
        styleConfig = styleConfig ?? _defaultStyle(geometryType),
        createdAt = createdAt ?? DateTime.now();

  /// Default style based on geometry type
  static Map<String, dynamic> _defaultStyle(GeometryType type) {
    switch (type) {
      case GeometryType.point:
        return {
          'color': 0xFF00FF00,
          'size': 12.0,
          'icon': 'circle',
          'strokeColor': 0xFF00FF00,
          'strokeWidth': 1.5,
          'fillColor': 0xFF00FF00,
          'fillOpacity': 0.2,
          'labelMinZoom': 17.0,
        };
      case GeometryType.line:
        return {
          'color': 0xFF00FF00,
          'strokeColor': 0xFF00FF00,
          'width': 1.5,
          'strokeWidth': 1.5,
          'labelMinZoom': 17.0,
        };
      case GeometryType.polygon:
        return {
          'fillColor': 0xFF00FF00,
          'fillOpacity': 0.2,
          'strokeColor': 0xFF00FF00,
          'strokeWidth': 1.5,
          'labelMinZoom': 17.0,
        };
    }
  }

  /// Get the display color for this layer
  Color get displayColor {
    final colorValue = styleConfig['color'] ??
        styleConfig['strokeColor'] ??
        styleConfig['fillColor'] ??
        0xFF2D6A4F;
    return Color((colorValue as num).toInt());
  }

  // ---------------------------------------------------------------------------
  // Style helpers — read from styleConfig JSON
  // Note: JSON decode may return large ints as num, so we use (as num?)?.toInt()
  // ---------------------------------------------------------------------------

  /// Polygon/Line stroke color
  Color get strokeColor =>
      Color((styleConfig['strokeColor'] as num?)?.toInt() ??
            (styleConfig['color'] as num?)?.toInt() ??
            0xFF00FF7F);

  /// Polygon fill color
  Color get fillColor =>
      Color((styleConfig['fillColor'] as num?)?.toInt() ?? 0x3300FF00);

  /// Stroke width
  double get strokeWidth =>
      (styleConfig['strokeWidth'] as num?)?.toDouble() ??
      (styleConfig['width'] as num?)?.toDouble() ??
      1.0;

  /// Point color
  Color get pointColor =>
      Color((styleConfig['color'] as num?)?.toInt() ?? 0xFFE63946);

  /// Point size
  double get pointSize =>
      (styleConfig['size'] as num?)?.toDouble() ?? 12.0;

  // ---------------------------------------------------------------------------
  // Label helpers
  // ---------------------------------------------------------------------------

  /// Primary label field name (e.g. "Malo")
  String? get labelField => styleConfig['labelField'] as String?;

  /// Secondary label field (e.g. "DTich") — shown below primary
  String? get labelField2 => styleConfig['labelField2'] as String?;

  /// Raw QGIS label expression (when isExpression="1")
  /// Evaluated at render time with feature attributes
  String? get labelExpression => styleConfig['labelExpression'] as String?;

  /// Label suffix for field2 (e.g. " ha")
  String? get labelSuffix2 => styleConfig['labelSuffix2'] as String?;

  /// Label text color
  Color get labelColor =>
      Color((styleConfig['labelColor'] as num?)?.toInt() ?? 0xFF00FF00);

  /// Label font size
  double get labelFontSize =>
      (styleConfig['labelFontSize'] as num?)?.toDouble() ?? 12.0;

  /// Whether labels are enabled
  bool get labelsEnabled => labelField != null && labelField!.isNotEmpty;

  /// Minimum zoom level for label display (default 17 — avoids crash with large datasets)
  double get labelMinZoom =>
      (styleConfig['labelMinZoom'] as num?)?.toDouble() ?? 17.0;

  /// Whether label buffer (halo) is enabled
  bool get labelBufferEnabled =>
      (styleConfig['labelBufferDraw'] as bool?) ?? true;

  /// Label buffer size in pixels
  double get labelBufferSize =>
      (styleConfig['labelBufferSize'] as num?)?.toDouble() ?? 1.5;

  /// Label buffer color (default white)
  Color get labelBufferColor =>
      Color((styleConfig['labelBufferColor'] as num?)?.toInt() ?? 0xFFFFFFFF);

  /// Label placement mode (0=AroundPoint, 1=OverPoint, 2=Line, 3=Curved, 4=Horizontal)
  int get labelPlacement =>
      (styleConfig['labelPlacement'] as int?) ?? 0;

  /// Whether label font is bold
  bool get labelFontBold =>
      (styleConfig['labelFontBold'] as bool?) ?? true;

  /// Whether label font is italic
  bool get labelFontItalic =>
      (styleConfig['labelFontItalic'] as bool?) ?? false;

  /// Source format of this layer (e.g. 'kml', 'kmz', 'mbtiles', 'gpkg', 'shp')
  String? get sourceFormat => styleConfig['sourceFormat'] as String?;

  /// Layers from KML, KMZ, MBTiles, GeoTIFF are read-only (no add/edit/delete)
  bool get isReadOnly {
    final fmt = sourceFormat?.toLowerCase();
    return fmt == 'kml' || fmt == 'kmz' || fmt == 'mbtiles' || fmt == 'tiff';
  }

  factory LayerModel.fromMap(Map<String, dynamic> map) {
    return LayerModel(
      id: map['id'] as String,
      projectId: map['project_id'] as String,
      name: map['name'] as String,
      geometryType: GeometryType.values.firstWhere(
        (e) => e.name == (map['geometry_type'] as String),
      ),
      styleConfig: map['style_json'] != null
          ? jsonDecode(map['style_json'] as String) as Map<String, dynamic>
          : null,
      zOrder: (map['z_order'] as int?) ?? 0,
      isVisible: (map['is_visible'] as int?) == 1,
      opacity: (map['opacity'] as num?)?.toDouble() ?? 1.0,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'project_id': projectId,
      'name': name,
      'geometry_type': geometryType.name,
      'style_json': jsonEncode(styleConfig),
      'z_order': zOrder,
      'is_visible': isVisible ? 1 : 0,
      'opacity': opacity,
      'created_at': createdAt.toIso8601String(),
    };
  }

  LayerModel copyWith({
    String? name,
    Map<String, dynamic>? styleConfig,
    int? zOrder,
    bool? isVisible,
    double? opacity,
  }) {
    return LayerModel(
      id: id,
      projectId: projectId,
      name: name ?? this.name,
      geometryType: geometryType,
      styleConfig: styleConfig ?? this.styleConfig,
      zOrder: zOrder ?? this.zOrder,
      isVisible: isVisible ?? this.isVisible,
      opacity: opacity ?? this.opacity,
      createdAt: createdAt,
    );
  }

  @override
  String toString() => 'LayerModel(id: $id, name: $name, type: ${geometryType.name})';
}
