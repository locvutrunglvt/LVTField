import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../data/database/app_database.dart';
import '../../data/models/form_field_model.dart';

/// Service for managing dynamic form templates and validation.
///
/// Provides CRUD operations on [FormFieldModel] definitions stored
/// in the `form_fields` table, plus default field generation for
/// common forest-survey geometry types.
///
/// Author: Lộc Vũ Trung
class FormEngineService {
  // ─── Query ───────────────────────────────────────────────────────

  /// Get form fields for a layer, ordered by [sortOrder].
  Future<List<FormFieldModel>> getFieldsForLayer(String layerId) async {
    final db = await AppDatabase.database;
    final results = await db.query(
      'form_fields',
      where: 'layer_id = ?',
      whereArgs: [layerId],
      orderBy: 'sort_order ASC',
    );
    return results.map((m) => FormFieldModel.fromMap(m)).toList();
  }

  // ─── Persistence ─────────────────────────────────────────────────

  /// Upsert a single form field template.
  Future<void> saveField(FormFieldModel field) async {
    final db = await AppDatabase.database;
    await db.insert(
      'form_fields',
      field.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Save a batch of form fields inside a single transaction.
  Future<void> saveFields(List<FormFieldModel> fields) async {
    final db = await AppDatabase.database;
    await db.transaction((txn) async {
      for (final field in fields) {
        await txn.insert(
          'form_fields',
          field.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// Delete a form field by [fieldId].
  Future<void> deleteField(String fieldId) async {
    final db = await AppDatabase.database;
    await db.delete('form_fields', where: 'id = ?', whereArgs: [fieldId]);
  }

  /// Delete all form fields for a given [layerId].
  Future<void> deleteFieldsForLayer(String layerId) async {
    final db = await AppDatabase.database;
    await db.delete(
      'form_fields',
      where: 'layer_id = ?',
      whereArgs: [layerId],
    );
  }

  // ─── Default field generation ────────────────────────────────────

  /// Helper to build dropdown options as `[{value, label}]` maps
  /// matching the [FormFieldModel.options] signature.
  static List<Map<String, String>> _opts(List<String> labels) {
    return labels
        .map((l) => {'value': l, 'label': l})
        .toList(growable: false);
  }

  /// Create default forest-survey fields for [layerId] based on
  /// the given [geometryType] (`point`, `line`, or `polygon`).
  Future<void> createDefaultForestFields(
    String layerId,
    String geometryType,
  ) async {
    final uuid = const Uuid();
    final fields = <FormFieldModel>[];

    switch (geometryType) {
      case 'polygon':
        fields.addAll([
          FormFieldModel(
            id: uuid.v4(),
            layerId: layerId,
            fieldName: 'plot_code',
            label: 'Mã lô rừng',
            fieldType: FormFieldType.text,
            isRequired: true,
            hint: 'VD: LR-001',
            sortOrder: 0,
          ),
          FormFieldModel(
            id: uuid.v4(),
            layerId: layerId,
            fieldName: 'forest_type',
            label: 'Loại rừng',
            fieldType: FormFieldType.dropdown,
            options: _opts([
              'Rừng tự nhiên',
              'Rừng trồng',
              'Rừng ngập mặn',
              'Rừng hỗn giao',
              'Rừng tre nứa',
            ]),
            isRequired: true,
            sortOrder: 1,
          ),
          FormFieldModel(
            id: uuid.v4(),
            layerId: layerId,
            fieldName: 'forest_status',
            label: 'Trạng thái rừng',
            fieldType: FormFieldType.dropdown,
            options: _opts([
              'Rừng giàu',
              'Rừng trung bình',
              'Rừng nghèo',
              'Rừng phục hồi',
              'Chưa có rừng',
            ]),
            isRequired: true,
            sortOrder: 2,
          ),
          FormFieldModel(
            id: uuid.v4(),
            layerId: layerId,
            fieldName: 'area',
            label: 'Diện tích (ha)',
            fieldType: FormFieldType.number,
            hint: 'Tự động tính nếu có polygon',
            sortOrder: 3,
          ),
          FormFieldModel(
            id: uuid.v4(),
            layerId: layerId,
            fieldName: 'notes',
            label: 'Ghi chú',
            fieldType: FormFieldType.textMultiline,
            sortOrder: 4,
          ),
        ]);
        break;

      case 'point':
        fields.addAll([
          FormFieldModel(
            id: uuid.v4(),
            layerId: layerId,
            fieldName: 'tree_code',
            label: 'Mã cây',
            fieldType: FormFieldType.text,
            isRequired: true,
            hint: 'VD: C-001',
            sortOrder: 0,
          ),
          FormFieldModel(
            id: uuid.v4(),
            layerId: layerId,
            fieldName: 'species',
            label: 'Loài cây',
            fieldType: FormFieldType.text,
            isRequired: true,
            hint: 'Tên loài cây',
            sortOrder: 1,
          ),
          FormFieldModel(
            id: uuid.v4(),
            layerId: layerId,
            fieldName: 'diameter',
            label: 'Đường kính D1.3 (cm)',
            fieldType: FormFieldType.number,
            isRequired: true,
            sortOrder: 2,
          ),
          FormFieldModel(
            id: uuid.v4(),
            layerId: layerId,
            fieldName: 'height',
            label: 'Chiều cao (m)',
            fieldType: FormFieldType.number,
            sortOrder: 3,
          ),
          FormFieldModel(
            id: uuid.v4(),
            layerId: layerId,
            fieldName: 'health',
            label: 'Tình trạng',
            fieldType: FormFieldType.dropdown,
            options: _opts([
              'Tốt',
              'Trung bình',
              'Xấu',
              'Chết đứng',
            ]),
            sortOrder: 4,
          ),
          FormFieldModel(
            id: uuid.v4(),
            layerId: layerId,
            fieldName: 'notes',
            label: 'Ghi chú',
            fieldType: FormFieldType.textMultiline,
            sortOrder: 5,
          ),
        ]);
        break;

      default:
        // line geometry
        fields.addAll([
          FormFieldModel(
            id: uuid.v4(),
            layerId: layerId,
            fieldName: 'line_code',
            label: 'Mã tuyến',
            fieldType: FormFieldType.text,
            isRequired: true,
            hint: 'VD: T-001',
            sortOrder: 0,
          ),
          FormFieldModel(
            id: uuid.v4(),
            layerId: layerId,
            fieldName: 'line_type',
            label: 'Loại tuyến',
            fieldType: FormFieldType.dropdown,
            options: _opts([
              'Tuyến khảo sát',
              'Đường mòn',
              'Suối',
              'Ranh giới',
              'Đường vận chuyển',
            ]),
            isRequired: true,
            sortOrder: 1,
          ),
          FormFieldModel(
            id: uuid.v4(),
            layerId: layerId,
            fieldName: 'notes',
            label: 'Ghi chú',
            fieldType: FormFieldType.textMultiline,
            sortOrder: 2,
          ),
        ]);
    }

    await saveFields(fields);
  }

  // ─── Validation ──────────────────────────────────────────────────

  /// Validate [data] against a list of [fields].
  ///
  /// Returns a map of `{fieldName: errorMessage}` for every failing
  /// field. An empty map means all validations passed.
  Map<String, String> validate(
    List<FormFieldModel> fields,
    Map<String, dynamic> data,
  ) {
    final errors = <String, String>{};

    for (final field in fields) {
      final value = data[field.fieldName];

      // Required-field check
      if (field.isRequired &&
          (value == null || value.toString().trim().isEmpty)) {
        errors[field.fieldName] = '${field.label} là trường bắt buộc';
        continue;
      }

      // Number type check (skip empty optional fields)
      if (value != null &&
          value.toString().trim().isNotEmpty &&
          (field.fieldType == FormFieldType.number ||
              field.fieldType == FormFieldType.numberAuto)) {
        if (double.tryParse(value.toString()) == null) {
          errors[field.fieldName] = '${field.label} phải là số';
        }
      }
    }

    return errors;
  }
}
