// Import service for LVTField project data
// Supports GeoJSON and .lvtfield package formats
// Author: Lộc Vũ Trung

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart' as xml;
import 'package:latlong2/latlong.dart';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'crs_service.dart';
import '../../data/database/app_database.dart';
import '../../data/models/project_model.dart';
import '../../data/models/layer_model.dart';
import '../../data/models/feature_model.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/layer_repository.dart';
import '../../data/repositories/feature_repository.dart';
import '../../data/models/form_field_model.dart';

/// Result of an import operation
class ImportResult {
  final bool success;
  final String? projectId;
  final String? layerId;
  final String? errorMessage;
  final int featureCount;
  final int layerCount;

  const ImportResult({
    required this.success,
    this.projectId,
    this.layerId,
    this.errorMessage,
    this.featureCount = 0,
    this.layerCount = 0,
  });
}

/// Progress callback: (current, total, statusMessage)
typedef ImportProgressCallback = void Function(int current, int total, String message);

/// Service for importing GeoJSON files and .lvtfield packages
class ImportService {
  final ProjectRepository _projectRepo = ProjectRepository();
  final LayerRepository _layerRepo = LayerRepository();
  final FeatureRepository _featureRepo = FeatureRepository();

  /// Import a GeoJSON file as a new layer in an existing project
  ///
  /// Parses the FeatureCollection, auto-detects geometry type,
  /// and creates a new layer with all features.
  Future<ImportResult> importGeoJson(String filePath, String projectId) async {
    try {
      // Verify the project exists
      final project = await _projectRepo.getById(projectId);
      if (project == null) {
        return const ImportResult(
          success: false,
          errorMessage: 'Không tìm thấy dự án',
        );
      }

      // Read and parse the GeoJSON file
      final file = File(filePath);
      if (!await file.exists()) {
        return const ImportResult(
          success: false,
          errorMessage: 'File không tồn tại',
        );
      }

      final content = await file.readAsString();
      final geoJson = jsonDecode(content) as Map<String, dynamic>;

      // Validate GeoJSON structure
      if (geoJson['type'] != 'FeatureCollection') {
        return const ImportResult(
          success: false,
          errorMessage: 'File không phải GeoJSON FeatureCollection hợp lệ',
        );
      }

      final geoFeatures = geoJson['features'] as List<dynamic>? ?? [];
      if (geoFeatures.isEmpty) {
        return const ImportResult(
          success: false,
          errorMessage: 'File GeoJSON không có đối tượng nào',
        );
      }

      // Auto-detect geometry type from the first feature
      final geometryType = _detectGeometryType(geoFeatures);
      if (geometryType == null) {
        return const ImportResult(
          success: false,
          errorMessage: 'Không thể xác định loại hình học',
        );
      }

      // Determine layer name from GeoJSON or filename
      final layerName = (geoJson['name'] as String?) ??
          _extractLayerName(filePath);

      // Check for lvtfield metadata (from package export)
      final metadata = geoJson['lvtfield_metadata'] as Map<String, dynamic>?;
      Map<String, dynamic>? styleConfig;
      int zOrder = 0;
      double opacity = 1.0;

      if (metadata != null) {
        styleConfig = metadata['style_config'] as Map<String, dynamic>?;
        zOrder = (metadata['z_order'] as int?) ?? 0;
        opacity = (metadata['opacity'] as num?)?.toDouble() ?? 1.0;
      }

      // Create the layer
      final layer = LayerModel(
        projectId: projectId,
        name: layerName,
        geometryType: geometryType,
        styleConfig: styleConfig,
        zOrder: zOrder,
        opacity: opacity,
      );
      await _layerRepo.insert(layer);

      // Parse and insert features
      int importedCount = 0;
      for (final geoFeature in geoFeatures) {
        final featureMap = geoFeature as Map<String, dynamic>;
        final feature = _parseGeoJsonFeature(featureMap, layer.id);
        if (feature != null) {
          await _featureRepo.insert(feature);
          importedCount++;
        }
      }

      debugPrint('ImportService: Imported $importedCount features '
          'into layer "${layer.name}" (${geometryType.name})');

      return ImportResult(
        success: true,
        projectId: projectId,
        layerId: layer.id,
        featureCount: importedCount,
        layerCount: 1,
      );
    } catch (e) {
      debugPrint('ImportService: importGeoJson failed - $e');
      return ImportResult(
        success: false,
        errorMessage: 'Lỗi nhập GeoJSON: $e',
      );
    }
  }

  /// Import a .lvtfield package (ZIP archive)
  ///
  /// Extracts the archive and creates a new project with all
  /// layers, features, form definitions, and media files.
  Future<ImportResult> importLvtFieldPackage(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return const ImportResult(
          success: false,
          errorMessage: 'File không tồn tại',
        );
      }

      // Read and decode the ZIP archive
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Find and parse project.json
      final projectFile = archive.findFile('project.json');
      if (projectFile == null) {
        return const ImportResult(
          success: false,
          errorMessage: 'File .lvtfield không hợp lệ: thiếu project.json',
        );
      }

      final projectJson = jsonDecode(
        utf8.decode(projectFile.content as List<int>),
      ) as Map<String, dynamic>;

      // Create new project (with new ID to avoid conflicts)
      final project = ProjectModel(
        name: projectJson['name'] as String? ?? 'Dự án nhập',
        description: projectJson['description'] as String? ?? '',
        crs: projectJson['crs'] as String? ?? 'EPSG:4326',
      );
      await _projectRepo.insert(project);

      int totalFeatures = 0;
      int totalLayers = 0;

      // Map old layer IDs to new IDs (for form field association)
      final layerIdMap = <String, String>{};

      // Import each GeoJSON layer file
      for (final archiveFile in archive) {
        if (archiveFile.name.startsWith('layers/') &&
            archiveFile.name.endsWith('.geojson')) {
          final geoJsonStr = utf8.decode(archiveFile.content as List<int>);
          final geoJson = jsonDecode(geoJsonStr) as Map<String, dynamic>;

          final geoFeatures = geoJson['features'] as List<dynamic>? ?? [];
          final geometryType = _detectGeometryType(geoFeatures);
          if (geometryType == null) continue;

          // Extract metadata if present
          final metadata = geoJson['lvtfield_metadata'] as Map<String, dynamic>?;
          String? oldLayerId;
          Map<String, dynamic>? styleConfig;
          int zOrder = 0;
          double opacity = 1.0;

          if (metadata != null) {
            oldLayerId = metadata['layer_id'] as String?;
            styleConfig = metadata['style_config'] as Map<String, dynamic>?;
            zOrder = (metadata['z_order'] as int?) ?? 0;
            opacity = (metadata['opacity'] as num?)?.toDouble() ?? 1.0;
          }

          final layerName = (geoJson['name'] as String?) ??
              _extractLayerNameFromArchive(archiveFile.name);

          // Create the layer
          final layer = LayerModel(
            projectId: project.id,
            name: layerName,
            geometryType: geometryType,
            styleConfig: styleConfig,
            zOrder: zOrder,
            opacity: opacity,
          );
          await _layerRepo.insert(layer);
          totalLayers++;

          // Map old ID to new ID
          if (oldLayerId != null) {
            layerIdMap[oldLayerId] = layer.id;
          }

          // Parse and insert features
          for (final geoFeature in geoFeatures) {
            final featureMap = geoFeature as Map<String, dynamic>;
            final feature = _parseGeoJsonFeature(featureMap, layer.id);
            if (feature != null) {
              await _featureRepo.insert(feature);
              totalFeatures++;
            }
          }
        }
      }

      // Import form field definitions
      final formsFile = archive.findFile('forms.json');
      if (formsFile != null) {
        await _importFormFields(formsFile, layerIdMap);
      }

