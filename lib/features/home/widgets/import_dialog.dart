// Import dialog for LVTField project data
// Supports GeoJSON, GPKG, KML, QGS and .lvtfield package imports
// Author: Lộc Vũ Trung

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/services/import_service.dart';
import '../../../core/services/qfield_package_importer.dart';

/// Dialog for importing GeoJSON files or .lvtfield packages
///
/// - GeoJSON import: adds a new layer to an existing project
/// - LVTField package import: creates a new project with all data
class ImportDialog extends StatefulWidget {
  final String? projectId;

  const ImportDialog({
    super.key,
    this.projectId,
  });

  /// Show the import dialog
  static Future<void> show(
    BuildContext context, {
    String? projectId,
  }) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ImportDialog(projectId: projectId),
    );
  }

  @override
  State<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<ImportDialog> {
  final ImportService _importService = ImportService();
  final QFieldPackageImporter _qfieldImporter = QFieldPackageImporter();

  bool _isImporting = false;
  bool _isImported = false;
  String? _importedProjectId;
  String? _errorMessage;
  String? _successMessage;

  /// Pick and import a GeoJSON file
  Future<void> _importGeoJson() async {
    if (widget.projectId == null) {
      setState(() {
        _errorMessage = 'Vui lòng mở dự án trước khi nhập GeoJSON';
      });
      return;
    }

    try {
      // Pick a .geojson file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['geojson', 'json'],
        dialogTitle: 'Chọn file GeoJSON',
      );

      if (result == null || result.files.single.path == null) return;

      setState(() {
        _isImporting = true;
        _errorMessage = null;
      });

      final filePath = result.files.single.path!;
      final importResult = await _importService.importGeoJson(
        filePath,
        widget.projectId!,
      );

      if (mounted) {
        setState(() {
          _isImporting = false;
          if (importResult.success) {
            _isImported = true;
            _importedProjectId = importResult.projectId;
            _successMessage = 'Đã nhập ${importResult.featureCount} đối tượng '
                'vào ${importResult.layerCount} lớp dữ liệu.';
          } else {
            _errorMessage = importResult.errorMessage;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _errorMessage = 'Lỗi chọn file: $e';
        });
      }
    }
  }

  /// Pick and import any supported file format (KML, KMZ, SHP, MBTiles)
  Future<void> _importFormat(List<String> extensions, String dialogTitle) async {
    if (widget.projectId == null) {
      setState(() {
        _errorMessage = 'Vui lòng mở dự án trước khi nhập dữ liệu';
      });
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: extensions,
        dialogTitle: dialogTitle,
      );

      if (result == null || result.files.single.path == null) return;

      setState(() {
        _isImporting = true;
        _errorMessage = null;
      });

      final filePath = result.files.single.path!;
      final importResult = await _importService.importFile(
        filePath,
        widget.projectId!,
      );

      if (mounted) {
        setState(() {
          _isImporting = false;
          if (importResult.success) {
            _isImported = true;
            _importedProjectId = importResult.projectId;
            if (importResult.featureCount == 0 && filePath.toLowerCase().endsWith('.mbtiles')) {
              _successMessage = 'Đã nhập MBTiles làm bản đồ nền offline.';
            } else {
              _successMessage = 'Đã nhập ${importResult.featureCount} đối tượng '
                  'vào ${importResult.layerCount} lớp dữ liệu.';
            }
          } else {
            _errorMessage = importResult.errorMessage;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _errorMessage = 'Lỗi chọn file: $e';
        });
      }
    }
  }

  /// Pick and import a QGIS .qgs project file with associated GPKG layers
  Future<void> _importQgsProject() async {
    if (widget.projectId == null) {
      setState(() {
        _errorMessage = 'Vui lòng mở dự án trước khi nhập dự án QGIS';
      });
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['qgs'],
        dialogTitle: 'Chọn file dự án QGIS (.qgs)',
      );

      if (result == null || result.files.single.path == null) return;

      setState(() {
        _isImporting = true;
        _errorMessage = null;
      });

      final filePath = result.files.single.path!;
      final importResult = await _qfieldImporter.importPackage(
        filePath,
        widget.projectId!,
      );

      if (mounted) {
        setState(() {
          _isImporting = false;
          if (importResult.success) {
            _isImported = true;
            _importedProjectId = importResult.projectId;
            _successMessage = 'Đã nhập ${importResult.layerCount} lớp, '
                '${importResult.featureCount} đối tượng từ dự án QGIS.\n'
                'Layers: ${importResult.importedLayers.join(", ")}';
          } else {
            _errorMessage = importResult.errorMessage;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _errorMessage = 'Lỗi chọn file: $e';
        });
      }
    }
  }

  /// Pick and import a .lvtfield package
  Future<void> _importLvtFieldPackage() async {
    try {
      // Pick a .lvtfield file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['lvtfield', 'zip'],
        dialogTitle: 'Chọn gói LVTField',
      );

      if (result == null || result.files.single.path == null) return;

      setState(() {
        _isImporting = true;
        _errorMessage = null;
      });

      final filePath = result.files.single.path!;
      final importResult = await _importService.importLvtFieldPackage(filePath);

      if (mounted) {
        setState(() {
          _isImporting = false;
          if (importResult.success) {
            _isImported = true;
            _importedProjectId = importResult.projectId;
            _successMessage = 'Đã nhập ${importResult.layerCount} lớp, '
                '${importResult.featureCount} đối tượng.';
          } else {
            _errorMessage = importResult.errorMessage;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _errorMessage = 'Lỗi chọn file: $e';
        });
      }
    }
  }

  /// Navigate to the imported project
  void _navigateToProject() {
    Navigator.pop(context);
    if (_importedProjectId != null) {
      context.go('/map/$_importedProjectId');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isImported) {
      return _buildSuccessDialog();
    }
    return _buildImportDialog();
  }

  Widget _buildImportDialog() {
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
              Icons.download,
              color: AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          const Expanded(
            child: Text(
              'Nhập dữ liệu',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Import GeoJSON option
            _buildImportOption(
              icon: Icons.map_outlined,
              title: 'Nhập GeoJSON',
              subtitle: 'Thêm lớp dữ liệu từ file .geojson',
              enabled: widget.projectId != null && !_isImporting,
              onTap: _importGeoJson,
            ),

            const SizedBox(height: AppSizes.sm),

            // Import KML
            _buildImportOption(
              icon: Icons.public,
              title: 'Nhập KML (Google Earth)',
              subtitle: 'Thêm lớp từ file .kml',
              enabled: widget.projectId != null && !_isImporting,
              onTap: () => _importFormat(['kml'], 'Chọn file KML'),
            ),

            const SizedBox(height: AppSizes.sm),

            // Import KMZ
            _buildImportOption(
              icon: Icons.folder_zip,
              title: 'Nhập KMZ',
              subtitle: 'KML nén (.kmz)',
              enabled: widget.projectId != null && !_isImporting,
              onTap: () => _importFormat(['kmz'], 'Chọn file KMZ'),
            ),

            const SizedBox(height: AppSizes.sm),

            // Import SHP
            _buildImportOption(
              icon: Icons.layers,
              title: 'Nhập Shapefile',
              subtitle: 'ESRI .shp (cần .dbf đi kèm)',
              enabled: widget.projectId != null && !_isImporting,
              onTap: () => _importFormat(['shp'], 'Chọn file .shp'),
            ),

            const SizedBox(height: AppSizes.sm),

            // Import GeoTIFF
            _buildImportOption(
              icon: Icons.image_outlined,
              title: 'Nhập GeoTIFF (ảnh tọa độ)',
              subtitle: 'Ảnh .tif/.tiff có tọa độ hoặc .tfw',
              enabled: widget.projectId != null && !_isImporting,
              onTap: () => _importFormat(['tif', 'tiff'], 'Chọn file GeoTIFF'),
            ),

            const SizedBox(height: AppSizes.sm),

            // Import MBTiles
            _buildImportOption(
              icon: Icons.grid_view,
              title: 'Nhập MBTiles (bản đồ nền)',
              subtitle: 'Tile cache offline .mbtiles',
              enabled: widget.projectId != null && !_isImporting,
              onTap: () => _importFormat(['mbtiles'], 'Chọn file MBTiles'),
            ),

            const SizedBox(height: AppSizes.sm),

            // Import QGIS/QField project
            _buildImportOption(
              icon: Icons.account_tree_outlined,
              title: 'Nhập dự án QGIS / QField',
              subtitle: 'File .qgs kèm GPKG (giữ style, label)',
              enabled: widget.projectId != null && !_isImporting,
              onTap: _importQgsProject,
            ),

            const SizedBox(height: AppSizes.sm),

            // Import LVTField package option
            _buildImportOption(
              icon: Icons.inventory_2_outlined,
              title: 'Nhập gói LVTField',
              subtitle: 'Tạo dự án mới từ file .lvtfield',
              enabled: !_isImporting,
              onTap: _importLvtFieldPackage,
            ),

            // Hint when no project is selected for GeoJSON
            if (widget.projectId == null) ...[
              const SizedBox(height: AppSizes.sm),
              Container(
                padding: const EdgeInsets.all(AppSizes.sm),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: AppColors.info, size: 18),
                    SizedBox(width: AppSizes.xs),
                    Expanded(
                      child: Text(
                        'Mở dự án trước để nhập GeoJSON vào dự án đó.',
                        style: TextStyle(
                          color: AppColors.info,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Progress indicator
            if (_isImporting) ...[
              const SizedBox(height: AppSizes.md),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: AppSizes.sm),
                  Text(
                    'Đang nhập dữ liệu...',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ],

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
      actions: [
        TextButton(
          onPressed: _isImporting ? null : () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    );
  }

  Widget _buildSuccessDialog() {
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
          const Text('Nhập thành công!'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _successMessage ?? 'Đã nhập dữ liệu thành công.',
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
        if (_importedProjectId != null)
          ElevatedButton.icon(
            onPressed: _navigateToProject,
            icon: const Icon(Icons.map, size: 20),
            label: const Text('Mở dự án'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(120, 44),
            ),
          ),
      ],
    );
  }

  Widget _buildImportOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(AppSizes.md),
          decoration: BoxDecoration(
            border: Border.all(
              color: enabled ? AppColors.borderOf(context) : AppColors.dividerOf(context),
            ),
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: enabled
                      ? AppColors.primarySurfaceOf(context)
                      : AppColors.dividerOf(context).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                ),
                child: Icon(
                  icon,
                  color: enabled ? AppColors.primary : AppColors.textSecondaryOf(context),
                  size: 24,
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: enabled
                            ? AppColors.textPrimaryOf(context)
                            : AppColors.textSecondaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: enabled
                            ? AppColors.textSecondaryOf(context)
                            : AppColors.textSecondaryOf(context).withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: enabled ? AppColors.textSecondaryOf(context) : AppColors.dividerOf(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
