import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/form_field_model.dart';

/// Compact dynamic form dialog — minimal, space-efficient attribute editor.
/// Supports "pin" mode: pinned fields remember their value for the next entry.
///
/// Author: Loc Vu Trung
class DynamicFormDialog extends StatefulWidget {
  final String title;
  final List<FormFieldModel> formFields;
  final Map<String, dynamic> initialValues;
  final bool allowAddCustom;

  /// Set of field names that are currently pinned (sticky values).
  final Set<String> pinnedFieldNames;

  const DynamicFormDialog({
    super.key,
    required this.title,
    required this.formFields,
    this.initialValues = const {},
    this.allowAddCustom = false,
    this.pinnedFieldNames = const {},
  });

  @override
  State<DynamicFormDialog> createState() => _DynamicFormDialogState();

  /// Show the dialog and return a result map with keys:
  /// - `values`: Map<String, dynamic> — field values
  /// - `pinned`: Set<String> — field names that are pinned
  /// Returns null if cancelled.
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required String title,
    required List<FormFieldModel> formFields,
    Map<String, dynamic> initialValues = const {},
    bool allowAddCustom = false,
    Set<String> pinnedFieldNames = const {},
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DynamicFormDialog(
        title: title,
        formFields: formFields,
        initialValues: initialValues,
        allowAddCustom: allowAddCustom,
        pinnedFieldNames: pinnedFieldNames,
      ),
    );
  }
}

