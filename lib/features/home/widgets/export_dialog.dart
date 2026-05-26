// Export dialog for LVTField project data
// Provides format selection and file sharing
// Author: Lộc Vũ Trung

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/services/export_service.dart';
import '../../../data/repositories/layer_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/models/layer_model.dart';

/// Export format options
enum _ExportFormat {
  geoJsonAll,
  geoJsonSingle,
  kml,
  gpx,
  csv,
  kmz,
  lvtfieldPackage,
}

/// Dialog for exporting project data in various formats
///
/// Shows export format options, filename preview, and handles
/// the export process with progress indication and sharing.
class ExportDialog extends StatefulWidget {
  final String projectId;
  final String username;

  const ExportDialog({
    super.key,
    required this.projectId,
    required this.username,
  });

  /// Show the export dialog
  static Future<void> show(
    BuildContext context, {
    required String projectId,
    required String username,
  }) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ExportDialog(
        projectId: projectId,
        username: username,
      ),
    );
  }

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  final ExportService _exportService = ExportService();
  final LayerRepository _layerRepo = LayerRepository();
  final ProjectRepository _projectRepo = ProjectRepository();

  _ExportFormat _selectedFormat = _ExportFormat.geoJsonAll;
  LayerModel? _selectedLayer;
  List<LayerModel> _layers = [];
  String _projectName = '';

  bool _isExporting = false;
  bool _isExported = false;
  String? _exportedPath;
  String? _errorMessage;
  int _exportedFeatureCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final project = await _projectRepo.getById(widget.projectId);
    final layers = await _layerRepo.getByProject(widget.projectId);
    if (mounted) {
      setState(() {
        _projectName = project?.name ?? 'Dự án';
        _layers = layers;
        if (layers.isNotEmpty) {
          _selectedLayer = layers.first;
        }
      });
    }
  }

  /// Generate preview filename based on current selection
  String _previewFilename() {
    final safeName = _projectName.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final safeUser = widget.username.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final date = DateTime.now();
    final timestamp = '${date.year}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}_'
        '${date.hour.toString().padLeft(2, '0')}'
        '${date.minute.toString().padLeft(2, '0')}'
        '${date.second.toString().padLeft(2, '0')}';

    switch (_selectedFormat) {
      case _ExportFormat.geoJsonAll:
        return '${safeName}_${safeUser}_$timestamp/';
      case _ExportFormat.geoJsonSingle:
        final layerName = _selectedLayer?.name ?? 'layer';
        final safeLayer = layerName.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
        return '${safeName}_${safeLayer}_${safeUser}_$timestamp.geojson';
      case _ExportFormat.kml:
        return '${safeName}_${safeUser}_$timestamp.kml';
      case _ExportFormat.gpx:
        return '${safeName}_${safeUser}_$timestamp.gpx';
      case _ExportFormat.csv:
        return '${safeName}_${safeUser}_$timestamp.csv';
      case _ExportFormat.kmz:
        return '${safeName}_${safeUser}_$timestamp.kmz';
      case _ExportFormat.lvtfieldPackage:
        return '${safeName}_${safeUser}_$timestamp.lvtfield';
    }
  }

  Future<void> _doExport() async {
    setState(() {
      _isExporting = true;
      _errorMessage = null;
    });

    ExportResult result;

    switch (_selectedFormat) {
      case _ExportFormat.geoJsonAll:
        result = await _exportService.exportAllLayersGeoJson(
          projectId: widget.projectId,
          username: widget.username,
        );
        break;
      case _ExportFormat.geoJsonSingle:
        if (_selectedLayer == null) {
          setState(() {
            _isExporting = false;
            _errorMessage = 'Vui lòng chọn lớp dữ liệu';
          });
          return;
        }
        result = await _exportService.exportGeoJson(
          projectId: widget.projectId,
          layerId: _selectedLayer!.id,
          username: widget.username,
        );
        break;
      case _ExportFormat.lvtfieldPackage:
        result = await _exportService.exportProjectPackage(
          projectId: widget.projectId,
          username: widget.username,
        );
        break;
      case _ExportFormat.kml:
      case _ExportFormat.gpx:
      case _ExportFormat.csv:
      case _ExportFormat.kmz:
        if (_selectedLayer == null) {
          setState(() {
            _isExporting = false;
            _errorMessage = 'Vui lòng chọn lớp dữ liệu';
          });
          return;
        }
        switch (_selectedFormat) {
          case _ExportFormat.kml:
            result = await _exportService.exportKML(
              projectId: widget.projectId,
              layerId: _selectedLayer!.id,
              username: widget.username,
            );
            break;
          case _ExportFormat.gpx:
            result = await _exportService.exportGPX(
              projectId: widget.projectId,
              layerId: _selectedLayer!.id,
              username: widget.username,
            );
            break;
          case _ExportFormat.csv:
            result = await _exportService.exportCSV(
              projectId: widget.projectId,
              layerId: _selectedLayer!.id,
              username: widget.username,
            );
            break;
          case _ExportFormat.kmz:
            result = await _exportService.exportKMZ(
              projectId: widget.projectId,
              layerId: _selectedLayer!.id,
              username: widget.username,
            );
            break;
          default:
            return;
        }
        break;
    }

    if (mounted) {
      setState(() {
        _isExporting = false;
        if (result.success) {
          _isExported = true;
          _exportedPath = result.filePath;
          _exportedFeatureCount = result.featureCount;
        } else {
          _errorMessage = result.errorMessage;
        }
      });
    }
  }

  void _shareFile() {
    if (_exportedPath != null) {
      _exportService.shareFile(_exportedPath!);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isExported) {
      return _buildSuccessDialog();
    }
    return _buildExportDialog();
  }

  Widget _buildExportDialog() {
    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primarySurfaceOf(context),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.upload_file,
              color: AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          const Expanded(
            child: Text(
              'Xuất dữ liệu',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Project name
              _buildInfoRow(Icons.folder_outlined, 'Dự án', _projectName),
              const SizedBox(height: AppSizes.xs),
              _buildInfoRow(Icons.person_outline, 'Người dùng', widget.username),
              const SizedBox(height: AppSizes.md),

              // Format selection
              const Text(
                'Định dạng xuất:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: AppSizes.sm),

              // GeoJSON all layers
              _buildFormatOption(
                format: _ExportFormat.geoJsonAll,
                icon: Icons.layers,
                title: 'GeoJSON (tất cả lớp)',
                subtitle: 'Xuất mỗi lớp thành file .geojson riêng',
              ),

              // GeoJSON single layer
              _buildFormatOption(
                format: _ExportFormat.geoJsonSingle,
                icon: Icons.layers_outlined,
                title: 'GeoJSON (chọn lớp)',
                subtitle: 'Xuất 1 lớp dữ liệu cụ thể',
              ),

              // LVTField package
              _buildFormatOption(
                format: _ExportFormat.lvtfieldPackage,
                icon: Icons.inventory_2_outlined,
                title: 'Gói LVTField (.lvtfield)',
                subtitle: 'Dự án đầy đủ: lớp, biểu mẫu, ảnh',
              ),

              const Divider(height: 16),

              // KML
              _buildFormatOption(
                format: _ExportFormat.kml,
                icon: Icons.public,
                title: 'KML (Google Earth)',
                subtitle: 'Mở trong Google Earth',
              ),

              // GPX
              _buildFormatOption(
                format: _ExportFormat.gpx,
                icon: Icons.terrain,
                title: 'GPX (GPS Track)',
                subtitle: 'Cho Garmin, hiking apps',
              ),

              // CSV
              _buildFormatOption(
                format: _ExportFormat.csv,
                icon: Icons.table_chart,
                title: 'CSV (Excel)',
                subtitle: 'Bảng thuộc tính, mở trong Excel',
              ),

              // KMZ
              _buildFormatOption(
                format: _ExportFormat.kmz,
                icon: Icons.folder_zip,
                title: 'KMZ (KML nén)',
                subtitle: 'KML nén, nhẹ hơn',
              ),

              // Layer picker for single-layer formats
              if (_selectedFormat != _ExportFormat.geoJsonAll &&
                  _selectedFormat != _ExportFormat.lvtfieldPackage) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 4),
                  child: DropdownButtonFormField<LayerModel>(
                    value: _selectedLayer,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Chọn lớp dữ liệu',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      isDense: true,
                    ),
                    items: _layers.map((layer) {
                      return DropdownMenuItem(
                        value: layer,
                        child: Text(layer.name, overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() => _selectedLayer = value);
                    },
                  ),
                ),
              ],

              const SizedBox(height: AppSizes.md),

              // Filename preview
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSizes.sm),
                decoration: BoxDecoration(
                  color: AppColors.primarySurfaceOf(context).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                  border: Border.all(color: AppColors.borderOf(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tên file:',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _previewFilename(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // Error message
              if (_errorMessage != null) ...[
                const SizedBox(height: AppSizes.sm),
                Container(
                  padding: const EdgeInsets.all(AppSizes.sm),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.error, size: 18),
                      const SizedBox(width: AppSizes.xs),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isExporting ? null : () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        ElevatedButton.icon(
          onPressed: _isExporting ? null : _doExport,
          icon: _isExporting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download, size: 20),
          label: Text(_isExporting ? 'Đang xuất...' : 'Xuất dữ liệu'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(130, 44),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessDialog() {
    final description = _exportedPath != null
        ? _exportService.getExportDescription(_exportedPath!)
        : '';

    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.check_circle,
              color: AppColors.success,
              size: 24,
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          const Text('Xuất thành công!'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$_exportedFeatureCount đối tượng đã được xuất.',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: AppSizes.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSizes.sm),
            decoration: BoxDecoration(
              color: AppColors.primarySurfaceOf(context).withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppSizes.radiusSm),
              border: Border.all(color: AppColors.borderOf(context)),
            ),
            child: Text(
              description,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
        ElevatedButton.icon(
          onPressed: _shareFile,
          icon: const Icon(Icons.share, size: 20),
          label: const Text('Chia sẻ'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(110, 44),
          ),
        ),
      ],
    );
  }

  Widget _buildFormatOption({
    required _ExportFormat format,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return RadioListTile<_ExportFormat>(
      value: format,
      groupValue: _selectedFormat,
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(left: 28),
        child: Text(
          subtitle,
          style: const TextStyle(fontSize: 12),
        ),
      ),
      onChanged: _isExporting
          ? null
          : (value) {
              if (value != null) {
                setState(() => _selectedFormat = value);
              }
            },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondaryOf(context)),
        const SizedBox(width: AppSizes.xs),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondaryOf(context),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
