import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/app_strings.dart';

/// App settings screen with fully functional menus
/// Author: Lộc Vũ Trung
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _gpsSource = 'GPS nội bộ';
  String _crs = 'WGS 84 (EPSG:4326)';
  String _basemap = 'Google Satellite';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.settings),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.md),
        children: [
          // GPS section
          _SectionHeader(title: 'GPS'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.gps_fixed, color: AppColors.primary),
                  title: const Text('Nguồn GPS'),
                  subtitle: Text(_gpsSource),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showGpsSourceDialog,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.satellite_alt, color: AppColors.primary),
                  title: const Text('Hệ tọa độ'),
                  subtitle: Text(_crs),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showCrsDialog,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSizes.lg),

          // Map section
          _SectionHeader(title: 'Bản đồ'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.map, color: AppColors.primary),
                  title: const Text('Bản đồ nền'),
                  subtitle: Text(_basemap),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showBasemapDialog,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.download, color: AppColors.primary),
                  title: const Text('Tải bản đồ offline'),
                  subtitle: const Text('Import MBTiles từ màn hình chính'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showSnackBar(
                    'Dùng nút Import trên màn hình chính để thêm file .mbtiles',
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSizes.lg),

          // Data section
          _SectionHeader(title: 'Dữ liệu'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined,
                      color: AppColors.primary),
                  title: const Text('Xem tất cả ảnh'),
                  subtitle: const Text('Ảnh đã chụp trong tất cả dự án'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showSnackBar(
                    'Tính năng Gallery sẽ có trong phiên bản tiếp theo',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.storage_outlined,
                      color: AppColors.primary),
                  title: const Text('Sao lưu dữ liệu'),
                  subtitle: const Text('Vị trí cơ sở dữ liệu'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showBackupInfo,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSizes.lg),

          // About section
          _SectionHeader(title: 'Thông tin'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.forest,
                        color: AppColors.primary, size: 22),
                  ),
                  title: const Text(AppStrings.appName),
                  subtitle: const Text('Phiên bản 1.0.0 (Build 1)'),
                  onTap: () => _showAboutDialog(),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.person_outline,
                      color: AppColors.primary),
                  title: const Text('Tác giả'),
                  subtitle: const Text('Lộc Vũ Trung'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/author'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.description_outlined,
                      color: AppColors.primary),
                  title: const Text('Giấy phép mã nguồn'),
                  subtitle: const Text('Xem giấy phép các thư viện'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: AppStrings.appName,
                    applicationVersion: '1.0.0',
                    applicationLegalese: '© 2024 Lộc Vũ Trung',
                    applicationIcon: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.forest,
                          color: AppColors.primary, size: 48),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Dialogs
  // ---------------------------------------------------------------------------

  void _showGpsSourceDialog() {
    final options = ['GPS nội bộ', 'GNSS qua Bluetooth', 'Mock GPS (test)'];
    _showSelectionDialog(
      title: 'Nguồn GPS',
      icon: Icons.gps_fixed,
      options: options,
      currentValue: _gpsSource,
      onSelected: (val) => setState(() => _gpsSource = val),
    );
  }

  void _showCrsDialog() {
    final options = [
      'WGS 84 (EPSG:4326)',
      'VN-2000 / TM3 (EPSG:9210)',
      'VN-2000 / UTM zone 48N (EPSG:3405)',
      'WGS 84 / UTM zone 48N (EPSG:32648)',
    ];
    _showSelectionDialog(
      title: 'Hệ tọa độ',
      icon: Icons.satellite_alt,
      options: options,
      currentValue: _crs,
      onSelected: (val) => setState(() => _crs = val),
    );
  }

  void _showBasemapDialog() {
    final options = [
      'OpenStreetMap',
      'Google Satellite',
      'Google Terrain',
      'Google Hybrid',
    ];
    _showSelectionDialog(
      title: 'Bản đồ nền',
      icon: Icons.map,
      options: options,
      currentValue: _basemap,
      onSelected: (val) => setState(() => _basemap = val),
    );
  }

  void _showSelectionDialog({
    required String title,
    required IconData icon,
    required List<String> options,
    required String currentValue,
    required void Function(String) onSelected,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((option) {
            final isSelected = option == currentValue;
            return RadioListTile<String>(
              value: option,
              groupValue: currentValue,
              title: Text(
                option,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              activeColor: AppColors.primary,
              onChanged: (val) {
                if (val != null) {
                  onSelected(val);
                  Navigator.pop(ctx);
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showBackupInfo() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.storage, color: AppColors.primary),
            SizedBox(width: 8),
            Text('Cơ sở dữ liệu'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dữ liệu được lưu trong SQLite database nội bộ.',
              style: TextStyle(fontSize: 14),
            ),
            SizedBox(height: 12),
            Text(
              'Để sao lưu, sử dụng chức năng "Xuất dữ liệu" từ '
              'danh sách dự án với định dạng .lvtfield.',
              style: TextStyle(fontSize: 14),
            ),
            SizedBox(height: 12),
            Text(
              'File: lvtfield.db\nVị trí: Documents/LVTField/',
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AboutDialog(
        applicationName: AppStrings.appName,
        applicationVersion: '1.0.0',
        applicationLegalese: '© 2024 Lộc Vũ Trung',
        applicationIcon: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primarySurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.forest, color: AppColors.primary, size: 32),
        ),
        children: const [
          Text(
            'LVTField là ứng dụng GIS di động chuyên dụng cho '
            'khảo sát rừng và thu thập dữ liệu không gian.',
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ));
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