class _DynamicFormDialogState extends State<DynamicFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late Map<String, dynamic> _values;
  late Set<String> _pinned;
  final _customKeyCtrl = TextEditingController();
  final _customValCtrl = TextEditingController();
  final List<MapEntry<String, TextEditingController>> _customFields = [];

  @override
  void initState() {
    super.initState();
    _values = Map<String, dynamic>.from(widget.initialValues);
    _pinned = Set<String>.from(widget.pinnedFieldNames);
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.70,
          maxWidth: MediaQuery.of(context).size.width,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Compact header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: AppColors.primary,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context, null),
                    child: const Icon(Icons.close, color: Colors.white70, size: 18),
                  ),
                ],
              ),
            ),

            // Form body
            Flexible(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  shrinkWrap: true,
                  children: [
                    ...widget.formFields.map(_buildField),
                    ..._buildUnmappedFields(),
                    if (widget.allowAddCustom) ...[
                      const Divider(height: 16),
                      _buildAddCustomField(),
                    ],
                  ],
                ),
              ),
            ),

            // Compact actions
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, null),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        side: BorderSide(color: AppColors.borderOf(context)),
                      ),
                      child: const Text('Hủy', style: TextStyle(fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Lưu', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
    // Checkbox is inline — no separate label row
    if (field.fieldType == FormFieldType.checkbox) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(child: _buildCheckboxField(field)),
            _buildPinButton(field.fieldName),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label row with pin button
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      field.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    if (field.isRequired) ...[
                      const SizedBox(width: 3),
                      const Text('*', style: TextStyle(color: AppColors.error, fontSize: 13)),
                    ],
                  ],
                ),
              ),
              _buildPinButton(field.fieldName),
            ],
          ),
          const SizedBox(height: 4),
          _buildInputWidget(field),
        ],
      ),
    );
  }

  /// Small pin/pushpin toggle button
  Widget _buildPinButton(String fieldName) {
    final isPinned = _pinned.contains(fieldName);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isPinned) {
            _pinned.remove(fieldName);
          } else {
            _pinned.add(fieldName);
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Icon(
          isPinned ? Icons.push_pin : Icons.push_pin_outlined,
          size: 16,
          color: isPinned ? AppColors.primary : AppColors.textSecondaryOf(context).withValues(alpha: 0.4),
        ),
      ),
    );
  }

  Widget _buildInputWidget(FormFieldModel field) {
    switch (field.fieldType) {
      case FormFieldType.text:
        return _buildTextField(field, maxLines: 1);
      case FormFieldType.textMultiline:
        return _buildTextField(field, maxLines: 3);
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
      decoration: _inputDecoration(null, field.hint ?? 'Nhập ${field.label}', false),
      style: const TextStyle(fontSize: 13),
      validator: field.isRequired
          ? (v) => (v == null || v.isEmpty) ? 'Bắt buộc' : null
          : null,
      onChanged: (v) => _values[field.fieldName] = v,
    );
  }

  Widget _buildNumberField(FormFieldModel field) {
    return TextFormField(
      initialValue: _values[field.fieldName]?.toString() ?? field.defaultValue ?? '',
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      decoration: _inputDecoration(null, field.hint ?? 'Nhập số', false),
      style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
      validator: (v) {
        if (field.isRequired && (v == null || v.isEmpty)) return 'Bắt buộc';
        if (v != null && v.isNotEmpty && num.tryParse(v) == null) return 'Số không hợp lệ';
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

    return DropdownButtonFormField<String>(
      value: options.any((o) => o['value'] == currentValue) ? currentValue : null,
      isExpanded: true,
      decoration: _inputDecoration(field.label, null, field.isRequired),
      hint: Text(field.hint ?? 'Chọn', style: TextStyle(fontSize: 13, color: AppColors.textSecondaryOf(context))),
      style: TextStyle(fontSize: 13, color: AppColors.textPrimaryOf(context)),
      items: options.map((opt) {
        return DropdownMenuItem<String>(
          value: opt['value'],
          child: Text(opt['label'] ?? opt['value'] ?? '', style: const TextStyle(fontSize: 13)),
        );
      }).toList(),
      onChanged: (v) => setState(() => _values[field.fieldName] = v),
      validator: field.isRequired
          ? (v) => (v == null || v.isEmpty) ? 'Bắt buộc' : null
          : null,
    );
  }

  Widget _buildCheckboxField(FormFieldModel field) {
    final checked = _values[field.fieldName] == true ||
        _values[field.fieldName] == 1 ||
        _values[field.fieldName] == '1';

    return InkWell(
      onTap: () => setState(() => _values[field.fieldName] = !checked),
      borderRadius: BorderRadius.circular(6),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(
              value: checked,
              onChanged: (v) => setState(() => _values[field.fieldName] = v ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              activeColor: AppColors.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            field.label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
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
      child: InputDecorator(
        decoration: _inputDecoration(field.label, null, false),
        child: Text(
          currentVal.isEmpty ? 'Chọn ngày' : currentVal,
          style: TextStyle(
            fontSize: 13,
            color: currentVal.isEmpty ? AppColors.textSecondaryOf(context) : AppColors.textPrimaryOf(context),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoPlaceholder(FormFieldModel field) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderOf(context)),
        borderRadius: BorderRadius.circular(6),
        color: AppColors.backgroundOf(context),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.camera_alt, size: 18, color: AppColors.textSecondaryOf(context)),
          const SizedBox(width: 6),
          Text(field.label, style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context))),
        ],
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
        const Divider(height: 12),
        Text('Khác', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondaryOf(context))),
        const SizedBox(height: 4),
      ],
      ...unmapped.map((e) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(e.key, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextFormField(
                initialValue: e.value?.toString() ?? '',
                decoration: _inputDecoration(null, null, false),
                style: const TextStyle(fontSize: 12),
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
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(kv.key, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: kv.value,
                  decoration: _inputDecoration(null, null, false),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() {
                  _customFields[i].value.dispose();
                  _customFields.removeAt(i);
                }),
                child: const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.remove_circle_outline, size: 14, color: AppColors.error),
                ),
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
            decoration: _inputDecoration('Tên', null, false),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 3,
          child: TextField(
            controller: _customValCtrl,
            decoration: _inputDecoration('Giá trị', null, false),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        GestureDetector(
          onTap: () {
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
          child: const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(Icons.add_circle, color: AppColors.primary, size: 20),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String? label, String? hint, bool required) {
    return InputDecoration(
      labelText: label != null ? (required ? '$label *' : label) : null,
      labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondaryOf(context)),
      hintText: hint,
      hintStyle: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context)),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.borderOf(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      filled: true,
      fillColor: AppColors.cardOf(context),
    );
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      for (final entry in _customFields) {
        _values[entry.key] = entry.value.text;
      }
      _values.removeWhere((_, v) => v == null || v.toString().isEmpty);
      // Return both values and pinned field names
      Navigator.pop(context, {
        '_values': _values,
        '_pinned': _pinned.toList(),
      });
    }
  }
}
