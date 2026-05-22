import 'dart:convert';
import 'package:uuid/uuid.dart';

/// Types of form fields for data entry
enum FormFieldType {
  text,
  textMultiline,
  number,
  numberAuto,
  dropdown,
  checkbox,
  date,
  photo,
}

/// Represents a form field definition for a layer
class FormFieldModel {
  final String id;
  final String layerId;
  final String fieldName;
  final String label;
  final FormFieldType fieldType;
  final String? defaultValue;
  final List<Map<String, String>>? options;
  final bool isRequired;
  final String? validationRule;
  final String? hint;
  final String? autoSource;
  final int sortOrder;

  FormFieldModel({
    String? id,
    required this.layerId,
    required this.fieldName,
    required this.label,
    this.fieldType = FormFieldType.text,
    this.defaultValue,
    this.options,
    this.isRequired = false,
    this.validationRule,
    this.hint,
    this.autoSource,
    this.sortOrder = 0,
  }) : id = id ?? const Uuid().v4();

  factory FormFieldModel.fromMap(Map<String, dynamic> map) {
    List<Map<String, String>>? opts;
    if (map['options_json'] != null) {
      final decoded = jsonDecode(map['options_json'] as String) as List;
      opts = decoded
          .map((e) => Map<String, String>.from(e as Map))
          .toList();
    }

    return FormFieldModel(
      id: map['id'] as String,
      layerId: map['layer_id'] as String,
      fieldName: map['field_name'] as String,
      label: map['label'] as String,
      fieldType: FormFieldType.values.firstWhere(
        (e) => e.name == (map['field_type'] as String),
        orElse: () => FormFieldType.text,
      ),
      defaultValue: map['default_value'] as String?,
      options: opts,
      isRequired: (map['is_required'] as int?) == 1,
      validationRule: map['validation_rule'] as String?,
      hint: map['hint'] as String?,
      autoSource: map['auto_source'] as String?,
      sortOrder: (map['sort_order'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'layer_id': layerId,
      'field_name': fieldName,
      'label': label,
      'field_type': fieldType.name,
      'default_value': defaultValue,
      'options_json': options != null ? jsonEncode(options) : null,
      'is_required': isRequired ? 1 : 0,
      'validation_rule': validationRule,
      'hint': hint,
      'auto_source': autoSource,
      'sort_order': sortOrder,
    };
  }

  /// Create from JSON form definition (from LVTFieldSync plugin)
  factory FormFieldModel.fromJson(Map<String, dynamic> json, String layerId) {
    FormFieldType type;
    switch (json['type'] as String? ?? 'text') {
      case 'text':
        type = FormFieldType.text;
        break;
      case 'text_multiline':
        type = FormFieldType.textMultiline;
        break;
      case 'number':
        type = FormFieldType.number;
        break;
      case 'number_auto':
        type = FormFieldType.numberAuto;
        break;
      case 'dropdown':
        type = FormFieldType.dropdown;
        break;
      case 'checkbox':
        type = FormFieldType.checkbox;
        break;
      case 'date':
        type = FormFieldType.date;
        break;
      case 'photo':
        type = FormFieldType.photo;
        break;
      default:
        type = FormFieldType.text;
    }

    List<Map<String, String>>? options;
    if (json['options'] != null) {
      options = (json['options'] as List)
          .map((o) => Map<String, String>.from(o as Map))
          .toList();
    }

    return FormFieldModel(
      layerId: layerId,
      fieldName: json['name'] as String,
      label: json['label'] as String? ?? json['name'] as String,
      fieldType: type,
      defaultValue: json['default_value']?.toString(),
      options: options,
      isRequired: json['required'] as bool? ?? false,
      validationRule: json['validation_rule'] as String?,
      hint: json['hint'] as String?,
      autoSource: json['auto_source'] as String?,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }

  @override
  String toString() => 'FormFieldModel($fieldName: ${fieldType.name})';
}
