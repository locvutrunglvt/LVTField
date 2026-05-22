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
          'color': 0xFFE63946,
          'size': 12.0,
          'icon': 'circle',
        };
      case GeometryType.line:
        return {
          'color': 0xFF457B9D,
          'width': 3.0,
        };
      case GeometryType.polygon:
        return {
          'fillColor': 0x3300FF00,
          'strokeColor': 0xFF00FF7F,
          'strokeWidth': 1.0,
        };
    }
  }

  /// Get the display color for this layer
  Color get displayColor {
    final colorValue = styleConfig['color'] ??
        styleConfig['strokeColor'] ??
        styleConfig['fillColor'] ??
        0xFF2D6A4F;
    return Color(colorValue as int);
  }

  // ---------------------------------------------------------------------------
  // Style helpers — read from styleConfig JSON
  // ---------------------------------------------------------------------------

  /// Polygon/Line stroke color
  Color get strokeColor =>
      Color((styleConfig['strokeColor'] as int?) ?? 0xFF00FF7F);

  /// Polygon fill color
  Color get fillColor =>
      Color((styleConfig['fillColor'] as int?) ?? 0x3300FF00);

  /// Stroke width
  double get strokeWidth =>
      (styleConfig['strokeWidth'] as num?)?.toDouble() ?? 1.0;

  /// Point color
  Color get pointColor =>
      Color((styleConfig['color'] as int?) ?? 0xFFE63946);

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

  /// Label suffix for field2 (e.g. " ha")
  String? get labelSuffix2 => styleConfig['labelSuffix2'] as String?;

  /// Label text color
  Color get labelColor =>
      Color((styleConfig['labelColor'] as int?) ?? 0xFF00FF00);

  /// Label font size
  double get labelFontSize =>
      (styleConfig['labelFontSize'] as num?)?.toDouble() ?? 12.0;

  /// Whether labels are enabled
  bool get labelsEnabled => labelField != null && labelField!.isNotEmpty;

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
