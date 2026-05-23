import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// Toolbar hiển thị khi đang ở chế độ chỉnh sửa vertex.
/// Gồm: Hủy | Hoàn tác | Di chuyển lô | Đỉnh count | Lưu
///
/// Author: Lộc Vũ Trung
class VertexEditToolbar extends StatelessWidget {
  final int vertexCount;
  final bool canUndo;
  final bool isTranslating;
  final VoidCallback onCancel;
  final VoidCallback onUndo;
  final VoidCallback onSave;
  final VoidCallback? onTranslateToggle;

  const VertexEditToolbar({
    super.key,
    required this.vertexCount,
    required this.canUndo,
    required this.onCancel,
    required this.onUndo,
    required this.onSave,
    this.isTranslating = false,
    this.onTranslateToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Cancel button
          _ToolButton(
            icon: Icons.close,
            label: 'Hủy',
            color: AppColors.error,
            onTap: onCancel,
          ),

          // Undo button
          _ToolButton(
            icon: Icons.undo,
            label: 'Hoàn tác',
            color: canUndo ? AppColors.info : Colors.grey.shade400,
            onTap: canUndo ? onUndo : null,
          ),

          // Translate (move polygon) button
          _ToolButton(
            icon: Icons.open_with,
            label: 'Dời lô',
            color: isTranslating ? Colors.white : const Color(0xFF7B1FA2),
            bgColor: isTranslating ? const Color(0xFF7B1FA2) : null,
            onTap: onTranslateToggle,
          ),

          // Vertex count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$vertexCount',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.secondary,
              ),
            ),
          ),

          // Save button
          _ToolButton(
            icon: Icons.check,
            label: 'Lưu',
            color: AppColors.primary,
            onTap: onSave,
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color? bgColor;
  final VoidCallback? onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.color,
    this.bgColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: bgColor ?? color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
