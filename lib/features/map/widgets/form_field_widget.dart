import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../data/models/form_field_model.dart';

/// Renders a single dynamic form field based on its [FormFieldModel] definition.
///
/// Supports: text, textMultiline, number, numberAuto, dropdown,
/// checkbox, date, and photo field types.
///
/// Author: Lộc Vũ Trung
class FormFieldWidget extends StatelessWidget {
  /// The field definition that drives rendering.
  final FormFieldModel fieldModel;

  /// Current value of the field.
  final dynamic value;

  /// Called whenever the user changes the field value.
  final ValueChanged<dynamic> onChanged;

  /// Optional error text shown below the field.
  final String? errorText;

  const FormFieldWidget({
    super.key,
    required this.fieldModel,
    required this.value,
    required this.onChanged,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.md),
      child: _buildField(context),
    );
  }

  // ─── Field dispatcher ────────────────────────────────────────────

  Widget _buildField(BuildContext context) {
    switch (fieldModel.fieldType) {
      case FormFieldType.text:
        return _buildTextField(maxLines: 1);
      case FormFieldType.textMultiline:
        return _buildTextField(maxLines: 3);
      case FormFieldType.number:
        return _buildNumberField();
      case FormFieldType.numberAuto:
        return _buildNumberField(readOnly: true);
      case FormFieldType.dropdown:
        return _buildDropdown();
      case FormFieldType.checkbox:
        return _buildCheckbox();
      case FormFieldType.date:
        return _buildDatePicker(context);
      case FormFieldType.photo:
        return _buildPhotoPlaceholder();
    }
  }

  // ─── Text ────────────────────────────────────────────────────────

  Widget _buildTextField({int maxLines = 1}) {
    return TextFormField(
      initialValue: value?.toString() ?? '',
      maxLines: maxLines,
      decoration: _inputDecoration(),
      onChanged: onChanged,
    );
  }

  // ─── Number ──────────────────────────────────────────────────────

  Widget _buildNumberField({bool readOnly = false}) {
    return TextFormField(
      initialValue: value?.toString() ?? '',
      readOnly: readOnly,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
      ],
      decoration: _inputDecoration().copyWith(
        suffixIcon: readOnly
            ? const Icon(Icons.lock_outline, size: AppSizes.iconSm)
            : null,
      ),
      onChanged: onChanged,
    );
  }

  // ─── Dropdown ────────────────────────────────────────────────────

  Widget _buildDropdown() {
    final items = fieldModel.options ?? [];
    final currentValue =
        items.any((o) => o['value'] == value?.toString()) ? value?.toString() : null;

    return DropdownButtonFormField<String>(
      value: currentValue,
      decoration: _inputDecoration(),
      isExpanded: true,
      items: items.map((opt) {
        return DropdownMenuItem<String>(
          value: opt['value'],
          child: Text(opt['label'] ?? opt['value'] ?? ''),
        );
      }).toList(),
      onChanged: (v) => onChanged(v),
    );
  }

  // ─── Checkbox ────────────────────────────────────────────────────

  Widget _buildCheckbox() {
    final checked = value == true || value == 1 || value == '1';
    return CheckboxListTile(
      value: checked,
      title: Text(
        fieldModel.label,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: errorText != null
          ? Text(errorText!, style: const TextStyle(color: AppColors.error, fontSize: 12))
          : null,
      contentPadding: EdgeInsets.zero,
      activeColor: AppColors.primary,
      controlAffinity: ListTileControlAffinity.leading,
      onChanged: (v) => onChanged(v ?? false),
    );
  }

  // ─── Date Picker ─────────────────────────────────────────────────

  Widget _buildDatePicker(BuildContext context) {
    final displayText = value?.toString() ?? '';
    return TextFormField(
      readOnly: true,
      controller: TextEditingController(text: displayText),
      decoration: _inputDecoration().copyWith(
        suffixIcon: const Icon(Icons.calendar_today, size: AppSizes.iconSm),
      ),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: _tryParseDate(value) ?? now,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
          builder: (ctx, child) {
            return Theme(
              data: Theme.of(ctx).copyWith(
                colorScheme: const ColorScheme.light(
                  primary: AppColors.primary,
                  onPrimary: AppColors.textOnPrimary,
                ),
              ),
              child: child!,
            );
          },
        );
        if (picked != null) {
          onChanged(picked.toIso8601String().split('T').first);
        }
      },
    );
  }

  // ─── Photo placeholder ──────────────────────────────────────────

  Widget _buildPhotoPlaceholder() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          fieldModel.label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSizes.xs),
        Container(
          height: 80,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppSizes.radiusSm),
          ),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.camera_alt_outlined,
                    color: AppColors.textSecondary, size: AppSizes.iconLg),
                SizedBox(height: AppSizes.xs),
                Text('Chụp ảnh',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSizes.xs),
            child: Text(errorText!,
                style: const TextStyle(color: AppColors.error, fontSize: 12)),
          ),
      ],
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────

  InputDecoration _inputDecoration() {
    return InputDecoration(
      labelText: fieldModel.label,
      hintText: fieldModel.hint,
      errorText: errorText,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.sm + AppSizes.xs,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      suffixText: fieldModel.isRequired ? '*' : null,
      suffixStyle: const TextStyle(
        color: AppColors.error,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  DateTime? _tryParseDate(dynamic val) {
    if (val == null) return null;
    return DateTime.tryParse(val.toString());
  }
}
