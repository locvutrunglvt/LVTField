import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// Toolbar hiển thị khi đang ở chế độ chỉnh sửa vertex.
/// Dọc bên trái: Hủy | Hoàn tác | Dời lô | Đỉnh count | Lưu
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
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(2, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Cancel button
          _VToolBtn(
            icon: Icons.close,
            label: 'Hủy',
            color: AppColors.error,
            onTap: onCancel,
          ),

          _vtDivider(context),

          // Undo button
          _VToolBtn(
            icon: Icons.undo,
            label: 'H.tác',
            color: canUndo ? AppColors.info : Colors.grey.shade400,
            onTap: canUndo ? onUndo : null,
          ),

          // Translate (move polygon) button
          _VToolBtn(
            icon: Icons.open_with,
            label: 'Dời',
            color: isTranslating ? Colors.white : const Color(0xFF7B1FA2),
            bgColor: isTranslating ? const Color(0xFF7B1FA2) : null,
            onTap: onTranslateToggle,
          ),

          _vtDivider(context),

          // Vertex count badge
          Container(
            width: 36,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$vertexCount',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.secondary,
              ),
            ),
          ),

          _vtDivider(context),

          // Save button
          _VToolBtn(
            icon: Icons.check,
            label: 'Lưu',
            color: AppColors.primary,
            onTap: onSave,
          ),
        ],
      ),
    );
  }

  Widget _vtDivider(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Container(
      width: 28,
      height: 1,
      color: AppColors.dividerOf(context),
    ),
  );
}

class _VToolBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color? bgColor;
  final VoidCallback? onTap;

  const _VToolBtn({
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
        width: 46,
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: bgColor != null
            ? BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
