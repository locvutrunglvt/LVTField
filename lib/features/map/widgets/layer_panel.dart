import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../data/models/layer_model.dart';

/// Bottom sheet panel displaying all layers in the current project.
/// Allows toggling visibility, deleting layers, and adding new ones.
/// Author: Lộc Vũ Trung
class LayerPanel extends StatelessWidget {
  final List<LayerModel> layers;
  final Map<String, int> featureCounts;
  final VoidCallback onAddLayer;
  final Function(String layerId, bool visible) onToggleVisibility;
  final Function(String layerId) onDeleteLayer;

  const LayerPanel({
    super.key,
    required this.layers,
    required this.featureCounts,
    required this.onAddLayer,
    required this.onToggleVisibility,
    required this.onDeleteLayer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSizes.radiusLg),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDragHandle(),
          _buildHeader(context),
          const Divider(height: 1, color: AppColors.divider),
          if (layers.isEmpty) _buildEmptyState() else _buildLayerList(),
        ],
      ),
    );
  }

  /// Drag handle indicator at the top of the bottom sheet
  Widget _buildDragHandle() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: AppSizes.sm),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(AppSizes.radiusFull),
        ),
      ),
    );
  }

  /// Header with title and "Add layer" button
  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Lớp dữ liệu',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          TextButton.icon(
            onPressed: onAddLayer,
            icon: const Icon(Icons.add, size: AppSizes.iconSm),
            label: const Text('Thêm lớp'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  /// Empty state when no layers exist
  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(AppSizes.xl),
      child: Column(
        children: [
          Icon(
            Icons.layers_outlined,
            size: AppSizes.iconXl,
            color: AppColors.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: AppSizes.sm),
          const Text(
            'Chưa có lớp dữ liệu nào',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSizes.xs),
          const Text(
            'Nhấn "Thêm lớp" để bắt đầu',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Scrollable list of layer tiles
  Widget _buildLayerList() {
    return Flexible(
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
        itemCount: layers.length,
        separatorBuilder: (_, __) => const Divider(
          height: 1,
          indent: AppSizes.md,
          endIndent: AppSizes.md,
          color: AppColors.divider,
        ),
        itemBuilder: (context, index) => _buildLayerTile(context, layers[index]),
      ),
    );
  }

  /// Individual layer tile with color, name, type icon, count, visibility toggle
  Widget _buildLayerTile(BuildContext context, LayerModel layer) {
    final count = featureCounts[layer.id] ?? 0;

    return Opacity(
      opacity: layer.isVisible ? 1.0 : 0.5,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md,
          vertical: AppSizes.xs,
        ),
        leading: _buildColorIndicator(layer),
        title: Text(
          layer.name,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Row(
          children: [
            Icon(
              _geometryIcon(layer.geometryType),
              size: 14,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: AppSizes.xs),
            Text(
              _geometryLabel(layer.geometryType),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            _buildFeatureCountBadge(count),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Visibility toggle
            IconButton(
              icon: Icon(
                layer.isVisible ? Icons.visibility : Icons.visibility_off,
                color: layer.isVisible
                    ? AppColors.primary
                    : AppColors.textSecondary,
                size: AppSizes.iconMd,
              ),
              onPressed: () => onToggleVisibility(layer.id, !layer.isVisible),
              tooltip: layer.isVisible ? 'Ẩn lớp' : 'Hiện lớp',
            ),
            // More options popup
            PopupMenuButton<String>(
              icon: const Icon(
                Icons.more_vert,
                color: AppColors.textSecondary,
                size: AppSizes.iconMd,
              ),
              onSelected: (value) {
                if (value == 'delete') {
                  _confirmDelete(context, layer);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                      SizedBox(width: AppSizes.sm),
                      Text(
                        'Xóa lớp',
                        style: TextStyle(color: AppColors.error),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Circular color indicator matching the layer's display color
  Widget _buildColorIndicator(LayerModel layer) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: layer.displayColor.withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(
          color: layer.displayColor,
          width: 2.5,
        ),
      ),
      child: Icon(
        _geometryIcon(layer.geometryType),
        size: 16,
        color: layer.displayColor,
      ),
    );
  }

  /// Feature count badge
  Widget _buildFeatureCountBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(AppSizes.radiusFull),
      ),
      child: Text(
        '$count đối tượng',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.primaryDark,
        ),
      ),
    );
  }

  /// Show delete confirmation dialog
  void _confirmDelete(BuildContext context, LayerModel layer) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa lớp dữ liệu'),
        content: Text(
          'Bạn có chắc muốn xóa lớp "${layer.name}"?\n'
          'Tất cả dữ liệu trong lớp sẽ bị mất.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onDeleteLayer(layer.id);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
  }

  /// Get icon for geometry type
  IconData _geometryIcon(GeometryType type) {
    switch (type) {
      case GeometryType.point:
        return Icons.location_on;
      case GeometryType.line:
        return Icons.timeline;
      case GeometryType.polygon:
        return Icons.pentagon;
    }
  }

  /// Get Vietnamese label for geometry type
  String _geometryLabel(GeometryType type) {
    switch (type) {
      case GeometryType.point:
        return 'Điểm';
      case GeometryType.line:
        return 'Đường';
      case GeometryType.polygon:
        return 'Vùng';
    }
  }
}
