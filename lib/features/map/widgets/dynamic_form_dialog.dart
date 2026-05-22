import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/form_field_model.dart';

/// A beautiful dynamic form dialog that renders form fields based on
/// FormFieldModel definitions. Supports text, number, dropdown, checkbox,
/// date, multiline text, and photo fields.
///
/// Author: Loc Vu Trung
class DynamicFormDialog extends StatefulWidget {
  final String title;
  final List<FormFieldModel> formFields;
  final Map<String, dynamic> initialValues;
  final bool allowAddCustom;

  const DynamicFormDialog({
    super.key,
    required this.title,
    required this.formFields,
    this.initialValues = const {},
    this.allowAddCustom = false,
  });

  @override
  State<DynamicFormDialog> createState() => _DynamicFormDialogState();

  /// Show the dialog and return the filled values
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required String title,
    required List<FormFieldModel> formFields,
    Map<String, dynamic> initialValues = const {},
    bool allowAddCustom = false,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DynamicFormDialog(
        title: title,
        formFields: formFields,
        initialValues: initialValues,
        allowAddCustom: allowAddCustom,
      ),
    );
  }
}

class _DynamicFormDialogState extends State<DynamicFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late Map<String, dynamic> _values;
  final _customKeyCtrl = TextEditingController();
  final _customValCtrl = TextEditingController();
  final List<MapEntry<String, TextEditingController>> _customFields = [];

  @override
  void initState() {
    super.initState();
    _values = Map<String, dynamic>.from(widget.initialValues);
    // Initialize defaults for fields not in initialValues
    for (final field in widget.formFields) {
      if (!_values.containsKey(field.fieldName)) {
        if (field.defaultValue != null) {
          _values[field.fieldName] = field.defaultValue;
        } else if (field.fieldType == FormFieldType.checkbox) {
          _values[field.fieldName] = false;
        }
      }
    }
  }

  @override
  void dispose() {
    _customKeyCtrl.dispose();
    _customValCtrl.dispose();
    for (final f in _customFields) {
      f.value.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
          maxWidth: 500,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit_note, color: Colors.white, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                    onPressed: () => Navigator.pop(context, null),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Form body
            Flexible(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shrinkWrap: true,
                  children: [
                    // Dynamic fields
                    ...widget.formFields.map(_buildField),

                    // Custom fields (from initial attributes not in form definition)
                    ..._buildUnmappedFields(),

                    // Add custom field section
                    if (widget.allowAddCustom) ...[
                      const Divider(height: 32),
                      _buildAddCustomField(),
                    ],
                  ],
                ),
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, null),
                    child: const Text('Hủy'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Lưu'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(FormFieldModel field) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label
          Row(
            children: [
              Icon(_fieldIcon(field.fieldType), size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                field.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              if (field.isRequired) ...[
                const SizedBox(width: 4),
                const Text('*', style: TextStyle(color: AppColors.error, fontSize: 13)),
              ],
            ],
          ),
          const SizedBox(height: 6),
          // Input widget
          _buildInputWidget(field),
        ],
      ),
    );
  }

  Widget _buildInputWidget(FormFieldModel field) {
    switch (field.fieldType) {
      case FormFieldType.text:
        return _buildTextField(field, maxLines: 1);

      case FormFieldType.textMultiline:
        return _buildTextField(field, maxLines: 4);

      case FormFieldType.number:
      case FormFieldType.numberAuto:
        return _buildNumberField(field);

      case FormFieldType.dropdown:
        return _buildDropdownField(field);

      case FormFieldType.checkbox:
        return _buildCheckboxField(field);

      case FormFieldType.date:
        return _buildDateField(field);

      case FormFieldType.photo:
        return _buildPhotoPlaceholder(field);
    }
  }

  Widget _buildTextField(FormFieldModel field, {int maxLines = 1}) {
    return TextFormField(
      initialValue: _values[field.fieldName]?.toString() ?? field.defaultValue ?? '',
      maxLines: maxLines,
      decoration: _inputDecoration(field.hint ?? 'Nhập ${field.label}'),
      style: const TextStyle(fontSize: 14),
      validator: field.isRequired
          ? (v) => (v == null || v.isEmpty) ? '${field.label} là bắt buộc' : null
          : null,
      onChanged: (v) => _values[field.fieldName] = v,
    );
  }

  Widget _buildNumberField(FormFieldModel field) {
    return TextFormField(
      initialValue: _values[field.fieldName]?.toString() ?? field.defaultValue ?? '',
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      decoration: _inputDecoration(field.hint ?? 'Nhập số'),
      style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
      validator: (v) {
        if (field.isRequired && (v == null || v.isEmpty)) {
          return '${field.label} là bắt buộc';
        }
        if (v != null && v.isNotEmpty && num.tryParse(v) == null) {
          return 'Giá trị không hợp lệ';
        }
        return null;
      },
      onChanged: (v) {
        final numVal = num.tryParse(v);
        _values[field.fieldName] = numVal ?? v;
      },
    );
  }

  Widget _buildDropdownField(FormFieldModel field) {
    final currentValue = _values[field.fieldName]?.toString();
    final options = field.options ?? [];

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
        color: Colors.white,
      ),
      child: DropdownButtonFormField<String>(
        value: options.any((o) => o['value'] == currentValue) ? currentValue : null,
        isExpanded: true,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          border: InputBorder.none,
        ),
        hint: Text(
          field.hint ?? 'Chọn ${field.label}',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
        ),
        style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
        items: options.map((opt) {
          return DropdownMenuItem<String>(
            value: opt['value'],
            child: Text(opt['label'] ?? opt['value'] ?? ''),
          );
        }).toList(),
        onChanged: (v) => setState(() => _values[field.fieldName] = v),
        validator: field.isRequired
            ? (v) => (v == null || v.isEmpty) ? '${field.label} là bắt buộc' : null
            : null,
      ),
    );
  }

  Widget _buildCheckboxField(FormFieldModel field) {
    final checked = _values[field.fieldName] == true ||
        _values[field.fieldName] == 1 ||
        _values[field.fieldName] == '1';

    return InkWell(
      onTap: () => setState(() => _values[field.fieldName] = !checked),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: checked ? AppColors.primary : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(10),
          color: checked ? AppColors.primarySurface : Colors.white,
        ),
        child: Row(
          children: [
            Icon(
              checked ? Icons.check_box : Icons.check_box_outline_blank,
              color: checked ? AppColors.primary : AppColors.textSecondary,
              size: 22,
            ),
            const SizedBox(width: 10),
            Text(
              checked ? 'Có' : 'Không',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: checked ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateField(FormFieldModel field) {
    final currentVal = _values[field.fieldName]?.toString() ?? '';
    final dateFormat = DateFormat('dd/MM/yyyy');

    return InkWell(
      onTap: () async {
        DateTime initialDate;
        try {
          initialDate = dateFormat.parse(currentVal);
        } catch (_) {
          initialDate = DateTime.now();
        }

        final picked = await showDatePicker(
          context: context,
          initialDate: initialDate,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) {
          setState(() => _values[field.fieldName] = dateFormat.format(picked));
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
          color: Colors.white,
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Text(
              currentVal.isEmpty ? 'Chọn ngày' : currentVal,
              style: TextStyle(
                fontSize: 14,
                color: currentVal.isEmpty ? Colors.grey.shade400 : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoPlaceholder(FormFieldModel field) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border, style: BorderStyle.solid),
        borderRadius: BorderRadius.circular(10),
        color: Colors.grey.shade50,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.camera_alt, size: 28, color: Colors.grey.shade400),
            const SizedBox(height: 4),
            Text('Chụp ảnh', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          ],
        ),
      ),
    );
  }

  /// Build fields for attributes that exist in initialValues but NOT in formFields
  List<Widget> _buildUnmappedFields() {
    final mappedNames = widget.formFields.map((f) => f.fieldName).toSet();
    final unmapped = widget.initialValues.entries
        .where((e) => !mappedNames.contains(e.key))
        .toList();

    if (unmapped.isEmpty && _customFields.isEmpty) return [];

    return [
      if (unmapped.isNotEmpty || _customFields.isNotEmpty) ...[
        const Divider(height: 24),
        const Text(
          'Thuộc tính khác',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
      ],
      ...unmapped.map((e) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            SizedBox(
              width: 100,
              child: Text(e.key,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                initialValue: e.value?.toString() ?? '',
                decoration: _inputDecoration(null),
                style: const TextStyle(fontSize: 13),
                onChanged: (v) => _values[e.key] = v,
              ),
            ),
          ],
        ),
      )),
      ..._customFields.asMap().entries.map((entry) {
        final i = entry.key;
        final kv = entry.value;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(
                width: 100,
                child: Text(kv.key,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: kv.value,
                  decoration: _inputDecoration(null),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline,
                    size: 16, color: AppColors.error),
                onPressed: () => setState(() {
                  _customFields[i].value.dispose();
                  _customFields.removeAt(i);
                }),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        );
      }),
    ];
  }

  Widget _buildAddCustomField() {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: TextField(
            controller: _customKeyCtrl,
            decoration: _inputDecoration('Tên trường'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: TextField(
            controller: _customValCtrl,
            decoration: _inputDecoration('Giá trị'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle, color: AppColors.primary, size: 22),
          onPressed: () {
            final key = _customKeyCtrl.text.trim();
            if (key.isNotEmpty) {
              setState(() {
                _customFields.add(MapEntry(
                  key,
                  TextEditingController(text: _customValCtrl.text.trim()),
                ));
                _customKeyCtrl.clear();
                _customValCtrl.clear();
              });
            }
          },
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String? hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      filled: true,
      fillColor: Colors.white,
    );
  }

  IconData _fieldIcon(FormFieldType type) {
    switch (type) {
      case FormFieldType.text:
        return Icons.text_fields;
      case FormFieldType.textMultiline:
        return Icons.notes;
      case FormFieldType.number:
      case FormFieldType.numberAuto:
        return Icons.tag;
      case FormFieldType.dropdown:
        return Icons.arrow_drop_down_circle_outlined;
      case FormFieldType.checkbox:
        return Icons.check_box_outlined;
      case FormFieldType.date:
        return Icons.calendar_today;
      case FormFieldType.photo:
        return Icons.camera_alt;
    }
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      // Add custom fields
      for (final entry in _customFields) {
        _values[entry.key] = entry.value.text;
      }
      // Clean up empty values
      _values.removeWhere((_, v) => v == null || v.toString().isEmpty);
      Navigator.pop(context, _values);
    }
  }
}
