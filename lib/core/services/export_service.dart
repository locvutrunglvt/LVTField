// Export service for LVTField project data
// Supports GeoJSON, KML, GPX, CSV, KMZ, GeoPackage and .lvtfield package formats
// Author: Lộc Vũ Trung

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';
import 'package:xml/xml.dart' as xml;
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
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
  // GeoPackage (GPKG) Export
  // ===========================================================================

  /// Export all layers of a project as a GeoPackage (.gpkg) file
  ///
  /// Creates an OGC-compliant GeoPackage SQLite database with:
  /// - `gpkg_spatial_ref_sys` table (EPSG:4326)
  /// - `gpkg_contents` table
  /// - `gpkg_geometry_columns` table
  /// - Feature table(s) with GeoPackage Binary (GPB) geometry
  /// - `layer_styles` table with QML style data (QGIS compatible)
  Future<ExportResult> exportGeoPackage({
    required String projectId,
    required String username,
  }) async {
    try {
      final project = await _projectRepo.getById(projectId);
      if (project == null) {
        return const ExportResult(success: false, errorMessage: 'Không tìm thấy dự án');
      }

      final layers = await _layerRepo.getByProject(projectId);
      if (layers.isEmpty) {
        return const ExportResult(success: false, errorMessage: 'Dự án không có lớp dữ liệu nào');
      }

      // Create output file path
      final exportDir = await _getExportDir();
      final filename = _generateFilename(
        projectName: project.name,
        username: username,
        extension: 'gpkg',
      );
      final outputPath = p.join(exportDir.path, filename);

      // Create GeoPackage SQLite database
      final db = await openDatabase(outputPath, version: 1);

      int totalFeatures = 0;

      try {
        // 1. Create GeoPackage metadata tables
        await _gpkgCreateMetadataTables(db);

        // 2. Create layer_styles table (QGIS compatible)
        await _gpkgCreateLayerStylesTable(db);

        // 3. Process each layer
        for (final layer in layers) {
          final features = await _featureRepo.getByLayer(layer.id);
          final tableName = _gpkgSanitizeTableName(layer.name);
          final geomColumn = 'geom';
          final geomTypeName = _gpkgGeometryTypeName(layer.geometryType);

          // Collect all unique attribute keys across features
          final attrKeys = <String>{};
          for (final f in features) {
            attrKeys.addAll(f.attributes.keys);
          }
          final sortedAttrKeys = attrKeys.toList()..sort();

          // Create feature table
          await _gpkgCreateFeatureTable(db, tableName, geomColumn, sortedAttrKeys);

          // Register in gpkg_contents
          double minX = 180, minY = 90, maxX = -180, maxY = -90;
          for (final f in features) {
            for (final c in f.coordinates) {
              if (c.longitude < minX) minX = c.longitude;
              if (c.longitude > maxX) maxX = c.longitude;
              if (c.latitude < minY) minY = c.latitude;
              if (c.latitude > maxY) maxY = c.latitude;
            }
          }

          await db.insert('gpkg_contents', {
            'table_name': tableName,
            'data_type': 'features',
            'identifier': layer.name,
            'description': '',
            'last_change': DateTime.now().toUtc().toIso8601String(),
            'min_x': features.isEmpty ? 0 : minX,
            'min_y': features.isEmpty ? 0 : minY,
            'max_x': features.isEmpty ? 0 : maxX,
            'max_y': features.isEmpty ? 0 : maxY,
            'srs_id': 4326,
          });

          // Register in gpkg_geometry_columns
          await db.insert('gpkg_geometry_columns', {
            'table_name': tableName,
            'column_name': geomColumn,
            'geometry_type_name': geomTypeName,
            'srs_id': 4326,
            'z': 0,
            'm': 0,
          });

          // Insert features
          for (final f in features) {
            final gpbBytes = _gpkgEncodeGeometry(f.coordinates, layer.geometryType);
            final row = <String, dynamic>{
              geomColumn: gpbBytes,
            };
            for (final key in sortedAttrKeys) {
              final colName = _gpkgSanitizeColumnName(key);
              row[colName] = f.attributes[key];
            }
            await db.insert(tableName, row);
            totalFeatures++;
          }

          // Insert QML style into layer_styles
          final qmlXml = _gpkgGenerateQml(layer, geomColumn);
          await db.insert('layer_styles', {
            'f_table_catalog': '',
            'f_table_schema': '',
            'f_table_name': tableName,
            'f_geometry_column': geomColumn,
            'styleName': 'default',
            'styleQML': qmlXml,
            'styleSLD': null,
            'useAsDefault': 1,
            'description': '',
            'owner': username,
            'ui': null,
          });

          debugPrint('ExportService: GPKG table "$tableName" — '
              '${features.length} features, style inserted');
        }
      } finally {
        await db.close();
      }

      // Set the SQLite application_id to 0x47504B47 ('GPKG') for OGC compliance
      await _gpkgSetApplicationId(outputPath);

      debugPrint('ExportService: Exported GeoPackage to $outputPath '
          '(${layers.length} layers, $totalFeatures features)');

      return ExportResult(
        success: true,
        filePath: outputPath,
        featureCount: totalFeatures,
      );
    } catch (e) {
      debugPrint('ExportService: exportGeoPackage failed - $e');
      return ExportResult(
        success: false,
        errorMessage: 'Lỗi xuất GeoPackage: $e',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // GeoPackage helpers
  // ---------------------------------------------------------------------------

  /// Create OGC GeoPackage metadata tables
  Future<void> _gpkgCreateMetadataTables(Database db) async {
    // gpkg_spatial_ref_sys
    await db.execute('''
      CREATE TABLE IF NOT EXISTS gpkg_spatial_ref_sys (
        srs_name TEXT NOT NULL,
        srs_id INTEGER NOT NULL PRIMARY KEY,
        organization TEXT NOT NULL,
        organization_coordsys_id INTEGER NOT NULL,
        definition TEXT NOT NULL,
        description TEXT
      )
    ''');
    // Insert WGS 84 (EPSG:4326)
    await db.insert('gpkg_spatial_ref_sys', {
      'srs_name': 'WGS 84 geodetic',
      'srs_id': 4326,
      'organization': 'EPSG',
      'organization_coordsys_id': 4326,
      'definition': 'GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563]],PRIMEM["Greenwich",0],UNIT["degree",0.0174532925199433]]',
      'description': 'longitude/latitude coordinates in decimal degrees on the WGS 84 spheroid',
    });
    // Undefined Cartesian (srs_id = -1)
    await db.insert('gpkg_spatial_ref_sys', {
      'srs_name': 'Undefined cartesian SRS',
      'srs_id': -1,
      'organization': 'NONE',
      'organization_coordsys_id': -1,
      'definition': 'undefined',
      'description': 'undefined cartesian coordinate reference system',
    });
    // Undefined Geographic (srs_id = 0)
    await db.insert('gpkg_spatial_ref_sys', {
      'srs_name': 'Undefined geographic SRS',
      'srs_id': 0,
      'organization': 'NONE',
      'organization_coordsys_id': 0,
      'definition': 'undefined',
      'description': 'undefined geographic coordinate reference system',
    });

    // gpkg_contents
    await db.execute('''
      CREATE TABLE IF NOT EXISTS gpkg_contents (
        table_name TEXT NOT NULL PRIMARY KEY,
        data_type TEXT NOT NULL,
        identifier TEXT UNIQUE,
        description TEXT DEFAULT '',
        last_change DATETIME NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
        min_x DOUBLE,
        min_y DOUBLE,
        max_x DOUBLE,
        max_y DOUBLE,
        srs_id INTEGER,
        CONSTRAINT fk_gc_r_srs_id FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys(srs_id)
      )
    ''');

    // gpkg_geometry_columns
    await db.execute('''
      CREATE TABLE IF NOT EXISTS gpkg_geometry_columns (
        table_name TEXT NOT NULL,
        column_name TEXT NOT NULL,
        geometry_type_name TEXT NOT NULL,
        srs_id INTEGER NOT NULL,
        z TINYINT NOT NULL,
        m TINYINT NOT NULL,
        CONSTRAINT pk_geom_cols PRIMARY KEY (table_name, column_name),
        CONSTRAINT fk_gc_tn FOREIGN KEY (table_name) REFERENCES gpkg_contents(table_name),
        CONSTRAINT fk_gc_srs FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys(srs_id)
      )
    ''');
  }

  /// Create the QGIS-compatible layer_styles table
  Future<void> _gpkgCreateLayerStylesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS layer_styles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        f_table_catalog TEXT DEFAULT '',
        f_table_schema TEXT DEFAULT '',
        f_table_name TEXT NOT NULL,
        f_geometry_column TEXT NOT NULL,
        styleName TEXT DEFAULT 'default',
        styleQML TEXT,
        styleSLD TEXT,
        useAsDefault BOOLEAN DEFAULT 1,
        description TEXT DEFAULT '',
        owner TEXT DEFAULT '',
        ui TEXT,
        update_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');
  }

  /// Create a feature table with geometry column and attribute columns
  Future<void> _gpkgCreateFeatureTable(
    Database db,
    String tableName,
    String geomColumn,
    List<String> attrKeys,
  ) async {
    final colDefs = StringBuffer();
    colDefs.write('fid INTEGER PRIMARY KEY AUTOINCREMENT, ');
    colDefs.write('$geomColumn BLOB');
    for (final key in attrKeys) {
      final colName = _gpkgSanitizeColumnName(key);
      colDefs.write(', [$colName] TEXT');
    }
    await db.execute('CREATE TABLE IF NOT EXISTS [$tableName] ($colDefs)');
  }

  /// Sanitize a layer name for use as a SQLite table name
  String _gpkgSanitizeTableName(String name) {
    var safe = name.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    // Ensure it doesn't start with a digit
    if (safe.isNotEmpty && RegExp(r'^[0-9]').hasMatch(safe)) {
      safe = 'layer_$safe';
    }
    if (safe.isEmpty) safe = 'layer';
    return safe;
  }

  /// Sanitize an attribute key for use as a SQLite column name
  String _gpkgSanitizeColumnName(String name) {
    var safe = name.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    if (safe.isEmpty) safe = 'col';
    return safe;
  }

  /// Map GeometryType to OGC geometry type name
  String _gpkgGeometryTypeName(GeometryType type) {
    switch (type) {
      case GeometryType.point:
        return 'POINT';
      case GeometryType.line:
        return 'LINESTRING';
      case GeometryType.polygon:
        return 'POLYGON';
    }
  }

  /// Set the SQLite application_id to GeoPackage magic number
  ///
  /// sqflite doesn't support PRAGMA application_id directly, so
  /// we write 'GPKG' (0x47504B47) at byte offset 68 in the file.
  Future<void> _gpkgSetApplicationId(String filePath) async {
    try {
      final raf = await File(filePath).open(mode: FileMode.writeOnlyAppend);
      try {
        await raf.setPosition(68);
        // Write 0x47504B47 big-endian = 'GPKG'
        await raf.writeFrom(Uint8List.fromList([0x47, 0x50, 0x4B, 0x47]));
      } finally {
        await raf.close();
      }
    } catch (e) {
      debugPrint('ExportService: Could not set GPKG application_id: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // GPB (GeoPackage Binary) geometry encoding
  // ---------------------------------------------------------------------------

  /// Encode coordinates as GeoPackage Binary (GPB) geometry
  ///
  /// GPB format:
  /// - Header: 'GP' (0x47, 0x50)
  /// - Version: 0x00
  /// - Flags: 0x01 (standard, little-endian, no envelope)
  /// - SRS ID: 4326 (4 bytes LE)
  /// - WKB geometry body
  Uint8List _gpkgEncodeGeometry(List<LatLng> coordinates, GeometryType type) {
    // Build WKB body first
    final wkb = _gpkgEncodeWkb(coordinates, type);

    // GPB header: 8 bytes + WKB
    final result = ByteData(8 + wkb.length);
    result.setUint8(0, 0x47); // 'G'
    result.setUint8(1, 0x50); // 'P'
    result.setUint8(2, 0x00); // version
    result.setUint8(3, 0x01); // flags: little-endian, no envelope
    result.setInt32(4, 4326, Endian.little); // SRS ID

    // Copy WKB after header
    final bytes = result.buffer.asUint8List();
    bytes.setRange(8, 8 + wkb.length, wkb);
    return bytes;
  }

  /// Encode coordinates as WKB (Well-Known Binary)
  Uint8List _gpkgEncodeWkb(List<LatLng> coordinates, GeometryType type) {
    switch (type) {
      case GeometryType.point:
        return _gpkgEncodeWkbPoint(coordinates.first);
      case GeometryType.line:
        return _gpkgEncodeWkbLineString(coordinates);
      case GeometryType.polygon:
        return _gpkgEncodeWkbPolygon(coordinates);
    }
  }

  /// Encode a Point as WKB
  Uint8List _gpkgEncodeWkbPoint(LatLng coord) {
    // byte-order(1) + type(4) + x(8) + y(8) = 21 bytes
    final data = ByteData(21);
    data.setUint8(0, 1); // little-endian
    data.setUint32(1, 1, Endian.little); // wkbPoint = 1
    data.setFloat64(5, coord.longitude, Endian.little);
    data.setFloat64(13, coord.latitude, Endian.little);
    return data.buffer.asUint8List();
  }

  /// Encode a LineString as WKB
  Uint8List _gpkgEncodeWkbLineString(List<LatLng> coordinates) {
    // byte-order(1) + type(4) + numPoints(4) + points(numPoints * 16)
    final numPoints = coordinates.length;
    final data = ByteData(9 + numPoints * 16);
    data.setUint8(0, 1); // little-endian
    data.setUint32(1, 2, Endian.little); // wkbLineString = 2
    data.setUint32(5, numPoints, Endian.little);
    int offset = 9;
    for (final c in coordinates) {
      data.setFloat64(offset, c.longitude, Endian.little);
      data.setFloat64(offset + 8, c.latitude, Endian.little);
      offset += 16;
    }
    return data.buffer.asUint8List();
  }

  /// Encode a Polygon as WKB (single outer ring, auto-closed)
  Uint8List _gpkgEncodeWkbPolygon(List<LatLng> coordinates) {
    // Ensure ring is closed
    final ring = List<LatLng>.from(coordinates);
    if (ring.length >= 3 &&
        (ring.first.latitude != ring.last.latitude ||
            ring.first.longitude != ring.last.longitude)) {
      ring.add(ring.first);
    }

    final numPoints = ring.length;
    // byte-order(1) + type(4) + numRings(4) + numPoints(4) + points(numPoints * 16)
    final data = ByteData(13 + numPoints * 16);
    data.setUint8(0, 1); // little-endian
    data.setUint32(1, 3, Endian.little); // wkbPolygon = 3
    data.setUint32(5, 1, Endian.little); // 1 ring
    data.setUint32(9, numPoints, Endian.little);
    int offset = 13;
    for (final c in ring) {
      data.setFloat64(offset, c.longitude, Endian.little);
      data.setFloat64(offset + 8, c.latitude, Endian.little);
      offset += 16;
    }
    return data.buffer.asUint8List();
  }

  // ---------------------------------------------------------------------------
  // QML style generation for GPKG layer_styles table
  // ---------------------------------------------------------------------------

  /// Generate QGIS-compatible QML XML from LayerModel.styleConfig
  String _gpkgGenerateQml(LayerModel layer, String geomColumn) {
    final style = layer.styleConfig;
    final geomType = layer.geometryType;

    // Determine symbol type and symbol layer class
    String symbolType;
    String symbolLayerClass;
    switch (geomType) {
      case GeometryType.point:
        symbolType = 'marker';
        symbolLayerClass = 'SimpleMarker';
        break;
      case GeometryType.line:
        symbolType = 'line';
        symbolLayerClass = 'SimpleLine';
        break;
      case GeometryType.polygon:
        symbolType = 'fill';
        symbolLayerClass = 'SimpleFill';
        break;
    }

    // Build <prop> elements for the symbol layer
    final props = <xml.XmlNode>[];

    switch (geomType) {
      case GeometryType.polygon:
        // Fill color
        final fillColor = style['fillColor'] as num? ?? 0xFF00FF00;
        props.add(xml.XmlElement(xml.XmlName('prop'), [
          xml.XmlAttribute(xml.XmlName('k'), 'color'),
          xml.XmlAttribute(xml.XmlName('v'), _colorToQgis(fillColor.toInt())),
        ]));
        // Outline (stroke) color
        final strokeColor = style['strokeColor'] as num? ?? 0xFF000000;
        props.add(xml.XmlElement(xml.XmlName('prop'), [
          xml.XmlAttribute(xml.XmlName('k'), 'outline_color'),
          xml.XmlAttribute(xml.XmlName('v'), _colorToQgis(strokeColor.toInt())),
        ]));
        // Outline width (convert pixels back to mm: /3)
        final strokeWidth = (style['strokeWidth'] as num?)?.toDouble() ?? 1.5;
        final strokeWidthMm = (strokeWidth / 3.0).clamp(0.1, 5.0);
        props.add(xml.XmlElement(xml.XmlName('prop'), [
          xml.XmlAttribute(xml.XmlName('k'), 'outline_width'),
          xml.XmlAttribute(xml.XmlName('v'), strokeWidthMm.toStringAsFixed(2)),
        ]));
        // Fill style
        props.add(xml.XmlElement(xml.XmlName('prop'), [
          xml.XmlAttribute(xml.XmlName('k'), 'style'),
          xml.XmlAttribute(xml.XmlName('v'), 'solid'),
        ]));
        props.add(xml.XmlElement(xml.XmlName('prop'), [
          xml.XmlAttribute(xml.XmlName('k'), 'outline_style'),
          xml.XmlAttribute(xml.XmlName('v'), 'solid'),
        ]));
        break;

      case GeometryType.line:
        // Line color
        final lineColor = style['color'] as num? ?? style['strokeColor'] as num? ?? 0xFF00FF00;
        props.add(xml.XmlElement(xml.XmlName('prop'), [
          xml.XmlAttribute(xml.XmlName('k'), 'line_color'),
          xml.XmlAttribute(xml.XmlName('v'), _colorToQgis(lineColor.toInt())),
        ]));
        // Line width
        final lineWidth = (style['width'] as num?)?.toDouble() ??
            (style['strokeWidth'] as num?)?.toDouble() ?? 1.5;
        final lineWidthMm = (lineWidth / 3.0).clamp(0.1, 5.0);
        props.add(xml.XmlElement(xml.XmlName('prop'), [
          xml.XmlAttribute(xml.XmlName('k'), 'line_width'),
          xml.XmlAttribute(xml.XmlName('v'), lineWidthMm.toStringAsFixed(2)),
        ]));
        // Line style
        props.add(xml.XmlElement(xml.XmlName('prop'), [
          xml.XmlAttribute(xml.XmlName('k'), 'line_style'),
          xml.XmlAttribute(xml.XmlName('v'), 'solid'),
        ]));
        break;

      case GeometryType.point:
        // Point color
        final pointColor = style['color'] as num? ?? 0xFF00FF00;
        props.add(xml.XmlElement(xml.XmlName('prop'), [
          xml.XmlAttribute(xml.XmlName('k'), 'color'),
          xml.XmlAttribute(xml.XmlName('v'), _colorToQgis(pointColor.toInt())),
        ]));
        // Point outline color
        final strokeColor = style['strokeColor'] as num? ?? 0xFF000000;
        props.add(xml.XmlElement(xml.XmlName('prop'), [
          xml.XmlAttribute(xml.XmlName('k'), 'outline_color'),
          xml.XmlAttribute(xml.XmlName('v'), _colorToQgis(strokeColor.toInt())),
        ]));
        // Point size (convert pixels back to mm: /3)
        final pointSize = (style['size'] as num?)?.toDouble() ?? 12.0;
        final sizeMm = (pointSize / 3.0).clamp(1.0, 10.0);
        props.add(xml.XmlElement(xml.XmlName('prop'), [
          xml.XmlAttribute(xml.XmlName('k'), 'size'),
          xml.XmlAttribute(xml.XmlName('v'), sizeMm.toStringAsFixed(2)),
        ]));
        // Point outline width
        final strokeWidth = (style['strokeWidth'] as num?)?.toDouble() ?? 1.5;
        final strokeWidthMm = (strokeWidth / 3.0).clamp(0.1, 5.0);
        props.add(xml.XmlElement(xml.XmlName('prop'), [
          xml.XmlAttribute(xml.XmlName('k'), 'outline_width'),
          xml.XmlAttribute(xml.XmlName('v'), strokeWidthMm.toStringAsFixed(2)),
        ]));
        // Marker name (shape)
        props.add(xml.XmlElement(xml.XmlName('prop'), [
          xml.XmlAttribute(xml.XmlName('k'), 'name'),
          xml.XmlAttribute(xml.XmlName('v'), 'circle'),
        ]));
        break;
    }

    // Build symbol layer → symbol → renderer-v2
    final symbolLayer = xml.XmlElement(
      xml.XmlName('layer'),
      [
        xml.XmlAttribute(xml.XmlName('class'), symbolLayerClass),
        xml.XmlAttribute(xml.XmlName('pass'), '0'),
        xml.XmlAttribute(xml.XmlName('locked'), '0'),
        xml.XmlAttribute(xml.XmlName('enabled'), '1'),
      ],
      props,
    );

    final symbol = xml.XmlElement(
      xml.XmlName('symbol'),
      [
        xml.XmlAttribute(xml.XmlName('name'), '0'),
        xml.XmlAttribute(xml.XmlName('type'), symbolType),
        xml.XmlAttribute(xml.XmlName('alpha'), '1'),
        xml.XmlAttribute(xml.XmlName('force_rhr'), '0'),
        xml.XmlAttribute(xml.XmlName('clip_to_extent'), '1'),
      ],
      [symbolLayer],
    );

    final symbols = xml.XmlElement(xml.XmlName('symbols'), [], [symbol]);

    final renderer = xml.XmlElement(
      xml.XmlName('renderer-v2'),
      [
        xml.XmlAttribute(xml.XmlName('type'), 'singleSymbol'),
        xml.XmlAttribute(xml.XmlName('symbollevels'), '0'),
        xml.XmlAttribute(xml.XmlName('forceraster'), '0'),
        xml.XmlAttribute(xml.XmlName('enableorderby'), '0'),
      ],
      [symbols],
    );

    // Build labeling block if labelField is set
    final labelField = style['labelField'] as String?;
    xml.XmlElement? labeling;
    if (labelField != null && labelField.isNotEmpty) {
      final labelFontSize = (style['labelFontSize'] as num?)?.toDouble() ?? 10.0;

      // Label color
      final labelColorInt = (style['labelColor'] as num?)?.toInt() ?? 0xFF000000;
      final lA = (labelColorInt >> 24) & 0xFF;
      final lR = (labelColorInt >> 16) & 0xFF;
      final lG = (labelColorInt >> 8) & 0xFF;
      final lB = labelColorInt & 0xFF;

      final textColor = xml.XmlElement(
        xml.XmlName('text-color'),
        [
          xml.XmlAttribute(xml.XmlName('red'), '$lR'),
          xml.XmlAttribute(xml.XmlName('green'), '$lG'),
          xml.XmlAttribute(xml.XmlName('blue'), '$lB'),
          xml.XmlAttribute(xml.XmlName('alpha'), '$lA'),
        ],
      );

      final textStyle = xml.XmlElement(
        xml.XmlName('text-style'),
        [
          xml.XmlAttribute(xml.XmlName('fieldName'), labelField),
          xml.XmlAttribute(xml.XmlName('fontSize'), labelFontSize.toStringAsFixed(1)),
          xml.XmlAttribute(xml.XmlName('fontFamily'), 'Sans Serif'),
          xml.XmlAttribute(xml.XmlName('fontWeight'), '50'),
          xml.XmlAttribute(xml.XmlName('fontItalic'), '0'),
          xml.XmlAttribute(xml.XmlName('textOpacity'), '1'),
        ],
        [textColor],
      );

      final settings = xml.XmlElement(
        xml.XmlName('settings'),
        [xml.XmlAttribute(xml.XmlName('calloutType'), 'simple')],
        [textStyle],
      );

      labeling = xml.XmlElement(
        xml.XmlName('labeling'),
        [
          xml.XmlAttribute(xml.XmlName('type'), 'simple'),
        ],
        [settings],
      );
    }

    // Build root <qgis> element
    final qgisChildren = <xml.XmlNode>[renderer];
    if (labeling != null) qgisChildren.add(labeling);

    final qgisDoc = xml.XmlDocument([
      xml.XmlProcessing('xml', 'version="1.0" encoding="UTF-8"'),
      xml.XmlElement(
        xml.XmlName('qgis'),
        [
          xml.XmlAttribute(xml.XmlName('version'), '3.28.0'),
          xml.XmlAttribute(xml.XmlName('styleCategories'), 'Symbology|Labeling'),
        ],
        qgisChildren,
      ),
    ]);

    return qgisDoc.toXmlString(pretty: true, indent: '  ');
  }

  /// Convert a Flutter Color int (0xAARRGGBB) to QGIS format string "R,G,B,A"
  String _colorToQgis(int colorInt) {
    final a = (colorInt >> 24) & 0xFF;
    final r = (colorInt >> 16) & 0xFF;
    final g = (colorInt >> 8) & 0xFF;
    final b = colorInt & 0xFF;
    return '$r,$g,$b,$a';
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
      case '.gpkg':
        return 'GeoPackage (QGIS): $filename';
      default:
        return filename;
    }
  }
}
