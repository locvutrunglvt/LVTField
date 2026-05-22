import '../database/app_database.dart';
import '../models/media_model.dart';

/// Repository for CRUD operations on media attachments
/// Author: Lộc Vũ Trung
class MediaRepository {
  /// Insert a new media record
  Future<void> insert(MediaModel media) async {
    final db = await AppDatabase.database;
    await db.insert('media', media.toMap());
  }

  /// Get all media for a specific feature
  Future<List<MediaModel>> getByFeatureId(String featureId) async {
    final db = await AppDatabase.database;
    final maps = await db.query(
      'media',
      where: 'feature_id = ?',
      whereArgs: [featureId],
      orderBy: 'captured_at DESC',
    );
    return maps.map((m) => MediaModel.fromMap(m)).toList();
  }

  /// Get a single media record by ID
  Future<MediaModel?> getById(String id) async {
    final db = await AppDatabase.database;
    final maps = await db.query('media', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return MediaModel.fromMap(maps.first);
  }

  /// Delete a media record by ID
  Future<void> delete(String mediaId) async {
    final db = await AppDatabase.database;
    await db.delete('media', where: 'id = ?', whereArgs: [mediaId]);
  }

  /// Get all media across an entire project
  /// Joins through features -> layers -> project to find all related media
  Future<List<MediaModel>> getByProjectId(String projectId) async {
    final db = await AppDatabase.database;
    final maps = await db.rawQuery('''
      SELECT m.*
      FROM media m
      INNER JOIN features f ON m.feature_id = f.id
      INNER JOIN layers l ON f.layer_id = l.id
      WHERE l.project_id = ?
      ORDER BY m.captured_at DESC
    ''', [projectId]);
    return maps.map((m) => MediaModel.fromMap(m)).toList();
  }

  /// Count media attachments for a specific feature
  Future<int> countByFeature(String featureId) async {
    final db = await AppDatabase.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM media WHERE feature_id = ?',
      [featureId],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  /// Delete all media records for a specific feature
  Future<void> deleteByFeatureId(String featureId) async {
    final db = await AppDatabase.database;
    await db.delete('media', where: 'feature_id = ?', whereArgs: [featureId]);
  }
}
