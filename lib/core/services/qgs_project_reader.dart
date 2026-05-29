// QGIS .qgs project file reader for LVTField
// Parses XML to extract layer configurations, styles, and datasource paths
// Author: Lộc Vũ Trung

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

/// Parsed layer configuration from a .qgs project file
class QgsLayerConfig {
  final String name;
  final String dataSource;
  final String? geometryTypeStr;
  final String? labelingXml;
  final String? rendererXml;
  final Map<String, dynamic> parsedStyle;

  QgsLayerConfig({
    required this.name,
    required this.dataSource,
    this.geometryTypeStr,
    this.labelingXml,
    this.rendererXml,
    this.parsedStyle = const {},
  });

  /// Determine geometry type from QGIS string
  String get geometryType {
    switch (geometryTypeStr?.toLowerCase()) {
      case 'point':
      case 'multipoint':
        return 'point';
      case 'line':
      case 'linestring':
      case 'multilinestring':
        return 'line';
      case 'polygon':
      case 'multipolygon':
        return 'polygon';
      default:
        return 'point';
    }
  }

  /// Extract GPKG file path from datasource string
  /// Format: "./path/to/file.gpkg|layername=tablename" or just "./path/to/file.gpkg"
  String? get gpkgPath {
    final ds = dataSource;
    // Remove |layername=... suffix
    final pipeIndex = ds.indexOf('|');
    final path = pipeIndex >= 0 ? ds.substring(0, pipeIndex) : ds;
    if (path.toLowerCase().endsWith('.gpkg')) return path;
    return null;
  }

  /// Extract table name from datasource
  String? get tableName {
    final match = RegExp(r'layername=(\w+)').firstMatch(dataSource);
    return match?.group(1);
  }
}

/// Parsed .qgs project
class QgsProject {
  final String? title;
  final List<QgsLayerConfig> layers;

  QgsProject({this.title, required this.layers});
}

/// Reads and parses QGIS .qgs project files
class QgsProjectReader {

  /// Parse a .qgs XML file and extract layer configurations
  Future<QgsProject> parse(String qgsFilePath) async {
    debugPrint('QgsProjectReader: Parsing $qgsFilePath');

    final file = File(qgsFilePath);
    if (!await file.exists()) {
      throw Exception('File not found: $qgsFilePath');
    }

    final xmlContent = await file.readAsString();
    final doc = XmlDocument.parse(xmlContent);

    // Extract project title
    String? title;
    for (final titleEl in doc.findAllElements('title')) {
      title = titleEl.innerText;
      if (title.isNotEmpty) break;
    }

    final layers = <QgsLayerConfig>[];

    for (final mapLayer in doc.findAllElements('maplayer')) {
      try {
        // Only process vector layers
        final layerType = mapLayer.getAttribute('type');
        if (layerType != 'vector') continue;

        // Layer name
        final nameEl = mapLayer.findElements('layername').firstOrNull;
        final name = nameEl?.innerText ?? 'Unknown';

        // Data source
        final dsEl = mapLayer.findElements('datasource').firstOrNull;
        final dataSource = dsEl?.innerText ?? '';
        if (dataSource.isEmpty) continue;

        // Geometry type
        final geomType = mapLayer.getAttribute('geometry');

        // Extract <labeling> XML fragment
        String? labelingXml;
        final labelingEl = mapLayer.findElements('labeling').firstOrNull;
        if (labelingEl != null) {
          labelingXml = labelingEl.toXmlString();
        }

        // Extract <renderer-v2> XML fragment
        String? rendererXml;
        final rendererEl = mapLayer.findElements('renderer-v2').firstOrNull;
        if (rendererEl != null) {
          rendererXml = rendererEl.toXmlString();
        }

        // Parse style from labeling + renderer XML
        final parsedStyle = <String, dynamic>{};

        // Parse labeling
        if (labelingEl != null) {
          _parseLabelingElement(labelingEl, parsedStyle);
        }

        // Parse renderer for colors
        if (rendererEl != null) {
          _parseRendererElement(rendererEl, parsedStyle, geomType);
        }

        layers.add(QgsLayerConfig(
          name: name,
          dataSource: dataSource,
          geometryTypeStr: geomType,
          labelingXml: labelingXml,
          rendererXml: rendererXml,
          parsedStyle: parsedStyle,
        ));

        debugPrint('QgsProjectReader: Found layer "$name" geom=$geomType ds=$dataSource');
      } catch (e) {
        debugPrint('QgsProjectReader: Failed to parse maplayer: $e');
      }
    }

    debugPrint('QgsProjectReader: Parsed ${layers.length} vector layers');
    return QgsProject(title: title, layers: layers);
  }