      // Import media files (copy to app's media directory)
      await _importMediaFiles(archive, project.id);

      debugPrint('ImportService: Imported package - '
          '$totalLayers layers, $totalFeatures features');

      return ImportResult(
        success: true,
        projectId: project.id,
        featureCount: totalFeatures,
        layerCount: totalLayers,
      );
    } catch (e) {
      debugPrint('ImportService: importLvtFieldPackage failed - $e');
      return ImportResult(
        success: false,
        errorMessage: 'Lỗi nhập gói LVTField: $e',
      );
    }
  }

  // ===========================================================================
  // KML Import
  // ===========================================================================

  /// Import a KML file as a new layer
  Future<ImportResult> importKML(String filePath, String projectId, {ImportProgressCallback? onProgress, String sourceFormat = 'kml'}) async {
    try {
      final project = await _projectRepo.getById(projectId);
      if (project == null) {
        return const ImportResult(success: false, errorMessage: 'Không tìm thấy dự án');
      }

      final file = File(filePath);
      if (!await file.exists()) {
        return const ImportResult(success: false, errorMessage: 'File không tồn tại');
      }

      final content = await file.readAsString(encoding: utf8);
      final document = xml.XmlDocument.parse(content);

      // ── Parse KML Style definitions ──
      final styleMap = _parseKmlStyles(document);

      // Find all Placemarks
      final placemarks = document.findAllElements('Placemark').toList();
      if (placemarks.isEmpty) {
        return const ImportResult(success: false, errorMessage: 'KML không có Placemark nào');
      }

      // Detect geometry type from first placemark
      GeometryType? geoType;
      for (final pm in placemarks) {
        if (pm.findAllElements('Point').isNotEmpty) {
          geoType = GeometryType.point;
          break;
        } else if (pm.findAllElements('LineString').isNotEmpty) {
          geoType = GeometryType.line;
          break;
        } else if (pm.findAllElements('Polygon').isNotEmpty) {
          geoType = GeometryType.polygon;
          break;
        }
      }
      if (geoType == null) {
        return const ImportResult(success: false, errorMessage: 'Không tìm thấy hình học trong KML');
      }

      // ── Build styleConfig from KML styles ──
      final kmlStyle = _resolveKmlStyleForLayer(document, placemarks, styleMap);
      final baseLayer = LayerModel(
        projectId: projectId,
        name: _extractLayerName(filePath).replaceAll('.kml', ''),
        geometryType: geoType,
      );
      // Merge KML style + mark source format → read-only
      final mergedStyle = <String, dynamic>{
        ...baseLayer.styleConfig,
        ...kmlStyle,
        'sourceFormat': sourceFormat,
      };
      final layer = baseLayer.copyWith(styleConfig: mergedStyle);
      await _layerRepo.insert(layer);

      int importedCount = 0;
      final totalPlacemarks = placemarks.length;
      onProgress?.call(0, totalPlacemarks, 'Đang phân tích $totalPlacemarks đối tượng...');
      for (final pm in placemarks) {
        List<LatLng>? coords;
        final nameEl = pm.findElements('name').firstOrNull;
        final descEl = pm.findElements('description').firstOrNull;

        // Parse geometry
        final pointEl = pm.findAllElements('Point').firstOrNull;
        final lineEl = pm.findAllElements('LineString').firstOrNull;
        final polyEl = pm.findAllElements('Polygon').firstOrNull;

        if (pointEl != null) {
          final coordStr = pointEl.findElements('coordinates').firstOrNull?.innerText ?? '';
          coords = _parseKmlCoordinates(coordStr);
        } else if (lineEl != null) {
          final coordStr = lineEl.findElements('coordinates').firstOrNull?.innerText ?? '';
          coords = _parseKmlCoordinates(coordStr);
        } else if (polyEl != null) {
          final outerBoundary = polyEl.findAllElements('outerBoundaryIs').firstOrNull;
          final ring = outerBoundary?.findAllElements('LinearRing').firstOrNull;
          final coordStr = ring?.findElements('coordinates').firstOrNull?.innerText ?? '';
          coords = _parseKmlCoordinates(coordStr);
          // Remove closing vertex if duplicate
          if (coords.length > 1 &&
              coords.first.latitude == coords.last.latitude &&
              coords.first.longitude == coords.last.longitude) {
            coords.removeLast();
          }
        }

        if (coords == null || coords.isEmpty) continue;

        // Parse ExtendedData attributes
        final attrs = <String, dynamic>{};
        if (nameEl != null) attrs['name'] = nameEl.innerText;
        if (descEl != null) attrs['description'] = descEl.innerXml;
        for (final dataEl in pm.findAllElements('Data')) {
          final key = dataEl.getAttribute('name') ?? 'field';
          final value = dataEl.findElements('value').firstOrNull?.innerText ?? '';
          attrs[key] = value;
        }

        final feature = FeatureModel(
          layerId: layer.id,
          coordinates: coords,
          attributes: attrs,
        );
        await _featureRepo.insert(feature);
        importedCount++;
        if (importedCount % 50 == 0 || importedCount == totalPlacemarks) {
          onProgress?.call(importedCount, totalPlacemarks, 'Đã nhập $importedCount/$totalPlacemarks');
        }
      }

      debugPrint('ImportService: Imported $importedCount features from KML');
      return ImportResult(
        success: true,
        projectId: projectId,
        layerId: layer.id,
        featureCount: importedCount,
        layerCount: 1,
      );
    } catch (e) {
      debugPrint('ImportService: importKML failed - $e');
      return ImportResult(success: false, errorMessage: 'Lỗi nhập KML: $e');
    }
  }

  // ── KML Style Parsing Helpers ──

  /// Parse all <Style> and <StyleMap> elements from KML into a map keyed by id
  Map<String, Map<String, dynamic>> _parseKmlStyles(xml.XmlDocument doc) {
    final result = <String, Map<String, dynamic>>{};

    for (final styleEl in doc.findAllElements('Style')) {
      final id = styleEl.getAttribute('id') ?? '';
      result[id] = _extractKmlStyle(styleEl);
    }

    // StyleMap → resolve to its "normal" style
    for (final sm in doc.findAllElements('StyleMap')) {
      final id = sm.getAttribute('id') ?? '';
      for (final pair in sm.findAllElements('Pair')) {
        final key = pair.findElements('key').firstOrNull?.innerText ?? '';
        if (key == 'normal') {
          final styleUrl = pair.findElements('styleUrl').firstOrNull?.innerText ?? '';
          final refId = styleUrl.replaceFirst('#', '');
          if (result.containsKey(refId)) {
            result[id] = result[refId]!;
          }
          // Also check inline Style in Pair
          final inlineStyle = pair.findAllElements('Style').firstOrNull;
          if (inlineStyle != null) {
            result[id] = _extractKmlStyle(inlineStyle);
          }
        }
      }
    }

    return result;
  }

  /// Extract style properties from a <Style> element
  Map<String, dynamic> _extractKmlStyle(xml.XmlElement styleEl) {
    final style = <String, dynamic>{};

    // LineStyle
    final lineStyle = styleEl.findAllElements('LineStyle').firstOrNull;
    if (lineStyle != null) {
      final colorStr = lineStyle.findElements('color').firstOrNull?.innerText;
      if (colorStr != null) {
        style['strokeColor'] = _kmlColorToFlutter(colorStr);
        style['color'] = style['strokeColor']; // for lines
      }
      final width = lineStyle.findElements('width').firstOrNull?.innerText;
      if (width != null) {
        style['strokeWidth'] = double.tryParse(width) ?? 1.0;
        style['width'] = style['strokeWidth'];
      }
    }

    // PolyStyle
    final polyStyle = styleEl.findAllElements('PolyStyle').firstOrNull;
    if (polyStyle != null) {
      final colorStr = polyStyle.findElements('color').firstOrNull?.innerText;
      if (colorStr != null) {
        style['fillColor'] = _kmlColorToFlutter(colorStr);
      }
      final fill = polyStyle.findElements('fill').firstOrNull?.innerText;
      if (fill == '0') {
        style['fillColor'] = 0x00000000; // transparent
      }
    }

    // IconStyle
    final iconStyle = styleEl.findAllElements('IconStyle').firstOrNull;
    if (iconStyle != null) {
      final colorStr = iconStyle.findElements('color').firstOrNull?.innerText;
      if (colorStr != null) {
        style['color'] = _kmlColorToFlutter(colorStr);
      }
      final scale = iconStyle.findElements('scale').firstOrNull?.innerText;
      if (scale != null) {
        style['size'] = (double.tryParse(scale) ?? 1.0) * 12.0;
      }
    }

    // LabelStyle
    final labelStyle = styleEl.findAllElements('LabelStyle').firstOrNull;
    if (labelStyle != null) {
      final colorStr = labelStyle.findElements('color').firstOrNull?.innerText;
      if (colorStr != null) {
        style['labelColor'] = _kmlColorToFlutter(colorStr);
      }
    }

    return style;
  }

  /// Convert KML AABBGGRR color to Flutter AARRGGBB int
  int _kmlColorToFlutter(String kmlColor) {
    final hex = kmlColor.trim().toLowerCase().replaceFirst('#', '');
    if (hex.length < 8) return 0xFF00FF00; // default green
    // KML format: AABBGGRR → Flutter: AARRGGBB
    final aa = hex.substring(0, 2);
    final bb = hex.substring(2, 4);
    final gg = hex.substring(4, 6);
    final rr = hex.substring(6, 8);
    return int.parse('$aa$rr$gg$bb', radix: 16);
  }

  /// Resolve the dominant KML style for the whole layer
  /// (uses first Placemark's style, or the first defined Style)
  Map<String, dynamic> _resolveKmlStyleForLayer(
    xml.XmlDocument doc,
    List<xml.XmlElement> placemarks,
    Map<String, Map<String, dynamic>> styleMap,
  ) {
    // Try first placemark's styleUrl
    for (final pm in placemarks) {
      final styleUrl = pm.findElements('styleUrl').firstOrNull?.innerText ?? '';
      final refId = styleUrl.replaceFirst('#', '');
      if (styleMap.containsKey(refId) && styleMap[refId]!.isNotEmpty) {
        return styleMap[refId]!;
      }
      // Inline style on placemark
      final inlineStyle = pm.findAllElements('Style').firstOrNull;
      if (inlineStyle != null) {
        final s = _extractKmlStyle(inlineStyle);
        if (s.isNotEmpty) return s;
      }
    }
    // Fallback: first defined style
    if (styleMap.isNotEmpty) {
      final first = styleMap.values.firstWhere((s) => s.isNotEmpty, orElse: () => {});
      if (first.isNotEmpty) return first;
    }
    return {};
  }

  /// Parse KML coordinate string: 'lng,lat,alt lng,lat,alt'
  List<LatLng> _parseKmlCoordinates(String coordString) {
    return coordString
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty && s.contains(','))
        .map((s) {
      final parts = s.split(',');
      return LatLng(double.parse(parts[1]), double.parse(parts[0]));
    }).toList();
  }

  // ===========================================================================
  // KMZ Import
  // ===========================================================================

  /// Import a KMZ file (ZIP containing KML)
  Future<ImportResult> importKMZ(String filePath, String projectId, {ImportProgressCallback? onProgress}) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return const ImportResult(success: false, errorMessage: 'File không tồn tại');
      }

      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Find KML file inside
      ArchiveFile? kmlFile;
      for (final f in archive) {
        if (f.name.toLowerCase().endsWith('.kml')) {
          kmlFile = f;
          break;
        }
      }
      if (kmlFile == null) {
        return const ImportResult(success: false, errorMessage: 'KMZ không chứa file KML');
      }

      // Write KML to temp file and import
      final tempDir = await Directory.systemTemp.createTemp('lvtfield_kmz');
      final tempKml = File('${tempDir.path}/doc.kml');
      await tempKml.writeAsBytes(kmlFile.content as List<int>);

      final result = await importKML(tempKml.path, projectId, onProgress: onProgress, sourceFormat: 'kmz');

      // Cleanup
      await tempDir.delete(recursive: true);

      return result;
    } catch (e) {
      debugPrint('ImportService: importKMZ failed - $e');
      return ImportResult(success: false, errorMessage: 'Lỗi nhập KMZ: $e');
    }
  }

  // ===========================================================================
  // SHP Import (basic)
  // ===========================================================================

  /// Import a basic ESRI Shapefile (.shp)
  /// Supports Point(1), PolyLine(3), Polygon(5) shape types.
  /// Reads .dbf for attributes if present.
  Future<ImportResult> importSHP(String filePath, String projectId, {ImportProgressCallback? onProgress}) async {
    try {
      final project = await _projectRepo.getById(projectId);
      if (project == null) {
        return const ImportResult(success: false, errorMessage: 'Không tìm thấy dự án');
      }

      final shpFile = File(filePath);
      if (!await shpFile.exists()) {
        return const ImportResult(success: false, errorMessage: 'File .shp không tồn tại');
      }

      final bytes = await shpFile.readAsBytes();
      final data = ByteData.sublistView(bytes);

      // Validate header
      final fileCode = data.getInt32(0, Endian.big);
      if (fileCode != 9994) {
        return const ImportResult(success: false, errorMessage: 'File không phải định dạng SHP hợp lệ');
      }

      final shapeType = data.getInt32(32, Endian.little);
      GeometryType geoType;
      switch (shapeType) {
        case 1: // Point
        case 11: // PointZ
        case 21: // PointM
          geoType = GeometryType.point;
          break;
        case 3: // PolyLine
        case 13: // PolyLineZ
        case 23: // PolyLineM
          geoType = GeometryType.line;
          break;
        case 5: // Polygon
        case 15: // PolygonZ
        case 25: // PolygonM
          geoType = GeometryType.polygon;
          break;
        default:
          return ImportResult(success: false, errorMessage: 'Loại hình học SHP không hỗ trợ: $shapeType');
      }

      // Read DBF attributes if available
      final dbfPath = filePath.replaceAll(RegExp(r'\.shp$', caseSensitive: false), '.dbf');
      List<Map<String, dynamic>>? dbfRecords;
      final dbfFile = File(dbfPath);
      if (await dbfFile.exists()) {
        dbfRecords = await _readDbfRecords(dbfFile);
      }

      final layerName = _extractLayerName(filePath).replaceAll('.shp', '');
      final layer = LayerModel(
        projectId: projectId,
        name: layerName,
        geometryType: geoType,
      );
      await _layerRepo.insert(layer);

      // Parse records
      int offset = 100; // SHP header is 100 bytes
      int recordIndex = 0;
      int importedCount = 0;
      final totalEstimate = dbfRecords?.length ?? 0;
      onProgress?.call(0, totalEstimate, 'Đang nhập đối tượng...');

      while (offset < bytes.length - 8) {
        try {
          // Record header
          // final recordNum = data.getInt32(offset, Endian.big);
          final contentLength = data.getInt32(offset + 4, Endian.big) * 2;
          offset += 8;

          if (offset + contentLength > bytes.length) break;

          final recShapeType = data.getInt32(offset, Endian.little);
          List<LatLng> coords = [];

          if (recShapeType == 0) {
            // Null shape
            offset += contentLength;
            recordIndex++;
            continue;
          }

          switch (geoType) {
            case GeometryType.point:
              final x = data.getFloat64(offset + 4, Endian.little);
              final y = data.getFloat64(offset + 12, Endian.little);
              coords = [LatLng(y, x)];
              break;
            case GeometryType.line:
            case GeometryType.polygon:
              // Skip bounding box (32 bytes), read numParts + numPoints
              final numParts = data.getInt32(offset + 36, Endian.little);
              final numPoints = data.getInt32(offset + 40, Endian.little);
              // Skip parts array
              final pointsOffset = offset + 44 + (numParts * 4);
              // Read points (first part only for simplicity)
              for (int i = 0; i < numPoints; i++) {
                final pOff = pointsOffset + (i * 16);
                if (pOff + 16 > bytes.length) break;
                final x = data.getFloat64(pOff, Endian.little);
                final y = data.getFloat64(pOff + 8, Endian.little);
                coords.add(LatLng(y, x));
              }
              // Remove closing vertex for polygons
              if (geoType == GeometryType.polygon && coords.length > 1 &&
                  coords.first.latitude == coords.last.latitude &&
                  coords.first.longitude == coords.last.longitude) {
                coords.removeLast();
              }
              break;
          }

          if (coords.isNotEmpty) {
            final attrs = (dbfRecords != null && recordIndex < dbfRecords.length)
                ? dbfRecords[recordIndex]
                : <String, dynamic>{};

            final feature = FeatureModel(
              layerId: layer.id,
              coordinates: coords,
              attributes: attrs,
            );
            await _featureRepo.insert(feature);
            importedCount++;
            if (importedCount % 50 == 0) {
              onProgress?.call(importedCount, totalEstimate, 'Đã nhập $importedCount');
            }
          }

          offset += contentLength;
          recordIndex++;
        } catch (e) {
          debugPrint('ImportService: SHP record $recordIndex parse error: $e');
          break;
        }
      }

      debugPrint('ImportService: Imported $importedCount features from SHP');
      return ImportResult(
        success: true,
        projectId: projectId,
        layerId: layer.id,
        featureCount: importedCount,
        layerCount: 1,
      );
    } catch (e) {
      debugPrint('ImportService: importSHP failed - $e');
      return ImportResult(success: false, errorMessage: 'Lỗi nhập SHP: $e');
    }
  }

  /// Read DBF (dBASE) file records
  Future<List<Map<String, dynamic>>> _readDbfRecords(File dbfFile) async {
    final bytes = await dbfFile.readAsBytes();
    final data = ByteData.sublistView(bytes);
    final records = <Map<String, dynamic>>[];

    try {
      final numRecords = data.getInt32(4, Endian.little);
      final headerSize = data.getInt16(8, Endian.little);
      final recordSize = data.getInt16(10, Endian.little);

      // Parse field descriptors
      final fields = <_DbfField>[];
      int fieldOffset = 32;
      while (fieldOffset < headerSize - 1 && bytes[fieldOffset] != 0x0D) {
        final nameBytes = bytes.sublist(fieldOffset, fieldOffset + 11);
        final name = String.fromCharCodes(nameBytes).replaceAll('\x00', '').trim();
        final type = String.fromCharCode(bytes[fieldOffset + 11]);
        final length = bytes[fieldOffset + 16];
        fields.add(_DbfField(name: name, type: type, length: length));
        fieldOffset += 32;
      }

      // Parse records
      int recordOffset = headerSize;
      for (int i = 0; i < numRecords && recordOffset < bytes.length; i++) {
        if (bytes[recordOffset] == 0x2A) {
          // Deleted record
          recordOffset += recordSize;
          continue;
        }
        recordOffset++; // Skip deletion flag

        final record = <String, dynamic>{};
        for (final field in fields) {
          if (recordOffset + field.length > bytes.length) break;
          final rawValue = String.fromCharCodes(
              bytes.sublist(recordOffset, recordOffset + field.length)).trim();
          // Try to parse numeric fields
          if (field.type == 'N' || field.type == 'F') {
            record[field.name] = num.tryParse(rawValue) ?? rawValue;
          } else {
            record[field.name] = rawValue;
          }
          recordOffset += field.length;
        }
        records.add(record);
      }
    } catch (e) {
      debugPrint('ImportService: DBF parse error: $e');
    }

    return records;
  }

  // ===========================================================================
  // MBTiles Import (offline basemap)
  // ===========================================================================

  /// Import MBTiles file as offline basemap tile cache
  Future<ImportResult> importMBTiles(String filePath, String projectId) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return const ImportResult(success: false, errorMessage: 'File không tồn tại');
      }

      // Copy to app's tiles directory
      final appDir = await getApplicationDocumentsDirectory();
      final tilesDir = Directory('${appDir.path}/LVTField/tiles');
      if (!await tilesDir.exists()) {
        await tilesDir.create(recursive: true);
      }

      final basename = filePath.split(RegExp(r'[/\\]')).last;
      final destPath = '${tilesDir.path}/$basename';
      await file.copy(destPath);

      debugPrint('ImportService: MBTiles copied to $destPath');
      return ImportResult(
        success: true,
        projectId: projectId,
        featureCount: 0,
        layerCount: 0,
      );
    } catch (e) {
      debugPrint('ImportService: importMBTiles failed - $e');
      return ImportResult(success: false, errorMessage: 'Lỗi nhập MBTiles: $e');
    }
  }

  // ===========================================================================
  // Import GeoPackage (.gpkg) — SQLite-based OGC standard
  // ===========================================================================

  /// Import a GeoPackage file (.gpkg) into an existing project
  /// GPKG is a SQLite database with geometry stored as GeoPackage Binary (GPB)
  Future<ImportResult> importGpkg(String filePath, String projectId, {ImportProgressCallback? onProgress}) async {
    try {
      debugPrint('ImportService: Starting GPKG import: $filePath');
      final project = await _projectRepo.getById(projectId);
      if (project == null) {
        return const ImportResult(success: false, errorMessage: 'Không tìm thấy dự án');
      }

      final file = File(filePath);
      if (!await file.exists()) {
        return const ImportResult(success: false, errorMessage: 'File không tồn tại');
      }

      // Copy GPKG to app directory to safely open with sqflite
      final appDir = await getApplicationDocumentsDirectory();
      final gpkgDir = Directory('${appDir.path}/gpkg_import');
      if (!await gpkgDir.exists()) await gpkgDir.create(recursive: true);
      final destFile = File('${gpkgDir.path}/import_${DateTime.now().millisecondsSinceEpoch}.gpkg');
      await file.copy(destFile.path);
      debugPrint('ImportService: GPKG copied to ${destFile.path}');

      // Open as SQLite database
      final db = await openDatabase(destFile.path, readOnly: true);

      int totalFeatures = 0;
      int totalLayers = 0;

      try {
        // Read gpkg_contents to find feature tables
        final contents = await db.rawQuery(
          "SELECT table_name, data_type, identifier, description, srs_id "
          "FROM gpkg_contents WHERE data_type = 'features'"
        );
        debugPrint('ImportService: Found ${contents.length} feature tables');

        if (contents.isEmpty) {
          await db.close();
          await destFile.delete();
          return const ImportResult(
            success: false,
            errorMessage: 'File GPKG không chứa bảng feature nào',
          );
        }

        // Try to detect projection parameters from SRS
        double? centralMeridian;
        double scaleFactor = 0.9999;     // VN-2000 default
        double falseEasting = 500000.0;  // VN-2000 default
        bool isProjected = false;
        bool isVn2000 = false;           // Need datum shift correction
        try {
          final srsId = contents.first['srs_id'];
          debugPrint('ImportService: GPKG SRS ID = $srsId');

          if (srsId != null && srsId != 4326 && srsId != 0 && srsId != -1) {
            // Step 1: Try to detect from EPSG code
            final epsgInfo = CrsService.detectProjectionFromSrsId(srsId is int ? srsId : int.tryParse(srsId.toString()) ?? 0);
            if (epsgInfo['type'] == 'utm' || epsgInfo['type'] == 'vn2000_utm') {
              centralMeridian = epsgInfo['centralMeridian'];
              scaleFactor = epsgInfo['scaleFactor'] ?? 0.9996;
              falseEasting = epsgInfo['falseEasting'] ?? 500000.0;
              isProjected = true;
              if (epsgInfo['type'] == 'vn2000_utm') isVn2000 = true;
              debugPrint('ImportService: Detected from EPSG: CM=$centralMeridian, k0=$scaleFactor, vn2000=$isVn2000');
            }

            // Step 2: Try to parse WKT definition
            if (centralMeridian == null) {
              final srsDef = await db.rawQuery(
                "SELECT definition FROM gpkg_spatial_ref_sys WHERE srs_id = ?",
                [srsId],
              );
              if (srsDef.isNotEmpty) {
                final def = srsDef.first['definition'] as String? ?? '';
                final defPreview = def.length > 300 ? def.substring(0, 300) : def;
                debugPrint('ImportService: SRS WKT: $defPreview');

                // Check if projected
                if (CrsService.isProjectedCrs(def)) {
                  isProjected = true;

                  // Extract parameters using robust WKT parser
                  centralMeridian = CrsService.extractCentralMeridian(def);
                  final sf = CrsService.extractScaleFactor(def);
                  final fe = CrsService.extractFalseEasting(def);

                  if (sf != null) scaleFactor = sf;
                  if (fe != null) falseEasting = fe;

                  // Detect VN-2000 datum from WKT
                  final upperDef = def.toUpperCase();
                  if (upperDef.contains('VN-2000') || upperDef.contains('VN_2000') || upperDef.contains('VIETNAM_2000') || upperDef.contains('VIETNAM 2000')) {
                    isVn2000 = true;
                  }

                  debugPrint('ImportService: WKT params: CM=$centralMeridian, k0=$scaleFactor, FE=$falseEasting, vn2000=$isVn2000');
                } else {
                  debugPrint('ImportService: SRS is geographic (not projected)');
                }
              }
            }
          }
        } catch (e) {
          debugPrint('ImportService: Could not read SRS: $e');
        }

        // Read geometry columns info
        final geomCols = await db.rawQuery(
          "SELECT table_name, column_name, geometry_type_name "
          "FROM gpkg_geometry_columns"
        );
        final geomColMap = <String, Map<String, String>>{};
        for (final row in geomCols) {
          geomColMap[row['table_name'] as String] = {
            'column': row['column_name'] as String,
            'type': row['geometry_type_name'] as String,
          };
        }

        // Process each feature table
        for (final content in contents) {
          final tableName = content['table_name'] as String;
          final tableDesc = content['identifier'] as String? ?? tableName;
          final geomInfo = geomColMap[tableName];
          final geomColumn = geomInfo?['column'] ?? 'geom';
          final geomTypeName = geomInfo?['type'] ?? 'GEOMETRY';
          debugPrint('ImportService: Processing table "$tableName" geomCol=$geomColumn type=$geomTypeName');

          // Detect geometry type
          final geometryType = _gpkgGeometryType(geomTypeName);

          // Create layer
          final layer = LayerModel(
            projectId: projectId,
            name: tableDesc,
            geometryType: geometryType,
          );
          await _layerRepo.insert(layer);
          totalLayers++;

          // Auto-generate form fields from GPKG column schema
          await _autoGenerateFormFields(db, tableName, geomColumn, layer.id);

          // Read features from table (limit to 5000 for safety)
          final rows = await db.rawQuery("SELECT * FROM [$tableName] LIMIT 5000");
          final totalRows = rows.length;
          debugPrint('ImportService: GPKG table $tableName has $totalRows rows');
          onProgress?.call(0, totalRows, 'Đang nhập $totalRows đối tượng...');

          // Get non-geometry column names for attributes
          List<String>? attrColumns;
          int skipped = 0;

          for (final row in rows) {
            try {
              // Extract geometry from GPB (GeoPackage Binary)
              final geomData = row[geomColumn];
              if (geomData == null) { skipped++; continue; }

              List<LatLng>? coords;
              if (geomData is Uint8List) {
                coords = _parseGpkgGeometry(geomData, centralMeridian, scaleFactor, falseEasting, isVn2000);
              }
              if (coords == null || coords.isEmpty) { skipped++; continue; }

              // Extract attribute columns (skip geometry and internal columns)
              attrColumns ??= row.keys
                  .where((k) => k != geomColumn && k != 'fid' && k != 'id')
                  .toList();

              final attributes = <String, dynamic>{};
              for (final col in attrColumns) {
                final val = row[col];
                if (val != null && val.toString().isNotEmpty) {
                  attributes[col] = val;
                }
              }

              final feature = FeatureModel(
                layerId: layer.id,
                coordinates: coords,
                attributes: attributes,
              );
              await _featureRepo.insert(feature);
              totalFeatures++;
              if (totalFeatures % 20 == 0 || totalFeatures == totalRows) {
                onProgress?.call(totalFeatures, totalRows, 'Đã nhập $totalFeatures/$totalRows');
              }
            } catch (e) {
              skipped++;
              debugPrint('ImportService: Skip GPKG row: $e');
            }
          }
          debugPrint('ImportService: Table $tableName done: $totalFeatures imported, $skipped skipped');
        }
      } finally {
        await db.close();
        // Clean up temp file
        try { await destFile.delete(); } catch (_) {}
      }

      debugPrint('ImportService: GPKG import complete: $totalFeatures features, $totalLayers layers');
      return ImportResult(
        success: true,
        projectId: projectId,
        featureCount: totalFeatures,
        layerCount: totalLayers,
      );
    } catch (e, st) {
      debugPrint('ImportService: importGpkg failed - $e');
      debugPrint('ImportService: stack: $st');
      return ImportResult(success: false, errorMessage: 'Lỗi nhập GeoPackage: $e');
    }
  }

  /// Auto-generate form field definitions from GPKG column schema.
  /// Maps SQLite types to FormFieldType and detects dropdowns for low-cardinality fields.
  Future<void> _autoGenerateFormFields(
    Database db,
    String tableName,
    String geomColumn,
    String layerId,
  ) async {
    try {
      final appDb = await AppDatabase.database;
      final columns = await db.rawQuery("PRAGMA table_info([$tableName])");
      debugPrint('ImportService: GPKG schema for $tableName: ${columns.length} columns');

      // Skip internal columns
      const skipCols = {'fid', 'id', 'ogc_fid', 'rowid'};
      int order = 0;

      for (final col in columns) {
        final colName = col['name'] as String;
        final colType = (col['type'] as String? ?? 'TEXT').toUpperCase();
        final notNull = (col['notnull'] as int?) == 1;

        // Skip geometry and internal columns
        if (colName == geomColumn || skipCols.contains(colName.toLowerCase())) {
          continue;
        }

        // Map SQLite column type → FormFieldType
        FormFieldType fieldType;
        if (colType.contains('INT') || colType.contains('BOOL')) {
          fieldType = FormFieldType.number;
        } else if (colType.contains('REAL') || colType.contains('FLOAT') ||
                   colType.contains('DOUBLE') || colType.contains('NUMERIC')) {
          fieldType = FormFieldType.number;
        } else if (colType.contains('DATE') && colType.contains('TIME')) {
          fieldType = FormFieldType.date;
        } else if (colType.contains('DATE')) {
          fieldType = FormFieldType.date;
        } else {
          fieldType = FormFieldType.text;
        }

        // Detect potential dropdown: check distinct value count
        List<Map<String, String>>? options;
        if (fieldType == FormFieldType.text) {
          try {
            final distinctVals = await db.rawQuery(
              "SELECT DISTINCT [$colName] FROM [$tableName] "
              "WHERE [$colName] IS NOT NULL AND [$colName] != '' "
              "ORDER BY [$colName] LIMIT 30"
            );
            if (distinctVals.isNotEmpty && distinctVals.length <= 20) {
              // Low cardinality → make it a dropdown
              fieldType = FormFieldType.dropdown;
              options = distinctVals.map((r) {
                final val = r[colName]?.toString() ?? '';
                return {'value': val, 'label': val};
              }).toList();
              debugPrint('ImportService: Column "$colName" → dropdown (${options.length} options)');
            }
          } catch (_) {}
        }

        final formField = FormFieldModel(
          layerId: layerId,
          fieldName: colName,
          label: colName, // Use column name as label
          fieldType: fieldType,
          options: options,
          isRequired: notNull,
          sortOrder: order++,
        );

        await appDb.insert('form_fields', formField.toMap());
        debugPrint('ImportService: FormField "$colName" → ${fieldType.name}');
      }

      debugPrint('ImportService: Created $order form fields for layer $layerId');
    } catch (e) {
      debugPrint('ImportService: Auto-generate form fields failed: $e');
    }
  }

  /// Map GPKG geometry type name to our GeometryType
  GeometryType _gpkgGeometryType(String typeName) {
    final upper = typeName.toUpperCase();
    if (upper.contains('POINT')) return GeometryType.point;
    if (upper.contains('LINE')) return GeometryType.line;
    if (upper.contains('POLYGON')) return GeometryType.polygon;
    return GeometryType.point; // fallback
  }

  /// Parse GeoPackage Binary (GPB) geometry format
  /// GPB header: "GP" (2 bytes) + version (1) + flags (1) + srs_id (4) + [envelope] + WKB
  List<LatLng>? _parseGpkgGeometry(Uint8List data, [double? centralMeridian, double scaleFactor = 0.9999, double falseEasting = 500000.0, bool isVn2000 = false]) {
    if (data.length < 8) return null;

    // Check "GP" magic number
    if (data[0] != 0x47 || data[1] != 0x50) {
      // Not GPB, try as raw WKB
      return _parseWkbGeometry(data, 0, centralMeridian, scaleFactor, falseEasting, isVn2000);
    }

    final flags = data[3];
    final envelopeType = (flags >> 1) & 0x07;
    final byteOrder = flags & 0x01; // 0=big-endian, 1=little-endian

    // Calculate envelope size
    int envelopeSize;
    switch (envelopeType) {
      case 0: envelopeSize = 0; break;
      case 1: envelopeSize = 32; break; // minx,maxx,miny,maxy
      case 2: envelopeSize = 48; break; // + minz,maxz
      case 3: envelopeSize = 48; break; // + minm,maxm
      case 4: envelopeSize = 64; break; // + minz,maxz,minm,maxm
      default: envelopeSize = 0;
    }

    // WKB starts after header (8 bytes) + envelope
    final wkbOffset = 8 + envelopeSize;
    if (wkbOffset >= data.length) return null;

    return _parseWkbGeometry(data, wkbOffset, centralMeridian, scaleFactor, falseEasting, isVn2000);
  }

  /// Parse WKB (Well-Known Binary) geometry
  List<LatLng>? _parseWkbGeometry(Uint8List data, int offset, [double? centralMeridian, double scaleFactor = 0.9999, double falseEasting = 500000.0, bool isVn2000 = false]) {
    if (offset + 5 > data.length) return null;

    final byteOrder = data[offset]; // 0=big-endian, 1=little-endian
    final isLE = byteOrder == 1;

    // Read geometry type (4 bytes)
    final wkbType = _readUint32(data, offset + 1, isLE);
    // Strip Z/M flags for type detection
    final baseType = wkbType & 0xFF;
    // Detect coordinate dimensions from WKB type
    // Type 1000+ = Z, 2000+ = M, 3000+ = ZM
    final hasZ = (wkbType >= 1000 && wkbType < 2000) || wkbType >= 3000 || (wkbType & 0x80000000 != 0);
    final hasM = (wkbType >= 2000 && wkbType < 3000) || wkbType >= 3000;
    int coordStride = 16; // 2 doubles (x, y)
    if (hasZ && hasM) {
      coordStride = 32; // 4 doubles
    } else if (hasZ || hasM) {
      coordStride = 24; // 3 doubles
    }

    offset += 5; // past byte-order + type

    switch (baseType) {
      case 1: // Point
        return _parseWkbPoint(data, offset, isLE, centralMeridian, scaleFactor, falseEasting, isVn2000);
      case 2: // LineString
        return _parseWkbLineString(data, offset, isLE, coordStride, centralMeridian, scaleFactor, falseEasting, isVn2000);
      case 3: // Polygon
        return _parseWkbPolygon(data, offset, isLE, coordStride, centralMeridian, scaleFactor, falseEasting, isVn2000);
      case 4: // MultiPoint
        return _parseWkbMultiPoint(data, offset, isLE, centralMeridian, scaleFactor, falseEasting, isVn2000);
      case 5: // MultiLineString
        return _parseWkbMultiLineString(data, offset, isLE, centralMeridian, scaleFactor, falseEasting, isVn2000);
      case 6: // MultiPolygon
        return _parseWkbMultiPolygonFlat(data, offset, isLE, coordStride, centralMeridian, scaleFactor, falseEasting, isVn2000);
      default:
        debugPrint('ImportService: Unknown WKB type: $wkbType (base=$baseType)');
        return null;
    }
  }

  List<LatLng>? _parseWkbPoint(Uint8List data, int offset, bool isLE, [double? centralMeridian, double scaleFactor = 0.9999, double falseEasting = 500000.0, bool isVn2000 = false]) {
    if (offset + 16 > data.length) return null;
    final x = _readFloat64(data, offset, isLE);
    final y = _readFloat64(data, offset + 8, isLE);
    // Check if geographic or projected
    if (x >= -180 && x <= 180 && y >= -90 && y <= 90) {
      return [LatLng(y, x)];
    }
    // Projected → convert to WGS84
    final cm = centralMeridian ?? _guessCentralMeridian(x);
    final result = CrsService.tmToWgs84(x, y, cm, k0: scaleFactor, falseEasting: falseEasting, isVn2000: isVn2000);
    if (result != null) {
      return [LatLng(result[0], result[1])];
    }
    return null;
  }

  List<LatLng>? _parseWkbLineString(Uint8List data, int offset, bool isLE, [int stride = 16, double? centralMeridian, double scaleFactor = 0.9999, double falseEasting = 500000.0, bool isVn2000 = false]) {
    if (offset + 4 > data.length) return null;
    final numPoints = _readUint32(data, offset, isLE);
    offset += 4;
    return _readCoordSequence(data, offset, numPoints, isLE, stride, centralMeridian, scaleFactor, falseEasting, isVn2000);
  }

  List<LatLng>? _parseWkbPolygon(Uint8List data, int offset, bool isLE, [int stride = 16, double? centralMeridian, double scaleFactor = 0.9999, double falseEasting = 500000.0, bool isVn2000 = false]) {
    if (offset + 4 > data.length) return null;
    final numRings = _readUint32(data, offset, isLE);
    offset += 4;
    if (numRings == 0) return null;
    // Read only the outer ring (skip inner rings properly)
    final numPoints = _readUint32(data, offset, isLE);
    offset += 4;
    return _readCoordSequence(data, offset, numPoints, isLE, stride, centralMeridian, scaleFactor, falseEasting, isVn2000);
  }

  /// Calculate byte size of a single Polygon WKB body (for skipping in MultiPolygon)
  int _wkbPolygonByteSize(Uint8List data, int offset, bool isLE, int stride) {
    if (offset + 4 > data.length) return 0;
    final numRings = _readUint32(data, offset, isLE);
    int size = 4; // numRings uint32
    int curOffset = offset + 4;
    for (int r = 0; r < numRings; r++) {
      if (curOffset + 4 > data.length) break;
      final numPts = _readUint32(data, curOffset, isLE);
      curOffset += 4;
      curOffset += numPts * stride;
      size += 4 + numPts * stride;
    }
    return size;
  }

  List<LatLng>? _parseWkbMultiPoint(Uint8List data, int offset, bool isLE, [double? centralMeridian, double scaleFactor = 0.9999, double falseEasting = 500000.0, bool isVn2000 = false]) {
    if (offset + 4 > data.length) return null;
    final numGeoms = _readUint32(data, offset, isLE);
    offset += 4;
    final result = <LatLng>[];
    for (int i = 0; i < numGeoms; i++) {
      if (offset + 5 > data.length) break;
      offset += 5; // skip byte-order + type for each sub-geometry
      final pt = _parseWkbPoint(data, offset, isLE, centralMeridian, scaleFactor, falseEasting, isVn2000);
      if (pt != null) result.addAll(pt);
      offset += 16;
    }
    return result.isEmpty ? null : result;
  }

  List<LatLng>? _parseWkbMultiLineString(Uint8List data, int offset, bool isLE, [double? centralMeridian, double scaleFactor = 0.9999, double falseEasting = 500000.0, bool isVn2000 = false]) {
    if (offset + 4 > data.length) return null;
    final numGeoms = _readUint32(data, offset, isLE);
    offset += 4;
    // Return first linestring only
    if (numGeoms > 0 && offset + 5 < data.length) {
      offset += 5; // skip byte-order + type
      return _parseWkbLineString(data, offset, isLE, 16, centralMeridian, scaleFactor, falseEasting, isVn2000);
    }
    return null;
  }

  /// Parse MultiPolygon — return only first polygon part (avoid connecting lines)
  List<LatLng>? _parseWkbMultiPolygonFlat(Uint8List data, int offset, bool isLE, [int stride = 16, double? centralMeridian, double scaleFactor = 0.9999, double falseEasting = 500000.0, bool isVn2000 = false]) {
    if (offset + 4 > data.length) return null;
    final numGeoms = _readUint32(data, offset, isLE);
    offset += 4;
    if (numGeoms > 0 && offset + 5 < data.length) {
      // Each sub-polygon has its own WKB header → detect stride from sub type
      final subIsLE = data[offset] == 1;
      final subType = _readUint32(data, offset + 1, subIsLE);
      final subStride = _detectStride(subType);
      offset += 5; // skip byte-order + type
      return _parseWkbPolygon(data, offset, subIsLE, subStride, centralMeridian, scaleFactor, falseEasting, isVn2000);
    }
    return null;
  }

  /// Parse MultiPolygon into separate coordinate lists
  List<List<LatLng>>? _parseWkbMultiPolygonParts(Uint8List data, int offset, bool isLE, int stride, [double? centralMeridian, double scaleFactor = 0.9999, double falseEasting = 500000.0, bool isVn2000 = false]) {
    if (offset + 4 > data.length) return null;
    final numGeoms = _readUint32(data, offset, isLE);
    offset += 4;
    final parts = <List<LatLng>>[];
    for (int i = 0; i < numGeoms; i++) {
      if (offset + 5 > data.length) break;
      final subIsLE = data[offset] == 1;
      final subType = _readUint32(data, offset + 1, subIsLE);
      final subStride = _detectStride(subType);
      offset += 5;
      final coords = _parseWkbPolygon(data, offset, subIsLE, subStride, centralMeridian, scaleFactor, falseEasting, isVn2000);
      if (coords != null && coords.isNotEmpty) {
        parts.add(coords);
      }
      final polySize = _wkbPolygonByteSize(data, offset, subIsLE, subStride);
      offset += polySize;
    }
    return parts.isEmpty ? null : parts;
  }

  /// Detect coordinate stride from WKB geometry type
  int _detectStride(int wkbType) {
    final hasZ = (wkbType >= 1000 && wkbType < 2000) || wkbType >= 3000 || (wkbType & 0x80000000 != 0);
    final hasM = (wkbType >= 2000 && wkbType < 3000) || wkbType >= 3000;
    if (hasZ && hasM) return 32;
    if (hasZ || hasM) return 24;
    return 16;
  }

  List<LatLng>? _readCoordSequence(Uint8List data, int offset, int numPoints, bool isLE, [int stride = 16, double? centralMeridian, double scaleFactor = 0.9999, double falseEasting = 500000.0, bool isVn2000 = false]) {
    // Auto-detect stride if data seems too short for assumed stride
    if (numPoints > 0 && offset + numPoints * stride > data.length) {
      // Try smaller stride
      if (offset + numPoints * 16 <= data.length) {
        stride = 16;
      } else {
        debugPrint('ImportService: coord data too short for $numPoints points (stride=$stride)');
        return null;
      }
    }
    final coords = <LatLng>[];
    for (int i = 0; i < numPoints; i++) {
      if (offset + 16 > data.length) break;
      final x = _readFloat64(data, offset, isLE);
      final y = _readFloat64(data, offset + 8, isLE);
      // Check if coordinates are geographic (degrees)
      if (x >= -180 && x <= 180 && y >= -90 && y <= 90) {
        coords.add(LatLng(y, x));
      } else {
        // Projected coordinates (meters) → convert to WGS84 using CrsService
        final cm = centralMeridian ?? _guessCentralMeridian(x);
        final result = CrsService.tmToWgs84(x, y, cm,
          k0: scaleFactor,
          falseEasting: falseEasting,
          isVn2000: isVn2000,
        );
        if (result != null) {
          coords.add(LatLng(result[0], result[1]));
        }
      }
      offset += stride; // skip Z/M values
    }
    return coords.isEmpty ? null : coords;
  }

  /// Guess central meridian for VN-2000 from easting value
  double _guessCentralMeridian(double easting) {
    // Default: 105.75 for central Vietnam
    return 105.75;
  }

  int _readUint32(Uint8List data, int offset, bool isLE) {
    final bd = ByteData.sublistView(data, offset, offset + 4);
    return bd.getUint32(0, isLE ? Endian.little : Endian.big);
  }

  double _readFloat64(Uint8List data, int offset, bool isLE) {
    final bd = ByteData.sublistView(data, offset, offset + 8);
    return bd.getFloat64(0, isLE ? Endian.little : Endian.big);
  }

  // ===========================================================================
  // Auto-detect and import any supported file
  // ===========================================================================

  /// Auto-detect file format and import accordingly
  Future<ImportResult> importFile(String filePath, String projectId, {ImportProgressCallback? onProgress}) async {
    final ext = filePath.toLowerCase();
    if (ext.endsWith('.geojson') || ext.endsWith('.json')) {
      return importGeoJson(filePath, projectId);
    } else if (ext.endsWith('.kml')) {
      return importKML(filePath, projectId, onProgress: onProgress);
    } else if (ext.endsWith('.kmz')) {
      return importKMZ(filePath, projectId, onProgress: onProgress);
    } else if (ext.endsWith('.shp')) {
      return importSHP(filePath, projectId, onProgress: onProgress);
    } else if (ext.endsWith('.gpkg')) {
      return importGpkg(filePath, projectId, onProgress: onProgress);
    } else if (ext.endsWith('.mbtiles')) {
      return importMBTiles(filePath, projectId);
    } else if (ext.endsWith('.lvtfield')) {
      return importLvtFieldPackage(filePath);
    }
    return const ImportResult(
      success: false,
      errorMessage: 'Định dạng file không được hỗ trợ',
    );
  }

  /// Auto-detect geometry type from GeoJSON features
  GeometryType? _detectGeometryType(List<dynamic> features) {
    for (final feature in features) {
      final featureMap = feature as Map<String, dynamic>;
      final geometry = featureMap['geometry'] as Map<String, dynamic>?;
      if (geometry == null) continue;

      final type = geometry['type'] as String?;
      switch (type) {
        case 'Point':
        case 'MultiPoint':
          return GeometryType.point;
        case 'LineString':
        case 'MultiLineString':
          return GeometryType.line;
        case 'Polygon':
        case 'MultiPolygon':
          return GeometryType.polygon;
      }
    }
    return null;
  }

  /// Parse a single GeoJSON Feature into a FeatureModel
  FeatureModel? _parseGeoJsonFeature(
    Map<String, dynamic> geoFeature,
    String layerId,
  ) {
    try {
      final geometry = geoFeature['geometry'] as Map<String, dynamic>?;
      if (geometry == null) return null;

      final coordinates = _parseCoordinates(geometry);
      if (coordinates.isEmpty) return null;

      // Extract properties (attributes)
      final properties = geoFeature['properties'] as Map<String, dynamic>? ?? {};

      // Separate system properties from user attributes
      final collectedAt = properties['collected_at'] != null
          ? DateTime.tryParse(properties['collected_at'] as String)
          : null;
      final collectedBy = properties['collected_by'] as String?;
      final gpsAccuracy = (properties['gps_accuracy'] as num?)?.toDouble();

      // User attributes = everything except system fields
      final userAttributes = Map<String, dynamic>.from(properties)
        ..remove('id')
        ..remove('collected_at')
        ..remove('collected_by')
        ..remove('gps_accuracy');

      return FeatureModel(
        layerId: layerId,
        coordinates: coordinates,
        attributes: userAttributes,
        collectedAt: collectedAt,
        collectedBy: collectedBy,
        gpsAccuracy: gpsAccuracy,
      );
    } catch (e) {
      debugPrint('ImportService: Failed to parse feature - $e');
      return null;
    }
  }

  /// Parse GeoJSON geometry coordinates into LatLng list
  List<LatLng> _parseCoordinates(Map<String, dynamic> geometry) {
    final type = geometry['type'] as String;
    final coords = geometry['coordinates'];

    switch (type) {
      case 'Point':
        final pair = coords as List<dynamic>;
        return [
          LatLng(
            (pair[1] as num).toDouble(),
            (pair[0] as num).toDouble(),
          ),
        ];

      case 'MultiPoint':
        final points = coords as List<dynamic>;
        return points.map((p) {
          final pair = p as List<dynamic>;
          return LatLng(
            (pair[1] as num).toDouble(),
            (pair[0] as num).toDouble(),
          );
        }).toList();

      case 'LineString':
        final line = coords as List<dynamic>;
        return line.map((p) {
          final pair = p as List<dynamic>;
          return LatLng(
            (pair[1] as num).toDouble(),
            (pair[0] as num).toDouble(),
          );
        }).toList();

      case 'MultiLineString':
        // Take the first line
        final lines = coords as List<dynamic>;
        if (lines.isEmpty) return [];
        final firstLine = lines.first as List<dynamic>;
        return firstLine.map((p) {
          final pair = p as List<dynamic>;
          return LatLng(
            (pair[1] as num).toDouble(),
            (pair[0] as num).toDouble(),
          );
        }).toList();

      case 'Polygon':
        // Take the outer ring (first ring), skip closing vertex
        final rings = coords as List<dynamic>;
        if (rings.isEmpty) return [];
        final outerRing = rings.first as List<dynamic>;
        final ringCoords = outerRing.map((p) {
          final pair = p as List<dynamic>;
          return LatLng(
            (pair[1] as num).toDouble(),
            (pair[0] as num).toDouble(),
          );
        }).toList();
        // Remove the closing vertex if it duplicates the first
        if (ringCoords.length > 1 &&
            ringCoords.first.latitude == ringCoords.last.latitude &&
            ringCoords.first.longitude == ringCoords.last.longitude) {
          ringCoords.removeLast();
        }
        return ringCoords;

      case 'MultiPolygon':
        // Take the outer ring of the first polygon
        final polygons = coords as List<dynamic>;
        if (polygons.isEmpty) return [];
        final firstPolygon = polygons.first as List<dynamic>;
        if (firstPolygon.isEmpty) return [];
        final outerRing = firstPolygon.first as List<dynamic>;
        final polyCoords = outerRing.map((p) {
          final pair = p as List<dynamic>;
          return LatLng(
            (pair[1] as num).toDouble(),
            (pair[0] as num).toDouble(),
          );
        }).toList();
        if (polyCoords.length > 1 &&
            polyCoords.first.latitude == polyCoords.last.latitude &&
            polyCoords.first.longitude == polyCoords.last.longitude) {
          polyCoords.removeLast();
        }
        return polyCoords;

      default:
        return [];
    }
  }

  /// Extract a layer name from a file path
  String _extractLayerName(String filePath) {
    final basename = filePath.split(RegExp(r'[/\\]')).last;
    return basename.replaceAll('.geojson', '').replaceAll('.json', '');
  }

  /// Extract a layer name from an archive entry name
  String _extractLayerNameFromArchive(String archiveName) {
    final parts = archiveName.split('/');
    final filename = parts.last;
    return filename.replaceAll('.geojson', '');
  }

  /// Import form field definitions from forms.json in the archive
  Future<void> _importFormFields(
    ArchiveFile formsFile,
    Map<String, String> layerIdMap,
  ) async {
    try {
      final formsJson = jsonDecode(
        utf8.decode(formsFile.content as List<int>),
      ) as List<dynamic>;

      final db = await AppDatabase.database;
      const uuid = Uuid();

      for (final formDef in formsJson) {
        final formMap = formDef as Map<String, dynamic>;
        final oldLayerId = formMap['layer_id'] as String?;
        if (oldLayerId == null) continue;

        // Map to new layer ID
        final newLayerId = layerIdMap[oldLayerId];
        if (newLayerId == null) continue;

        final fields = formMap['fields'] as List<dynamic>? ?? [];
        for (final field in fields) {
          final fieldMap = Map<String, dynamic>.from(field as Map);
          // Assign new IDs and update layer reference
          fieldMap['id'] = uuid.v4();
          fieldMap['layer_id'] = newLayerId;
          await db.insert('form_fields', fieldMap);
        }
      }
    } catch (e) {
      debugPrint('ImportService: Failed to import form fields - $e');
    }
  }

  /// Import media files from the archive to the app's storage
  Future<void> _importMediaFiles(Archive archive, String projectId) async {
    try {
      for (final archiveFile in archive) {
        if (archiveFile.name.startsWith('media/') && archiveFile.size > 0) {
          // Media files are stored but not linked to features here
          // since feature IDs are regenerated on import.
          // Future: implement media re-linking using original feature IDs.
          debugPrint('ImportService: Media file found: ${archiveFile.name} '
              '(media re-linking not yet implemented)');
        }
      }
    } catch (e) {
      debugPrint('ImportService: Failed to import media files - $e');
    }
  }
}

/// Helper class for DBF field descriptors
class _DbfField {
  final String name;
  final String type;
  final int length;

  const _DbfField({required this.name, required this.type, required this.length});
}
