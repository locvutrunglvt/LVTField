import '../database/app_database.dart';
import '../models/project_model.dart';

/// Repository for CRUD operations on projects
class ProjectRepository {
  /// Get all projects ordered by most recent
  Future<List<ProjectModel>> getAll() async {
    final db = await AppDatabase.database;
    final maps = await db.query('projects', orderBy: 'updated_at DESC');
    return maps.map((m) => ProjectModel.fromMap(m)).toList();
  }

  /// Get a project by ID
  Future<ProjectModel?> getById(String id) async {
    final db = await AppDatabase.database;
    final maps = await db.query('projects', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return ProjectModel.fromMap(maps.first);
  }

  /// Insert a new project
  Future<void> insert(ProjectModel project) async {
    final db = await AppDatabase.database;
    await db.insert('projects', project.toMap());
  }

  /// Update an existing project
  Future<void> update(ProjectModel project) async {
    final db = await AppDatabase.database;
    await db.update(
      'projects',
      project.toMap(),
      where: 'id = ?',
      whereArgs: [project.id],
    );
  }

  /// Delete a project and all related data
  Future<void> delete(String id) async {
    final db = await AppDatabase.database;
    await db.delete('projects', where: 'id = ?', whereArgs: [id]);
  }

  /// Get number of features across all layers of a project
  Future<int> getFeatureCount(String projectId) async {
    final db = await AppDatabase.database;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count FROM features f
      INNER JOIN layers l ON f.layer_id = l.id
      WHERE l.project_id = ?
    ''', [projectId]);
    return (result.first['count'] as int?) ?? 0;
  }
}
