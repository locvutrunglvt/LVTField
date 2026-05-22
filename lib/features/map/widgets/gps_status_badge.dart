import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/gps_service.dart';

/// Compact badge widget displaying GPS status and accuracy.
/// Tapping the badge shows a detail dialog with full GPS info.
/// Author: Lộc Vũ Trung
class GpsStatusBadge extends StatelessWidget {
  final GpsPosition? position;
  final bool isTracking;

  const GpsStatusBadge({
    super.key,
    this.position,
    this.isTracking = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = _backgroundColorForQuality();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showGpsDetailDialog(context),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: bgColor.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isTracking ? Icons.gps_fixed : Icons.gps_off,
                size: 18,
                color: Colors.white,
              ),
              if (position != null) ...[
                const SizedBox(width: 6),
                Text(
                  position!.accuracyText,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Background color based on GPS accuracy quality
  Color _backgroundColorForQuality() {
    if (position == null || !isTracking) return AppColors.textSecondary;

    switch (position!.quality) {
      case GpsQuality.good:
        return AppColors.gpsGood;
      case GpsQuality.moderate:
        return AppColors.gpsModerate;
      case GpsQuality.poor:
        return AppColors.gpsPoor;
      case GpsQuality.noSignal:
        return AppColors.textSecondary;
    }
  }

  /// Show detail dialog with full GPS information
  void _showGpsDetailDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isTracking ? Icons.gps_fixed : Icons.gps_off,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            const Text('Thông tin GPS'),
          ],
        ),
        content: position != null
            ? _buildGpsDetails()
            : const Text(
                'Không có tín hiệu GPS.\nHãy bật GPS và ra ngoài trời.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  /// GPS detail info rows
  Widget _buildGpsDetails() {
    final pos = position!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDetailRow(
          icon: Icons.my_location,
          label: 'Vĩ độ',
          value: pos.latLng.latitude.toStringAsFixed(6),
        ),
        _buildDetailRow(
          icon: Icons.my_location,
          label: 'Kinh độ',
          value: pos.latLng.longitude.toStringAsFixed(6),
        ),
        _buildDetailRow(
          icon: Icons.height,
          label: 'Độ cao',
          value: pos.altitude != null
              ? '${pos.altitude!.toStringAsFixed(1)} m'
              : '—',
        ),
        _buildDetailRow(
          icon: Icons.adjust,
          label: 'Độ chính xác',
          value: pos.accuracyText,
          valueColor: _accuracyColor(pos.quality),
        ),
        _buildDetailRow(
          icon: Icons.speed,
          label: 'Tốc độ',
          value: pos.speed != null
              ? '${(pos.speed! * 3.6).toStringAsFixed(1)} km/h'
              : '—',
        ),
        _buildDetailRow(
          icon: Icons.access_time,
          label: 'Thời gian',
          value: _formatTimestamp(pos.timestamp),
        ),
        const SizedBox(height: 8),
        _buildQualityIndicator(pos.quality),
      ],
    );
  }

  /// Single detail row with icon, label, and value
  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// Quality indicator bar at the bottom of the detail dialog
  Widget _buildQualityIndicator(GpsQuality quality) {
    final color = _accuracyColor(quality);
    final label = _qualityLabel(quality);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.signal_cellular_alt, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// Color for GPS quality level
  Color _accuracyColor(GpsQuality quality) {
    switch (quality) {
      case GpsQuality.good:
        return AppColors.gpsGood;
      case GpsQuality.moderate:
        return AppColors.gpsModerate;
      case GpsQuality.poor:
        return AppColors.gpsPoor;
      case GpsQuality.noSignal:
        return AppColors.textSecondary;
    }
  }

  /// Vietnamese label for GPS quality level
  String _qualityLabel(GpsQuality quality) {
    switch (quality) {
      case GpsQuality.good:
        return 'Tín hiệu tốt';
      case GpsQuality.moderate:
        return 'Tín hiệu trung bình';
      case GpsQuality.poor:
        return 'Tín hiệu yếu';
      case GpsQuality.noSignal:
        return 'Không có tín hiệu';
    }
  }

  /// Format timestamp to HH:mm:ss
  String _formatTimestamp(DateTime timestamp) {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
