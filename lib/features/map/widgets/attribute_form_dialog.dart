import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/services/form_engine_service.dart';
import '../../../data/models/form_field_model.dart';
import '../../../data/repositories/feature_repository.dart';
import 'form_field_widget.dart';

/// Dialog that renders a dynamic attribute form after the user saves
/// a feature geometry.
///
/// It loads [FormFieldModel] definitions for the given layer,
/// renders each field with appropriate widgets, validates on submit,
/// and persists the attributes back to the database.
///
/// Author: Lộc Vũ Trung
class AttributeFormDialog extends StatefulWidget {
  /// The layer whose form template should be displayed.
  final String layerId;

  /// The feature to attach the attributes to.
  final String featureId;

  const AttributeFormDialog({
    super.key,
    required this.layerId,
    required this.featureId,
  });

  /// Convenience method to show the dialog.
  ///
  /// Returns the saved attribute map, or `null` if the user skipped.
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required String layerId,
    required String featureId,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AttributeFormDialog(
        layerId: layerId,
        featureId: featureId,
      ),
    );
  }

  @override
  State<AttributeFormDialog> createState() => _AttributeFormDialogState();
}

class _AttributeFormDialogState extends State<AttributeFormDialog> {
  final _formEngine = FormEngineService();
  final _featureRepo = FeatureRepository();

  List<FormFieldModel> _fields = [];
  Map<String, dynamic> _values = {};
  Map<String, String> _errors = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadForm();
  }

  // ─── Data loading ────────────────────────────────────────────────

  Future<void> _loadForm() async {
    try {
      // Load field definitions
      final fields = await _formEngine.getFieldsForLayer(widget.layerId);

      // Load existing feature attributes (for pre-fill / editing)
      final feature = await _featureRepo.getById(widget.featureId);
      final existingAttrs = feature?.attributes ?? {};

      // Merge existing values with defaults
      final values = <String, dynamic>{};
      for (final f in fields) {
        if (existingAttrs.containsKey(f.fieldName)) {
          values[f.fieldName] = existingAttrs[f.fieldName];
        } else if (f.defaultValue != null) {
          values[f.fieldName] = f.defaultValue;
        }
      }

      if (!mounted) return;
      setState(() {
        _fields = fields;
        _values = values;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      debugPrint('AttributeFormDialog: failed to load form – $e');
    }
  }

  // ─── Save ────────────────────────────────────────────────────────

  Future<void> _onSave() async {
    // Validate
    final errors = _formEngine.validate(_fields, _values);
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;

    setState(() => _saving = true);

    try {
      // Load current feature, merge attributes, update
      final feature = await _featureRepo.getById(widget.featureId);
      if (feature != null) {
        final merged = Map<String, dynamic>.from(feature.attributes)
          ..addAll(_values);
        final updated = feature.copyWith(attributes: merged);
        await _featureRepo.update(updated);
      }

      if (!mounted) return;
      Navigator.of(context).pop(_values);
    } catch (e) {
      debugPrint('AttributeFormDialog: save failed – $e');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lưu thất bại, vui lòng thử lại'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  // ─── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.xl,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          Divider(height: 1, color: AppColors.dividerOf(context)),
          Flexible(child: _buildBody()),
          Divider(height: 1, color: AppColors.dividerOf(context)),
          _buildActions(),
        ],
      ),
    );
  }

  // ─── Header ──────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSizes.radiusMd),
        ),
      ),
      child: const Row(
        children: [
          Icon(Icons.edit_note, color: AppColors.textOnPrimary),
          SizedBox(width: AppSizes.sm),
          Text(
            'Nhập thuộc tính',
            style: TextStyle(
              color: AppColors.textOnPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Body ────────────────────────────────────────────────────────

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(AppSizes.xl),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (_fields.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSizes.xl),
        child: Center(
          child: Text(
            'Chưa có trường thuộc tính.\nHãy thiết lập biểu mẫu cho lớp này.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondaryOf(context)),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSizes.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _fields.map((field) {
          return FormFieldWidget(
            fieldModel: field,
            value: _values[field.fieldName],
            errorText: _errors[field.fieldName],
            onChanged: (v) {
              setState(() {
                _values[field.fieldName] = v;
                _errors.remove(field.fieldName);
              });
            },
          );
        }).toList(),
      ),
    );
  }

  // ─── Action buttons ──────────────────────────────────────────────

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.sm,
      ),
      child: Row(
        children: [
          // Skip button
          Expanded(
            child: OutlinedButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(null),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(AppSizes.buttonHeight),
                side: BorderSide(color: AppColors.borderOf(context)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                ),
              ),
              child: Text(
                'Bỏ qua',
                style: TextStyle(color: AppColors.textSecondaryOf(context)),
              ),
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          // Save button
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _onSave,
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textOnPrimary,
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(_saving ? 'Đang lưu...' : 'Lưu'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(AppSizes.buttonHeight),
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