  /// Parse <labeling> element into style config
  void _parseLabelingElement(XmlElement labeling, Map<String, dynamic> style) {
    final labelType = labeling.getAttribute('type');
    if (labelType == null) return;

    // Check enabled
    final enabled = labeling.getAttribute('enabled');
    if (enabled == '0') return;

    for (final textStyle in labeling.findAllElements('text-style')) {
      // Field name
      final fieldName = textStyle.getAttribute('fieldName');
      if (fieldName == null || fieldName.isEmpty) continue;

      final isExpr = textStyle.getAttribute('isExpression');
      if (isExpr == '1') {
        style['labelExpression'] = fieldName;
        // Extract first field as fallback
        final fieldMatch = RegExp(r'"([^"]+)"').firstMatch(fieldName);
        if (fieldMatch != null) {
          style['labelField'] = fieldMatch.group(1);
        }
      } else {
        style['labelField'] = fieldName;
      }

      // Font size
      final fontSizeStr = textStyle.getAttribute('fontSize');
      if (fontSizeStr != null) {
        final fs = double.tryParse(fontSizeStr);
        if (fs != null) style['labelFontSize'] = fs.clamp(8.0, 24.0);
      }

      // Text color
      final textColor = textStyle.getAttribute('textColor');
      if (textColor != null) {
        final rgba = _parseQgisColor(textColor);
        if (rgba != null) style['labelColor'] = rgba;
      }

      // Font bold/italic
      if (textStyle.getAttribute('fontBold') == '1') {
        style['labelFontBold'] = true;
      }
      if (textStyle.getAttribute('fontItalic') == '1') {
        style['labelFontItalic'] = true;
      }

      // Text buffer (halo)
      for (final buf in textStyle.findAllElements('text-buffer')) {
        if (buf.getAttribute('bufferDraw') == '1') {
          style['labelBufferDraw'] = true;
          final bsStr = buf.getAttribute('bufferSize');
          if (bsStr != null) {
            final bs = double.tryParse(bsStr);
            if (bs != null) style['labelBufferSize'] = (bs * 3.0).clamp(0.5, 10.0);
          }
          final bcStr = buf.getAttribute('bufferColor');
          if (bcStr != null) {
            final rgba = _parseQgisColor(bcStr);
            if (rgba != null) style['labelBufferColor'] = rgba;
          }
        }
        break;
      }

      break; // Only first text-style
    }

    // Placement
    for (final settings in labeling.findAllElements('settings')) {
      for (final placement in settings.findAllElements('placement')) {
        final pStr = placement.getAttribute('placement');
        if (pStr != null) {
          final p = int.tryParse(pStr);
          if (p != null) style['labelPlacement'] = p;
        }
        break;
      }
      break;
    }
  }

  /// Parse <renderer-v2> element for symbology colors
  void _parseRendererElement(XmlElement renderer, Map<String, dynamic> style, String? geomType) {
    // Find first symbol → first layer → extract color properties
    for (final symbol in renderer.findAllElements('symbol')) {
      for (final layer in symbol.findAllElements('layer')) {
        for (final prop in layer.findAllElements('prop')) {
          final k = prop.getAttribute('k') ?? prop.getAttribute('name') ?? '';
          final v = prop.getAttribute('v') ?? prop.getAttribute('value') ?? '';

          switch (k) {
            case 'color':
              final rgba = _parseQgisColor(v);
              if (rgba != null) {
                if (geomType?.toLowerCase() == 'polygon') {
                  style['fillColor'] = rgba;
                } else {
                  style['color'] = rgba;
                  style['strokeColor'] = rgba;
                }
              }
              break;
            case 'outline_color':
            case 'line_color':
              final rgba = _parseQgisColor(v);
              if (rgba != null) style['strokeColor'] = rgba;
              break;
            case 'outline_width':
            case 'line_width':
              final w = double.tryParse(v);
              if (w != null) style['strokeWidth'] = (w * 3.0).clamp(0.5, 10.0);
              break;
            case 'size':
              final s = double.tryParse(v);
              if (s != null && geomType?.toLowerCase() == 'point') {
                style['size'] = (s * 3.0).clamp(4.0, 30.0);
              }
              break;
          }
        }
        break; // Only first layer
      }
      break; // Only first symbol
    }

    // Also check <Option> format (QGIS 3.28+)
    for (final symbol in renderer.findAllElements('symbol')) {
      for (final layer in symbol.findAllElements('layer')) {
        for (final opt in layer.findAllElements('Option')) {
          final name = opt.getAttribute('name') ?? '';
          final value = opt.getAttribute('value') ?? '';
          if (value.isEmpty) continue;

          switch (name) {
            case 'color':
              final rgba = _parseQgisColor(value);
              if (rgba != null) {
                if (geomType?.toLowerCase() == 'polygon') {
                  style['fillColor'] = rgba;
                } else {
                  style['color'] = rgba;
                  style['strokeColor'] = rgba;
                }
              }
              break;
            case 'outline_color':
            case 'line_color':
              final rgba = _parseQgisColor(value);
              if (rgba != null) style['strokeColor'] = rgba;
              break;
          }
        }
        break;
      }
      break;
    }
  }

  /// Parse QGIS color string "r,g,b,a" to Flutter ARGB int
  int? _parseQgisColor(String colorStr) {
    final parts = colorStr.split(',').map((s) => int.tryParse(s.trim())).toList();
    if (parts.length >= 3 && parts.every((p) => p != null)) {
      final r = parts[0]!;
      final g = parts[1]!;
      final b = parts[2]!;
      final a = parts.length >= 4 ? parts[3]! : 255;
      return (a << 24) | (r << 16) | (g << 8) | b;
    }
    return null;
  }
}
