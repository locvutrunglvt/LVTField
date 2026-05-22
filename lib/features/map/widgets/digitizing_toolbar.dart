import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../data/models/layer_model.dart';

/// Toolbar displayed during digitizing mode for field data collection.
/// All buttons are large (48x48 minimum) for field workers wearing gloves.
/// Author: Lộc Vũ Trung
class DigitizingToolbar extends StatelessWidget {
  final GeometryType geometryType;
  final int vertexCount;
  final VoidCallback onAddGpsVertex;
  final VoidCallback onUndo;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final bool canSave;

  const DigitizingToolbar({
    super.key,
    required this.geometryType,
    required this.vertexCount,
    required this.onAddGpsVertex,
    required this.onUndo,
    required this.onCancel,
    required this.onSave,
    required this.canSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildVertexCounter(),
            const SizedBox(height: AppSizes.sm),
            _buildButtonRow(),
          ],
        ),
      ),
    );
  }

  /// Vertex counter text: "Đã vẽ: X đỉnh"
  Widget _buildVertexCounter() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(AppSizes.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.edit_location_alt,
            size: 16,
            color: AppColors.primaryDark,
          ),
          const SizedBox(width: AppSizes.xs),
          Text(
            'Đã vẽ: $vertexCount đỉnh',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryDark,
            ),
          ),
          if (!canSave) ...[
            const SizedBox(width: AppSizes.sm),
            Text(
              '(cần ${_minVertices()} đỉnh)',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.primaryDark.withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Main button row with all toolbar actions
  Widget _buildButtonRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Cancel button
        _buildToolButton(
          icon: Icons.close,
          label: 'Hủy',
          color: AppColors.error,
          onPressed: onCancel,
        ),
        // Undo button
        _buildToolButton(
          icon: Icons.undo,
          label: 'Hoàn tác',
          color: AppColors.textSecondary,
          onPressed: vertexCount > 0 ? onUndo : null,
        ),
        // GPS vertex button (primary action)
        _buildGpsButton(),
        // Close polygon button (polygon only)
        if (geometryType == GeometryType.polygon)
          _buildToolButton(
            icon: Icons.crop_square,
            label: 'Đóng vùng',
            color: AppColors.polygonStroke,
            onPressed: canSave ? onSave : null,
          )
        else
          // Save/Finish button (point and line)
          _buildToolButton(
            icon: Icons.check,
            label: _saveLabel(),
            color: AppColors.success,
            onPressed: canSave ? onSave : null,
          ),
      ],
    );
  }

  /// GPS vertex capture button — the primary action, styled prominently
  Widget _buildGpsButton() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 56,
          height: 56,
          child: FloatingActionButton(
            heroTag: 'digitizing_gps',
            onPressed: onAddGpsVertex,
            backgroundColor: AppColors.primary,
            elevation: 3,
            child: const Icon(
              Icons.gps_fixed,
              color: Colors.white,
              size: AppSizes.iconLg,
            ),
          ),
        ),
        const SizedBox(height: AppSizes.xs),
        const Text(
          'GPS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }

  /// Generic toolbar button with icon and label
  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onPressed,
  }) {
    final isDisabled = onPressed == null;
    final effectiveColor = isDisabled ? color.withValues(alpha: 0.35) : color;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: Material(
            color: effectiveColor.withValues(alpha: isDisabled ? 0.08 : 0.12),
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              child: Icon(
                icon,
                color: effectiveColor,
                size: AppSizes.iconMd,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSizes.xs),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: effectiveColor,
          ),
        ),
      ],
    );
  }

  /// Minimum vertices required for the current geometry type
  int _minVertices() {
    switch (geometryType) {
      case GeometryType.point:
        return 1;
      case GeometryType.line:
        return 2;
      case GeometryType.polygon:
        return 3;
    }
  }

  /// Save button label based on geometry type
  String _saveLabel() {
    switch (geometryType) {
      case GeometryType.point:
        return 'Lưu';
      case GeometryType.line:
        return 'Kết thúc';
      case GeometryType.polygon:
        return 'Đóng vùng';
    }
  }
}
