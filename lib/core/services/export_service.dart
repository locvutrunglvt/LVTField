// Export service for LVTField project data
// Supports GeoJSON and .lvtfield package formats
// Author: Lộc Vũ Trung

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';
import 'package:xml/xml.dart' as xml;
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../../data/database/app_database.dart';
import '../../data/models/layer_model.dart';
import '../../data/models/feature_model.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/layer_repository.dart';
import '../../data/repositories/feature_repository.dart';
import 'geojson_service.dart';

/// Result of an export operation
class ExportResult {
  final bool success;
  final String? filePath;
  final String? errorMessage;
  final int featureCount;

  const ExportResult({
    required this.success,
    this.filePath,
    this.errorMessage,
    this.featureCount = 0,
  });
}

/// Service for exporting project data in various formats
///
/// All exported filenames follow the pattern:
/// `{projectName}_{username}_{YYYYMMDD_HHmmss}.{ext}`
/// to prevent filename conflicts between different users.
class ExportService {
  final ProjectRepository _projectRepo = ProjectRepository();
  final LayerRepository _layerRepo = LayerRepository();
  final FeatureRepository _featureRepo = FeatureRepository();

  /// Get the export directory, creating it if needed
  Future<Directory> _getExportDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final exportDir = Directory(p.join(appDir.path, 'LVTField', 'exports'));
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    return exportDir;
  }

  /// Generate a safe filename with project name, username, and timestamp
  ///
  /// Format: `{projectName}_{username}_{YYYYMMDD_HHmmss}.{ext}`
  String _generateFilename({
    required String projectName,
    required String username,
    required String extension,
  }) {
    final safeName = projectName.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final safeUser = username.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return '${safeName}_${safeUser}_$timestamp.$extension';
  }

  /// Export a single layer as GeoJSON file
  ///
  /// Returns [ExportResult] with the path to the exported file.
  /// The filename includes the username and timestamp.
  Future<ExportResult> exportGeoJson({
    required String projectId,
    required String layerId,
    required String username,
  }) async {
    try {
      // Fetch project, layer, and features
      final project = await _projectRepo.getById(projectId);
      if (project == null) {
        return const ExportResult(
          success: false,
          errorMessage: 'Không tìm thấy dự án',
        );
      }

      final layer = await _layerRepo.getById(layerId);
      if (layer == null) {
        return const ExportResult(
          success: false,
          errorMessage: 'Không tìm thấy lớp dữ liệu',
        );
      }

      final features = await _featureRepo.getByLayer(layerId);

      // Build GeoJSON using existing service
      final exportDir = await _getExportDir();
      final filename = _generateFilename(
        projectName: '${project.name}_${layer.name}',
        username: username,
        extension: 'geojson',
      );
      final outputPath = p.join(exportDir.path, filename);

      // Use GeoJsonService to export
      final result = await GeoJsonService.exportLayer(
        layer: layer,
        features: features,
        outputPath: outputPath,
      );

      if (result != null) {
        debugPrint('ExportService: Exported ${features.length} features to $result');
        return ExportResult(
          success: true,
          filePath: result,
          featureCount: features.length,
        );
      }

      return const ExportResult(
        success: false,
        errorMessage: 'Xuất GeoJSON thất bại',
      );
    } catch (e) {
      debugPrint('ExportService: exportGeoJson failed - $e');
      return ExportResult(
        success: false,
        errorMessage: 'Lỗi xuất dữ liệu: $e',
      );
    }
  }

  /// Export all layers of a project as separate GeoJSON files in a folder
  ///
  /// Creates a subfolder with the project name and exports each layer
  /// as a separate .geojson file. Returns the folder path.
  Future<ExportResult> exportAllLayersGeoJson({
    required String projectId,
    required String username,
  }) async {
    try {
      final project = await _projectRepo.getById(projectId);
      if (project == null) {
        return const ExportResult(
          success: false,
          errorMessage: 'Không tìm thấy dự án',
        );
      }

      final layers = await _layerRepo.getByProject(projectId);
      if (layers.isEmpty) {
        return const ExportResult(
          success: false,
          errorMessage: 'Dự án không có lớp dữ liệu nào',
        );
      }

      // Create a subfolder for the export
      final exportDir = await _getExportDir();
      final safeUser = username.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final safeName = project.name.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final folderName = '${safeName}_${safeUser}_$timestamp';
      final outputFolder = Directory(p.join(exportDir.path, folderName));
      if (!await outputFolder.exists()) {
        await outputFolder.create(recursive: true);
      }

      int totalFeatures = 0;

      // Export each layer as a separate GeoJSON file
      for (final layer in layers) {
        final features = await _featureRepo.getByLayer(layer.id);
        final layerSafeName = layer.name.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
        final layerFilename = '$layerSafeName.geojson';
        final layerPath = p.join(outputFolder.path, layerFilename);

        await GeoJsonService.exportLayer(
          layer: layer,
          features: features,
          outputPath: layerPath,
        );

        totalFeatures += features.length;
      }

      debugPrint('ExportService: Exported ${layers.length} layers '
          '($totalFeatures features) to ${outputFolder.path}');

      return ExportResult(
        success: true,
        filePath: outputFolder.path,
        featureCount: totalFeatures,
      );
    } catch (e) {
      debugPrint('ExportService: exportAllLayersGeoJson failed - $e');
      return ExportResult(
        success: false,
        errorMessage: 'Lỗi xuất dữ liệu: $e',
      );
    }
  }

  /// Export project as a .lvtfield package (ZIP archive)
  ///
  /// The package contains:
  /// - `project.json` — project metadata
  /// - `layers/*.geojson` — each layer as GeoJSON
  /// - `forms.json` — form field definitions for all layers
  /// - `media/*` — media files (if any)
  Future<ExportResult> exportProjectPackage({
    required String projectId,
    required String username,
  }) async {
    try {
      final project = await _projectRepo.getById(projectId);
      if (project == null) {
        return const ExportResult(
          success: false,
          errorMessage: 'Không tìm thấy dự án',
        );
      }

      final layers = await _layerRepo.getByProject(projectId);
      final archive = Archive();
      int totalFeatures = 0;

      // 1. Add project.json
      final projectJson = const JsonEncoder.withIndent('  ').convert({
        'id': project.id,
        'name': project.name,
        'description': project.description,
        'crs': project.crs,
        'created_at': project.createdAt.toIso8601String(),
        'updated_at': project.updatedAt.toIso8601String(),
        'exported_at': DateTime.now().toIso8601String(),
        'exported_by': username,
        'layer_count': layers.length,
      });
      archive.addFile(ArchiveFile(
        'project.json',
        utf8.encode(projectJson).length,
        utf8.encode(projectJson),
      ));

      // 2. Add each layer as GeoJSON + collect form definitions
      final allForms = <Map<String, dynamic>>[];

      for (final layer in layers) {
        final features = await _featureRepo.getByLayer(layer.id);
        totalFeatures += features.length;

        // Build GeoJSON FeatureCollection
        final geoJson = _buildFeatureCollectionForPackage(layer, features);
        final geoJsonStr = const JsonEncoder.withIndent('  ').convert(geoJson);
        final safeName = layer.name.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
        final layerFileName = 'layers/$safeName.geojson';

        archive.addFile(ArchiveFile(
          layerFileName,
          utf8.encode(geoJsonStr).length,
          utf8.encode(geoJsonStr),
        ));

        // Collect form field definitions from database
        final db = await AppDatabase.database;
        final formMaps = await db.query(
          'form_fields',
          where: 'layer_id = ?',
          whereArgs: [layer.id],
          orderBy: 'sort_order ASC',
        );

        if (formMaps.isNotEmpty) {
          allForms.add({
            'layer_id': layer.id,
            'layer_name': layer.name,
            'geometry_type': layer.geometryType.name,
            'fields': formMaps,
          });
        }
      }

      // 3. Add forms.json
      final formsJson = const JsonEncoder.withIndent('  ').convert(allForms);
      archive.addFile(ArchiveFile(
        'forms.json',
        utf8.encode(formsJson).length,
        utf8.encode(formsJson),
      ));

      // 4. Add media files (if they exist)
      final db = await AppDatabase.database;
      final mediaMaps = await db.rawQuery('''
        SELECT m.* FROM media m
        INNER JOIN features f ON m.feature_id = f.id
        INNER JOIN layers l ON f.layer_id = l.id
        WHERE l.project_id = ?
      ''', [projectId]);

      for (final mediaMap in mediaMaps) {
        final filePath = mediaMap['file_path'] as String;
        final file = File(filePath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final mediaFileName = 'media/${p.basename(filePath)}';
          archive.addFile(ArchiveFile(
            mediaFileName,
            bytes.length,
            bytes,
          ));
        }
      }

      // 5. Encode ZIP and write to file
      final zipData = ZipEncoder().encode(archive);
      if (zipData == null) {
        return const ExportResult(
          success: false,
          errorMessage: 'Không thể tạo file ZIP',
        );
      }

      final exportDir = await _getExportDir();
      final filename = _generateFilename(
        projectName: project.name,
        username: username,
        extension: 'lvtfield',
      );
      final outputPath = p.join(exportDir.path, filename);
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(zipData);

      debugPrint('ExportService: Exported package to $outputPath '
          '(${layers.length} layers, $totalFeatures features)');

      return ExportResult(
        success: true,
        filePath: outputPath,
        featureCount: totalFeatures,
      );
    } catch (e) {
      debugPrint('ExportService: exportProjectPackage failed - $e');
      return ExportResult(
        success: false,
        errorMessage: 'Lỗi xuất gói dữ liệu: $e',
      );
    }
  }

  /// Build a GeoJSON FeatureCollection with layer metadata

  // ===========================================================================
  // KML Export
  // ===========================================================================

  /// Export a layer as KML (Google Earth format)
  Future<ExportResult> exportKML({
    required String projectId,
    required String layerId,
    required String username,
  }) async {
    try {
      final project = await _projectRepo.getById(projectId);
      if (project == null) {
        return const ExportResult(success: false, errorMessage: 'Không tìm thấy dự án');
      }
      final layer = await _layerRepo.getById(layerId);
      if (layer == null) {
        return const ExportResult(success: false, errorMessage: 'Không tìm thấy lớp');
      }
      final features = await _featureRepo.getByLayer(layerId);

      final placemarks = <xml.XmlNode>[];
      for (final f in features) {
        final coordStr = _kmlCoordString(f.coordinates, layer.geometryType);
        xml.XmlNode geom;
        switch (layer.geometryType) {
          case GeometryType.point:
            geom = xml.XmlElement(xml.XmlName('Point'), [],
                [xml.XmlElement(xml.XmlName('coordinates'), [], [xml.XmlText(coordStr)])]);
            break;
          case GeometryType.line:
            geom = xml.XmlElement(xml.XmlName('LineString'), [],
                [xml.XmlElement(xml.XmlName('coordinates'), [], [xml.XmlText(coordStr)])]);
            break;
          case GeometryType.polygon:
            geom = xml.XmlElement(xml.XmlName('Polygon'), [], [
              xml.XmlElement(xml.XmlName('outerBoundaryIs'), [], [
                xml.XmlElement(xml.XmlName('LinearRing'), [],
                    [xml.XmlElement(xml.XmlName('coordinates'), [], [xml.XmlText(coordStr)])])
              ])
            ]);
            break;
        }

        final extData = f.attributes.entries.map((e) =>
            xml.XmlElement(xml.XmlName('Data'), [xml.XmlAttribute(xml.XmlName('name'), e.key)],
                [xml.XmlElement(xml.XmlName('value'), [], [xml.XmlText('${e.value}')])])).toList();

        placemarks.add(xml.XmlElement(xml.XmlName('Placemark'), [], [
          xml.XmlElement(xml.XmlName('name'), [], [xml.XmlText(f.attributes['name']?.toString() ?? f.id.substring(0, 8))]),
          geom,
          if (extData.isNotEmpty) xml.XmlElement(xml.XmlName('ExtendedData'), [], extData),
        ]));
      }

      final doc = xml.XmlDocument([
        xml.XmlProcessing('xml', 'version="1.0" encoding="UTF-8"'),
        xml.XmlElement(xml.XmlName('kml'), [xml.XmlAttribute(xml.XmlName('xmlns'), 'http://www.opengis.net/kml/2.2')], [
          xml.XmlElement(xml.XmlName('Document'), [], [
            xml.XmlElement(xml.XmlName('name'), [], [xml.XmlText('${project.name} - ${layer.name}')]),
            xml.XmlElement(xml.XmlName('Folder'), [
              xml.XmlAttribute(xml.XmlName('id'), layer.id),
            ], [
              xml.XmlElement(xml.XmlName('name'), [], [xml.XmlText(layer.name)]),
              ...placemarks,
            ]),
          ]),
        ]),
      ]);

      final exportDir = await _getExportDir();
      final filename = _generateFilename(projectName: '${project.name}_${layer.name}', username: username, extension: 'kml');
      final outputPath = p.join(exportDir.path, filename);
      await File(outputPath).writeAsString(doc.toXmlString(pretty: true, indent: '  '));

      return ExportResult(success: true, filePath: outputPath, featureCount: features.length);
    } catch (e) {
      return ExportResult(success: false, errorMessage: 'Lỗi xuất KML: $e');
    }
  }

  String _kmlCoordString(List<LatLng> coords, GeometryType type) {
    final s = coords.map((c) => '${c.longitude},${c.latitude},0').join(' ');
    if (type == GeometryType.polygon && coords.length >= 3) {
      return '$s ${coords.first.longitude},${coords.first.latitude},0';
    }
    return s;
  }

  // ===========================================================================
  // GPX Export
  // ===========================================================================

  /// Export a layer as GPX (GPS exchange format)
  Future<ExportResult> exportGPX({
    required String projectId,
    required String layerId,
    required String username,
  }) async {
    try {
      final project = await _projectRepo.getById(projectId);
      if (project == null) return const ExportResult(success: false, errorMessage: 'Không tìm thấy dự án');
      final layer = await _layerRepo.getById(layerId);
      if (layer == null) return const ExportResult(success: false, errorMessage: 'Không tìm thấy lớp');
      final features = await _featureRepo.getByLayer(layerId);

      final children = <xml.XmlNode>[
        xml.XmlElement(xml.XmlName('metadata'), [], [
          xml.XmlElement(xml.XmlName('name'), [], [xml.XmlText('${project.name} - ${layer.name}')]),
          xml.XmlElement(xml.XmlName('author'), [], [
            xml.XmlElement(xml.XmlName('name'), [], [xml.XmlText(username)]),
          ]),
        ]),
      ];

      for (final f in features) {
        switch (layer.geometryType) {
          case GeometryType.point:
            if (f.coordinates.isNotEmpty) {
              final c = f.coordinates.first;
              children.add(xml.XmlElement(xml.XmlName('wpt'), [
                xml.XmlAttribute(xml.XmlName('lat'), c.latitude.toString()),
                xml.XmlAttribute(xml.XmlName('lon'), c.longitude.toString()),
              ], [
                xml.XmlElement(xml.XmlName('name'), [], [xml.XmlText(f.attributes['name']?.toString() ?? f.id.substring(0, 8))]),
                xml.XmlElement(xml.XmlName('time'), [], [xml.XmlText(f.collectedAt.toIso8601String())]),
              ]));
            }
            break;
          case GeometryType.line:
            children.add(xml.XmlElement(xml.XmlName('trk'), [], [
              xml.XmlElement(xml.XmlName('name'), [], [xml.XmlText(f.attributes['name']?.toString() ?? f.id.substring(0, 8))]),
              xml.XmlElement(xml.XmlName('trkseg'), [], f.coordinates.map((c) =>
                xml.XmlElement(xml.XmlName('trkpt'), [
                  xml.XmlAttribute(xml.XmlName('lat'), c.latitude.toString()),
                  xml.XmlAttribute(xml.XmlName('lon'), c.longitude.toString()),
                ], [xml.XmlElement(xml.XmlName('time'), [], [xml.XmlText(f.collectedAt.toIso8601String())])])
              ).toList()),
            ]));
            break;
          case GeometryType.polygon:
            children.add(xml.XmlElement(xml.XmlName('rte'), [], [
              xml.XmlElement(xml.XmlName('name'), [], [xml.XmlText(f.attributes['name']?.toString() ?? f.id.substring(0, 8))]),
              ...f.coordinates.map((c) =>
                xml.XmlElement(xml.XmlName('rtept'), [
                  xml.XmlAttribute(xml.XmlName('lat'), c.latitude.toString()),
                  xml.XmlAttribute(xml.XmlName('lon'), c.longitude.toString()),
                ], [])
              ),
            ]));
            break;
        }
      }

      final doc = xml.XmlDocument([
        xml.XmlProcessing('xml', 'version="1.0" encoding="UTF-8"'),
        xml.XmlElement(xml.XmlName('gpx'), [
          xml.XmlAttribute(xml.XmlName('version'), '1.1'),
          xml.XmlAttribute(xml.XmlName('creator'), 'LVTField'),
          xml.XmlAttribute(xml.XmlName('xmlns'), 'http://www.topografix.com/GPX/1/1'),
        ], children),
      ]);

      final exportDir = await _getExportDir();
      final filename = _generateFilename(projectName: '${project.name}_${layer.name}', username: username, extension: 'gpx');
      final outputPath = p.join(exportDir.path, filename);
      await File(outputPath).writeAsString(doc.toXmlString(pretty: true, indent: '  '));

      return ExportResult(success: true, filePath: outputPath, featureCount: features.length);
    } catch (e) {
      return ExportResult(success: false, errorMessage: 'Lỗi xuất GPX: $e');
    }
  }

  // ===========================================================================
  // CSV Export
  // ===========================================================================

  /// Export layer attributes as CSV (Excel-friendly with UTF-8 BOM)
  Future<ExportResult> exportCSV({
    required String projectId,
    required String layerId,
    required String username,
  }) async {
    try {
      final project = await _projectRepo.getById(projectId);
      if (project == null) return const ExportResult(success: false, errorMessage: 'Không tìm thấy dự án');
      final layer = await _layerRepo.getById(layerId);
      if (layer == null) return const ExportResult(success: false, errorMessage: 'Không tìm thấy lớp');
      final features = await _featureRepo.getByLayer(layerId);

      // Collect all unique attribute keys
      final attrKeys = <String>{};
      for (final f in features) {
        attrKeys.addAll(f.attributes.keys);
      }
      final sortedKeys = attrKeys.toList()..sort();

      // Build CSV
      final buf = StringBuffer();
      // Header
      buf.writeln(['id', 'latitude', 'longitude', 'collected_at', 'gps_accuracy', ...sortedKeys]
          .map((h) => '"$h"').join(','));

      // Rows
      for (final f in features) {
        final lat = f.coordinates.isNotEmpty ? f.coordinates.first.latitude : '';
        final lng = f.coordinates.isNotEmpty ? f.coordinates.first.longitude : '';
        final row = [
          f.id,
          lat,
          lng,
          f.collectedAt.toIso8601String(),
          f.gpsAccuracy ?? '',
          ...sortedKeys.map((k) => f.attributes[k] ?? ''),
        ];
        buf.writeln(row.map((v) => '"${v.toString().replaceAll('"', '""')}"').join(','));
      }

      final exportDir = await _getExportDir();
      final filename = _generateFilename(projectName: '${project.name}_${layer.name}', username: username, extension: 'csv');
      final outputPath = p.join(exportDir.path, filename);
      // Write with UTF-8 BOM for Excel compatibility
      final bom = [0xEF, 0xBB, 0xBF];
      await File(outputPath).writeAsBytes([...bom, ...utf8.encode(buf.toString())]);

      return ExportResult(success: true, filePath: outputPath, featureCount: features.length);
    } catch (e) {
      return ExportResult(success: false, errorMessage: 'Lỗi xuất CSV: $e');
    }
  }

  // ===========================================================================
  // KMZ Export (KML compressed in ZIP)
  // ===========================================================================

  /// Export a layer as KMZ (compressed KML)
  Future<ExportResult> exportKMZ({
    required String projectId,
    required String layerId,
    required String username,
  }) async {
    try {
      // First export as KML
      final kmlResult = await exportKML(projectId: projectId, layerId: layerId, username: username);
      if (!kmlResult.success || kmlResult.filePath == null) {
        return ExportResult(success: false, errorMessage: kmlResult.errorMessage ?? 'KML export failed');
      }

      // Read KML and compress into KMZ
      final kmlFile = File(kmlResult.filePath!);
      final kmlBytes = await kmlFile.readAsBytes();

      final archive = Archive();
      archive.addFile(ArchiveFile('doc.kml', kmlBytes.length, kmlBytes));

      final zipData = ZipEncoder().encode(archive);
      if (zipData == null) {
        return const ExportResult(success: false, errorMessage: 'Không thể tạo KMZ');
      }

      final exportDir = await _getExportDir();
      final filename = _generateFilename(
        projectName: p.basenameWithoutExtension(kmlResult.filePath!),
        username: username,
        extension: 'kmz',
      );
      final outputPath = p.join(exportDir.path, filename);
      await File(outputPath).writeAsBytes(zipData);

      // Clean up temp KML
      await kmlFile.delete();

      return ExportResult(success: true, filePath: outputPath, featureCount: kmlResult.featureCount);
    } catch (e) {
      return ExportResult(success: false, errorMessage: 'Lỗi xuất KMZ: $e');
    }
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  Map<String, dynamic> _buildFeatureCollectionForPackage(
    LayerModel layer,
    List<FeatureModel> features,
  ) {
    return {
      'type': 'FeatureCollection',
      'name': layer.name,
      'crs': {
        'type': 'name',
        'properties': {
          'name': 'urn:ogc:def:crs:OGC:1.3:CRS84',
        },
      },
      'lvtfield_metadata': {
        'layer_id': layer.id,
        'geometry_type': layer.geometryType.name,
        'style_config': layer.styleConfig,
        'z_order': layer.zOrder,
        'opacity': layer.opacity,
      },
      'features': features.map((f) => _buildGeoJsonFeature(f, layer.geometryType)).toList(),
    };
  }

  /// Build a single GeoJSON Feature with all attributes
  Map<String, dynamic> _buildGeoJsonFeature(
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

  /// Build GeoJSON geometry from feature coordinates
  Map<String, dynamic> _buildGeometry(
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
        // Ensure polygon ring is closed
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

  /// Share an exported file using the system share dialog
  Future<void> shareFile(String filePath) async {
    try {
      final file = XFile(filePath);
      await Share.shareXFiles(
        [file],
        subject: 'LVTField - Dữ liệu khảo sát',
      );
    } catch (e) {
      debugPrint('ExportService: shareFile failed - $e');
    }
  }

  /// Get a human-readable description of the export file
  String getExportDescription(String filePath) {
    final filename = p.basename(filePath);
    final ext = p.extension(filePath).toLowerCase();

    switch (ext) {
      case '.geojson':
        return 'GeoJSON: $filename';
      case '.lvtfield':
        return 'Gói LVTField: $filename';
      case '.kml':
        return 'KML (Google Earth): $filename';
      case '.kmz':
        return 'KMZ (KML nén): $filename';
      case '.gpx':
        return 'GPX (GPS Track): $filename';
      case '.csv':
        return 'CSV (Excel): $filename';
      default:
        return filename;
    }
  }
}
