import 'package:uuid/uuid.dart';

/// Represents a survey project in LVTField
class ProjectModel {
  final String id;
  final String name;
  final String description;
  final String crs;
  final String? sourceFile;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSynced;

  ProjectModel({
    String? id,
    required this.name,
    this.description = '',
    this.crs = 'EPSG:4326',
    this.sourceFile,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isSynced = false,
  })
      : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Create from database map
  factory ProjectModel.fromMap(Map<String, dynamic> map) {
    return ProjectModel(
      id: map['id'] as String,
      name: map['name'] as String,
      description: (map['description'] as String?) ?? '',
      crs: (map['crs'] as String?) ?? 'EPSG:4326',
      sourceFile: map['source_file'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      isSynced: (map['is_synced'] as int?) == 1,
    );
  }

  /// Convert to database map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'crs': crs,
      'source_file': sourceFile,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_synced': isSynced ? 1 : 0,
    };
  }

  /// Create a copy with modified fields
  ProjectModel copyWith({
    String? name,
    String? description,
    String? crs,
    String? sourceFile,
    DateTime? updatedAt,
    bool? isSynced,
  }) {
    return ProjectModel(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      crs: crs ?? this.crs,
      sourceFile: sourceFile ?? this.sourceFile,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      isSynced: isSynced ?? this.isSynced,
    );
  }

  @override
  String toString() => 'ProjectModel(id: $id, name: $name)';
}
