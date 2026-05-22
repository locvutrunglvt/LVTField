import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../data/models/layer_model.dart';

/// Dialog for creating a new data layer.
/// Collects layer name and geometry type, then returns a [LayerModel].
/// Author: Lộc Vũ Trung
class AddLayerDialog extends StatefulWidget {
  final String projectId;

  const AddLayerDialog({
    super.key,
    required this.projectId,
  });

  /// Show the dialog and return the created [LayerModel], or null if cancelled
  static Future<LayerModel?> show(BuildContext context, String projectId) {
    return showDialog<LayerModel>(
      context: context,
      builder: (_) => AddLayerDialog(projectId: projectId),
    );
  }

  @override
  State<AddLayerDialog> createState() => _AddLayerDialogState();
}

class _AddLayerDialogState extends State<AddLayerDialog> {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  GeometryType _selectedType = GeometryType.point;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.lg),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTitle(),
              const SizedBox(height: AppSizes.lg),
              _buildNameField(),
              const SizedBox(height: AppSizes.lg),
              _buildGeometryTypeLabel(),
              const SizedBox(height: AppSizes.sm),
              _buildGeometryTypeSelector(),
              const SizedBox(height: AppSizes.lg),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  /// Dialog title
  Widget _buildTitle() {
    return const Row(
      children: [
        Icon(Icons.layers, color: AppColors.primary, size: AppSizes.iconMd),
        SizedBox(width: AppSizes.sm),
        Text(
          'Thêm lớp mới',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  /// Layer name text field with validation
  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: 'Tên lớp dữ liệu',
        hintText: 'VD: Lô rừng, Cây cá thể...',
        prefixIcon: const Icon(Icons.edit_outlined),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return AppStrings.requiredField;
        }
        return null;
      },
    );
  }

  /// Label above geometry type buttons
  Widget _buildGeometryTypeLabel() {
    return const Text(
      'Loại hình học',
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    );
  }

  /// Three large geometry type selection buttons
  Widget _buildGeometryTypeSelector() {
    return Row(
      children: [
        Expanded(
          child: _buildTypeButton(
            type: GeometryType.point,
            icon: Icons.location_on,
            label: AppStrings.addPoint,
            color: AppColors.pointColor,
          ),
        ),
        const SizedBox(width: AppSizes.sm),
        Expanded(
          child: _buildTypeButton(
            type: GeometryType.line,
            icon: Icons.timeline,
            label: AppStrings.addLine,
            color: AppColors.lineColor,
          ),
        ),
        const SizedBox(width: AppSizes.sm),
        Expanded(
          child: _buildTypeButton(
            type: GeometryType.polygon,
            icon: Icons.pentagon,
            label: AppStrings.addPolygon,
            color: AppColors.polygonStroke,
          ),
        ),
      ],
    );
  }

  /// Individual geometry type selection button
  Widget _buildTypeButton({
    required GeometryType type,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final isSelected = _selectedType == type;

    return GestureDetector(
      onTap: () => setState(() => _selectedType = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          vertical: AppSizes.md,
          horizontal: AppSizes.sm,
        ),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : AppColors.background,
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          border: Border.all(
            color: isSelected ? color : AppColors.border,
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: AppSizes.iconLg,
              color: isSelected ? color : AppColors.textSecondary,
            ),
            const SizedBox(height: AppSizes.xs),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? color : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Cancel and Create action buttons
  Widget _buildActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            AppStrings.cancel,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(width: AppSizes.sm),
        FilledButton.icon(
          onPressed: _onSubmit,
          icon: const Icon(Icons.add, size: AppSizes.iconSm),
          label: const Text('Tạo lớp'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textOnPrimary,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.lg,
              vertical: AppSizes.sm,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
          ),
        ),
      ],
    );
  }

  /// Validate and return a new [LayerModel]
  void _onSubmit() {
    if (!_formKey.currentState!.validate()) return;

    final layer = LayerModel(
      projectId: widget.projectId,
      name: _nameController.text.trim(),
      geometryType: _selectedType,
    );

    Navigator.of(context).pop(layer);
  }
}
