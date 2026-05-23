import '../database/app_database.dart';
import '../models/feature_model.dart';

/// Repository for CRUD operations on features
class FeatureRepository {
  /// Get all features for a layer
  Future<List<FeatureModel>> getByLayer(String layerId) async {
    final db = await AppDatabase.database;
    final maps = await db.query(
      'features',
      where: 'layer_id = ?',
      whereArgs: [layerId],
      orderBy: 'created_at DESC',
    );
    return maps.map((m) => FeatureModel.fromMap(m)).toList();
  }

  /// Get a feature by ID
  Future<FeatureModel?> getById(String id) async {
    final db = await AppDatabase.database;
    final maps = await db.query('features', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return FeatureModel.fromMap(maps.first);
  }

  /// Insert a new feature
  Future<void> insert(FeatureModel feature) async {
    final db = await AppDatabase.database;
    await db.insert('features', feature.toMap());
  }

  /// Insert multiple features in a single transaction (much faster for bulk imports)
  Future<void> insertBatch(List<FeatureModel> features) async {
    if (features.isEmpty) return;
    final db = await AppDatabase.database;
    final batch = db.batch();
    for (final feature in features) {
      batch.insert('features', feature.toMap());
    }
    await batch.commit(noResult: true);
  }

  /// Update a feature
  Future<void> update(FeatureModel feature) async {
    final db = await AppDatabase.database;
    await db.update(
      'features',
      feature.toMap(),
      where: 'id = ?',
      whereArgs: [feature.id],
    );
  }

  /// Delete a feature
  Future<void> delete(String id) async {
    final db = await AppDatabase.database;
    await db.delete('features', where: 'id = ?', whereArgs: [id]);
  }

  /// Get count of features in a layer
  Future<int> countByLayer(String layerId) async {
    final db = await AppDatabase.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM features WHERE layer_id = ?',
      [layerId],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  /// Get all unsynced features
  Future<List<FeatureModel>> getUnsynced() async {
    final db = await AppDatabase.database;
    final maps = await db.query(
      'features',
      where: 'is_synced = 0',
    );
    return maps.map((m) => FeatureModel.fromMap(m)).toList();
  }
}
