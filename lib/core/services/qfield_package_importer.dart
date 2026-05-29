// QField package importer for LVTField
// Imports .qgs project files with associated GPKG data layers
// Author: Lộc Vũ Trung

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../data/database/app_database.dart';
import 'qgs_project_reader.dart';
import 'import_service.dart';

/// Result of importing a QField package
class QFieldImportResult {
  final bool success;
  final String? projectId;
  final int layerCount;
  final int featureCount;
  final String? errorMessage;
  final List<String> importedLayers;

  QFieldImportResult({
    required this.success,
    this.projectId,
    this.layerCount = 0,
    this.featureCount = 0,
    this.errorMessage,
    this.importedLayers = const [],
  });
}

/// Imports QField packages (.qgs + .gpkg files) into LVTField
class QFieldPackageImporter {
  final ImportService _importService = ImportService();
  final QgsProjectReader _reader = QgsProjectReader();

  /// Import a .qgs project file and all associated GPKG layers
  Future<QFieldImportResult> importPackage(
    String qgsFilePath,
    String projectId,
  ) async {
    try {
      debugPrint('QFieldPackageImporter: Starting import from $qgsFilePath');

      // 1. Parse .qgs project
      final qgsProject = await _reader.parse(qgsFilePath);

      if (qgsProject.layers.isEmpty) {
        return QFieldImportResult(
          success: false,
          errorMessage: 'Không tìm thấy layer vector nào trong dự án QGIS',
        );
      }

      final qgsDir = p.dirname(qgsFilePath);
      int totalFeatures = 0;
      final importedLayerNames = <String>[];
      final processedGpkg = <String>{}; // Avoid importing same GPKG twice

      // Collect layer configs per GPKG for style application after import
      final gpkgLayerConfigs = <String, List<QgsLayerConfig>>{};

      // 2. For each layer, find and import the GPKG
      for (final layerConfig in qgsProject.layers) {
        try {
          final gpkgRelPath = layerConfig.gpkgPath;
          if (gpkgRelPath == null) {
            debugPrint('QFieldPackageImporter: Layer "${layerConfig.name}" has no GPKG source, skipping');
            continue;
          }

          // Resolve relative path to absolute
          String gpkgAbsPath;
          if (p.isAbsolute(gpkgRelPath)) {
            gpkgAbsPath = gpkgRelPath;
          } else {
            gpkgAbsPath = p.normalize(p.join(qgsDir, gpkgRelPath));
          }

          // Check if file exists
          if (!await File(gpkgAbsPath).exists()) {
            debugPrint('QFieldPackageImporter: GPKG not found: $gpkgAbsPath');
            continue;
          }

          // Track layer configs for this GPKG
          gpkgLayerConfigs.putIfAbsent(gpkgAbsPath, () => []);
          gpkgLayerConfigs[gpkgAbsPath]!.add(layerConfig);

          // Skip if already imported this GPKG file
          if (processedGpkg.contains(gpkgAbsPath)) {
            debugPrint('QFieldPackageImporter: Already imported $gpkgAbsPath, skipping');
            continue;
          }
          processedGpkg.add(gpkgAbsPath);

          debugPrint('QFieldPackageImporter: Importing GPKG: $gpkgAbsPath for layer "${layerConfig.name}"');

          // 3. Import GPKG using existing import service
          final result = await _importService.importGpkg(gpkgAbsPath, projectId);

          if (result.success) {
            totalFeatures += result.featureCount;
            // Add all layer names from this GPKG's configs
            for (final config in gpkgLayerConfigs[gpkgAbsPath]!) {
              importedLayerNames.add(config.name);
            }
          } else {
            debugPrint('QFieldPackageImporter: Failed to import GPKG for "${layerConfig.name}": ${result.errorMessage}');
          }
        } catch (e) {
          debugPrint('QFieldPackageImporter: Error processing layer "${layerConfig.name}": $e');
        }
      }

      // 4. Apply .qgs styles to imported layers by matching table/layer names
      await _applyQgsStyles(projectId, qgsProject.layers);

      if (importedLayerNames.isEmpty) {
        return QFieldImportResult(
          success: false,
          errorMessage: 'Không import được layer nào. Kiểm tra file GPKG có tồn tại không.',
        );
      }

      debugPrint('QFieldPackageImporter: Imported ${importedLayerNames.length} layers, $totalFeatures features');

      return QFieldImportResult(
        success: true,
        projectId: projectId,
        layerCount: importedLayerNames.length,
        featureCount: totalFeatures,
        importedLayers: importedLayerNames,
      );
    } catch (e) {
      debugPrint('QFieldPackageImporter: Import failed: $e');
      return QFieldImportResult(
        success: false,
        errorMessage: 'Lỗi import dự án QGIS: $e',
      );
    }
  }

  /// Apply styles from .qgs layer configs to imported layers
  /// Matches by layer name or table name since importGpkg doesn't return per-layer IDs
  Future<void> _applyQgsStyles(String projectId, List<QgsLayerConfig> layerConfigs) async {
    try {
      final appDb = await AppDatabase.database;

      // Get all layers in this project
      final dbLayers = await appDb.query(
        'layers',
        columns: ['id', 'name', 'style_json'],
        where: 'project_id = ?',
        whereArgs: [projectId],
      );

      if (dbLayers.isEmpty) return;

      for (final layerConfig in layerConfigs) {
        if (layerConfig.parsedStyle.isEmpty) continue;

        // Match by layer name or table name
        final matchName = layerConfig.name.toLowerCase();
        final matchTable = layerConfig.tableName?.toLowerCase();

        for (final dbLayer in dbLayers) {
          final dbName = (dbLayer['name'] as String? ?? '').toLowerCase();

          if (dbName == matchName || (matchTable != null && dbName == matchTable)) {
            final layerId = dbLayer['id'] as String;
            await _applyStyleToLayer(appDb, layerId, layerConfig.parsedStyle);
            debugPrint('QFieldPackageImporter: Applied .qgs style to layer "$dbName" (id=$layerId)');
            break; // Found match, move to next config
          }
        }
      }
    } catch (e) {
      debugPrint('QFieldPackageImporter: Failed to apply styles: $e');
    }
  }

  /// Apply style map to a single layer, merging with existing style
  Future<void> _applyStyleToLayer(
    dynamic appDb,
    String layerId,
    Map<String, dynamic> qgsStyle,
  ) async {
    try {
      final rows = await appDb.query(
        'layers',
        columns: ['style_json'],
        where: 'id = ?',
        whereArgs: [layerId],
      );

      if (rows.isEmpty) return;

      final currentStyleJson = rows.first['style_json'] as String?;
      Map<String, dynamic> currentStyle;
      if (currentStyleJson != null && currentStyleJson.isNotEmpty) {
        currentStyle = Map<String, dynamic>.from(
            jsonDecode(currentStyleJson) as Map);
      } else {
        currentStyle = <String, dynamic>{};
      }

      // Merge: .qgs style overrides existing style
      currentStyle.addAll(qgsStyle);

      // Save back
      await appDb.update(
        'layers',
        {'style_json': jsonEncode(currentStyle)},
        where: 'id = ?',
        whereArgs: [layerId],
      );
    } catch (e) {
      debugPrint('QFieldPackageImporter: Failed to apply style to layer $layerId: $e');
    }
  }
}
