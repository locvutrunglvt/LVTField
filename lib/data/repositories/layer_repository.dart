import '../database/app_database.dart';
import '../models/layer_model.dart';

/// Repository for CRUD operations on layers
class LayerRepository {
  /// Get all layers for a project
  Future<List<LayerModel>> getByProject(String projectId) async {
    final db = await AppDatabase.database;
    final maps = await db.query(
      'layers',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'z_order ASC',
    );
    return maps.map((m) => LayerModel.fromMap(m)).toList();
  }

  /// Get a layer by ID
  Future<LayerModel?> getById(String id) async {
    final db = await AppDatabase.database;
    final maps = await db.query('layers', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return LayerModel.fromMap(maps.first);
  }

  /// Insert a new layer
  Future<void> insert(LayerModel layer) async {
    final db = await AppDatabase.database;
    await db.insert('layers', layer.toMap());
  }

  /// Update a layer
  Future<void> update(LayerModel layer) async {
    final db = await AppDatabase.database;
    await db.update(
      'layers',
      layer.toMap(),
      where: 'id = ?',
      whereArgs: [layer.id],
    );
  }

  /// Delete a layer
  Future<void> delete(String id) async {
    final db = await AppDatabase.database;
    await db.delete('layers', where: 'id = ?', whereArgs: [id]);
  }

  /// Toggle layer visibility
  Future<void> toggleVisibility(String id, bool isVisible) async {
    final db = await AppDatabase.database;
    await db.update(
      'layers',
      {'is_visible': isVisible ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
