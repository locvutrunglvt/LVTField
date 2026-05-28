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

  // ─── Field Name Validation (Static) ─────────────────────────────

  /// Valid field name: 1-8 chars, only [a-zA-Z0-9_]
  static final _validNameRegex = RegExp(r'^[a-zA-Z0-9_]{1,8}$');

  /// Vietnamese diacritics removal map
  static const _diacriticsMap = {
    'à': 'a', 'á': 'a', 'ả': 'a', 'ã': 'a', 'ạ': 'a',
    'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ẳ': 'a', 'ẵ': 'a', 'ặ': 'a',
    'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ẩ': 'a', 'ẫ': 'a', 'ậ': 'a',
    'đ': 'd',
    'è': 'e', 'é': 'e', 'ẻ': 'e', 'ẽ': 'e', 'ẹ': 'e',
    'ê': 'e', 'ề': 'e', 'ế': 'e', 'ể': 'e', 'ễ': 'e', 'ệ': 'e',
    'ì': 'i', 'í': 'i', 'ỉ': 'i', 'ĩ': 'i', 'ị': 'i',
    'ò': 'o', 'ó': 'o', 'ỏ': 'o', 'õ': 'o', 'ọ': 'o',
    'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ổ': 'o', 'ỗ': 'o', 'ộ': 'o',
    'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ở': 'o', 'ỡ': 'o', 'ợ': 'o',
    'ù': 'u', 'ú': 'u', 'ủ': 'u', 'ũ': 'u', 'ụ': 'u',
    'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ử': 'u', 'ữ': 'u', 'ự': 'u',
    'ỳ': 'y', 'ý': 'y', 'ỷ': 'y', 'ỹ': 'y', 'ỵ': 'y',
    'À': 'A', 'Á': 'A', 'Ả': 'A', 'Ã': 'A', 'Ạ': 'A',
    'Ă': 'A', 'Ằ': 'A', 'Ắ': 'A', 'Ẳ': 'A', 'Ẵ': 'A', 'Ặ': 'A',
    'Â': 'A', 'Ầ': 'A', 'Ấ': 'A', 'Ẩ': 'A', 'Ẫ': 'A', 'Ậ': 'A',
    'Đ': 'D',
    'È': 'E', 'É': 'E', 'Ẻ': 'E', 'Ẽ': 'E', 'Ẹ': 'E',
    'Ê': 'E', 'Ề': 'E', 'Ế': 'E', 'Ể': 'E', 'Ễ': 'E', 'Ệ': 'E',
    'Ì': 'I', 'Í': 'I', 'Ỉ': 'I', 'Ĩ': 'I', 'Ị': 'I',
    'Ò': 'O', 'Ó': 'O', 'Ỏ': 'O', 'Õ': 'O', 'Ọ': 'O',
    'Ô': 'O', 'Ồ': 'O', 'Ố': 'O', 'Ổ': 'O', 'Ỗ': 'O', 'Ộ': 'O',
    'Ơ': 'O', 'Ờ': 'O', 'Ớ': 'O', 'Ở': 'O', 'Ỡ': 'O', 'Ợ': 'O',
    'Ù': 'U', 'Ú': 'U', 'Ủ': 'U', 'Ũ': 'U', 'Ụ': 'U',
    'Ư': 'U', 'Ừ': 'U', 'Ứ': 'U', 'Ử': 'U', 'Ữ': 'U', 'Ự': 'U',
    'Ỳ': 'Y', 'Ý': 'Y', 'Ỷ': 'Y', 'Ỹ': 'Y', 'Ỵ': 'Y',
  };

  /// Check if a field name is valid: 1-8 chars, [a-zA-Z0-9_]
  static bool isValidFieldName(String name) => _validNameRegex.hasMatch(name);

  /// Sanitize a raw string into a valid field name (max 8 chars).
  /// - Removes Vietnamese diacritics
  /// - Replaces spaces with underscore
  /// - Strips invalid characters
  /// - Truncates to 8 chars
  /// - If empty → returns 'field_01' etc.
  static String sanitizeFieldName(String raw, {int maxLen = 8}) {
    // Step 1: Remove diacritics
    final buf = StringBuffer();
    for (final ch in raw.runes) {
      final c = String.fromCharCode(ch);
      buf.write(_diacriticsMap[c] ?? c);
    }
    var s = buf.toString();

    // Step 2: Replace spaces with underscore
    s = s.replaceAll(' ', '_');

    // Step 3: Keep only valid chars
    s = s.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');

    // Step 4: Truncate
    if (s.length > maxLen) s = s.substring(0, maxLen);

    // Step 5: Fallback
    if (s.isEmpty) s = 'field_01';

    return s;
  }

  /// Make a unique field name by appending _1, _2... if needed.
  /// Keeps result within maxLen chars.
  static String makeUniqueFieldName(String name, List<String> existing, {int maxLen = 8}) {
    if (!existing.contains(name)) return name;
    for (int i = 1; i <= 99; i++) {
      final suffix = '_$i';
      final maxBase = maxLen - suffix.length;
      final base = name.length > maxBase ? name.substring(0, maxBase) : name;
      final candidate = '$base$suffix';
      if (!existing.contains(candidate)) return candidate;
    }
    return name; // fallback
  }

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
