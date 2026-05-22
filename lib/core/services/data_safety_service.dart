import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../../data/database/app_database.dart';

/// Service to ensure data safety, integrity, and backup
class DataSafetyService {
  /// Auto-backup database before critical operations
  /// Returns backup file path on success, null on failure
  static Future<String?> createBackup({String? label}) async {
    try {
      final dbPath = await getDatabasesPath();
      final sourcePath = p.join(dbPath, 'lvtfield.db');
      final sourceFile = File(sourcePath);

      if (!await sourceFile.exists()) {
        debugPrint('DataSafety: No database to backup');
        return null;
      }

      // Create backup directory
      final appDir = await getApplicationDocumentsDirectory();
      final backupDir = Directory(p.join(appDir.path, 'LVTField', 'backups'));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      // Generate backup filename with timestamp
      final timestamp = DateTime.now().toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final backupLabel = label ?? 'auto';
      final backupName = 'lvtfield_${backupLabel}_$timestamp.db';
      final backupPath = p.join(backupDir.path, backupName);

      // Copy database file
      await sourceFile.copy(backupPath);

      // Clean old backups (keep last 10)
      await _cleanOldBackups(backupDir, maxKeep: 10);

      debugPrint('DataSafety: Backup created at $backupPath');
      return backupPath;
    } catch (e) {
      debugPrint('DataSafety: Backup failed - $e');
      return null;
    }
  }

  /// Restore database from backup file
  static Future<bool> restoreFromBackup(String backupPath) async {
    try {
      final backupFile = File(backupPath);
      if (!await backupFile.exists()) {
        debugPrint('DataSafety: Backup file not found');
        return false;
      }

      // Close current database
      await AppDatabase.close();

      // Create a safety backup of current database before restore
      await createBackup(label: 'pre-restore');

      // Copy backup to database location
      final dbPath = await getDatabasesPath();
      final targetPath = p.join(dbPath, 'lvtfield.db');
      await backupFile.copy(targetPath);

      debugPrint('DataSafety: Database restored from $backupPath');
      return true;
    } catch (e) {
      debugPrint('DataSafety: Restore failed - $e');
      return false;
    }
  }

  /// List available backups
  static Future<List<BackupInfo>> listBackups() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final backupDir = Directory(p.join(appDir.path, 'LVTField', 'backups'));

      if (!await backupDir.exists()) return [];

      final files = await backupDir
          .list()
          .where((f) => f is File && f.path.endsWith('.db'))
          .cast<File>()
          .toList();

      final backups = <BackupInfo>[];
      for (final file in files) {
        final stat = await file.stat();
        backups.add(BackupInfo(
          path: file.path,
          name: p.basename(file.path),
          size: stat.size,
          createdAt: stat.modified,
        ));
      }

      // Sort by date, newest first
      backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return backups;
    } catch (e) {
      debugPrint('DataSafety: List backups failed - $e');
      return [];
    }
  }

  /// Verify database integrity
  static Future<bool> verifyDatabaseIntegrity() async {
    try {
      final db = await AppDatabase.database;
      final result = await db.rawQuery('PRAGMA integrity_check');
      final status = result.first.values.first as String;
      final isOk = status == 'ok';
      debugPrint('DataSafety: Integrity check - $status');
      return isOk;
    } catch (e) {
      debugPrint('DataSafety: Integrity check failed - $e');
      return false;
    }
  }

  /// Safe write operation with transaction and automatic backup
  /// Wraps the operation in a database transaction for atomicity
  static Future<T> safeWrite<T>(
    Future<T> Function(Transaction txn) operation, {
    bool autoBackup = false,
  }) async {
    if (autoBackup) {
      await createBackup(label: 'pre-write');
    }

    final db = await AppDatabase.database;
    return db.transaction((txn) async {
      return await operation(txn);
    });
  }

  /// Export project data as JSON for safe transfer
  static Future<String?> exportProjectAsJson(String projectId) async {
    try {
      final db = await AppDatabase.database;

      // Get project
      final projects = await db.query(
        'projects',
        where: 'id = ?',
        whereArgs: [projectId],
      );
      if (projects.isEmpty) return null;

      // Get layers
      final layers = await db.query(
        'layers',
        where: 'project_id = ?',
        whereArgs: [projectId],
      );

      // Get features for each layer
      final allFeatures = <Map<String, dynamic>>[];
      for (final layer in layers) {
        final features = await db.query(
          'features',
          where: 'layer_id = ?',
          whereArgs: [layer['id']],
        );
        allFeatures.addAll(features);
      }

      // Get form fields for each layer
      final allFormFields = <Map<String, dynamic>>[];
      for (final layer in layers) {
        final fields = await db.query(
          'form_fields',
          where: 'layer_id = ?',
          whereArgs: [layer['id']],
        );
        allFormFields.addAll(fields);
      }

      final exportData = {
        'app': 'LVTField',
        'version': '1.0.0',
        'exported_at': DateTime.now().toIso8601String(),
        'project': projects.first,
        'layers': layers,
        'features': allFeatures,
        'form_fields': allFormFields,
      };

      final appDir = await getApplicationDocumentsDirectory();
      final exportDir = Directory(p.join(appDir.path, 'LVTField', 'exports'));
      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }

      final fileName = 'project_${projectId.substring(0, 8)}_${DateTime.now().millisecondsSinceEpoch}.json';
      final filePath = p.join(exportDir.path, fileName);
      final file = File(filePath);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(exportData),
      );

      debugPrint('DataSafety: Project exported to $filePath');
      return filePath;
    } catch (e) {
      debugPrint('DataSafety: Export failed - $e');
      return null;
    }
  }

  /// Clean old backups, keeping only the most recent ones
  static Future<void> _cleanOldBackups(Directory dir, {int maxKeep = 10}) async {
    try {
      final files = await dir
          .list()
          .where((f) => f is File && f.path.endsWith('.db'))
          .cast<File>()
          .toList();

      if (files.length <= maxKeep) return;

      // Sort by modification time
      final fileStats = <File, DateTime>{};
      for (final file in files) {
        final stat = await file.stat();
        fileStats[file] = stat.modified;
      }

      files.sort((a, b) => fileStats[b]!.compareTo(fileStats[a]!));

      // Delete old ones
      for (int i = maxKeep; i < files.length; i++) {
        await files[i].delete();
        debugPrint('DataSafety: Deleted old backup ${files[i].path}');
      }
    } catch (e) {
      debugPrint('DataSafety: Clean backups failed - $e');
    }
  }
}

/// Information about a backup file
class BackupInfo {
  final String path;
  final String name;
  final int size;
  final DateTime createdAt;

  BackupInfo({
    required this.path,
    required this.name,
    required this.size,
    required this.createdAt,
  });

  /// Human-readable file size
  String get sizeText {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
