import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/app_strings.dart';
import '../../app.dart';

/// App settings screen with fully functional menus
/// Author: Lộc Vũ Trung
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _gpsSource = 'GPS nội bộ';


  // Dynamic version info
  String _version = '';
  String _buildNumber = '';

  @override
  void initState() {
    super.initState();
    _loadVersionInfo();
  }

  Future<void> _loadVersionInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _version = info.version;
        _buildNumber = info.buildNumber;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final versionText = _version.isEmpty ? '...' : 'v$_version (Build $_buildNumber)';
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.settings),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.md),
        children: [
          // Appearance section
          _SectionHeader(title: 'Giao diện'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    LVTFieldApp.currentThemeMode == ThemeMode.dark
                        ? Icons.dark_mode
                        : LVTFieldApp.currentThemeMode == ThemeMode.light
                            ? Icons.light_mode
                            : Icons.brightness_auto,
                    color: AppColors.primary,
                  ),
                  title: const Text('Chế độ hiển thị'),
                  subtitle: Text(_themeModeLabel(LVTFieldApp.currentThemeMode)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showThemeModeDialog,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSizes.lg),

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

          // Help section
          _SectionHeader(title: 'Hỗ trợ'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primarySurfaceOf(context),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.menu_book,
                        color: AppColors.primary, size: 22),
                  ),
                  title: const Text('Hướng dẫn sử dụng'),
                  subtitle: const Text('Tìm hiểu tất cả tính năng'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/help'),
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
                      color: AppColors.primarySurfaceOf(context),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.forest,
                        color: AppColors.primary, size: 22),
                  ),
                  title: const Text(AppStrings.appName),
                  subtitle: Text('Phiên bản $versionText'),
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
                    applicationVersion: _version,
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dữ liệu được lưu trong SQLite database nội bộ.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            const Text(
              'Để sao lưu, sử dụng chức năng "Xuất dữ liệu" từ '
              'danh sách dự án với định dạng .lvtfield.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Text(
              'File: lvtfield.db\nVị trí: Documents/LVTField/',
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: AppColors.textSecondaryOf(context),
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
        applicationVersion: _version,
        applicationLegalese: '© 2024 Lộc Vũ Trung',
        applicationIcon: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primarySurfaceOf(context),
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

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Sáng';
      case ThemeMode.dark:
        return 'Tối';
      case ThemeMode.system:
        return 'Theo hệ thống';
    }
  }

  void _showThemeModeDialog() {
    final current = LVTFieldApp.currentThemeMode;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.palette, color: AppColors.primary, size: 24),
            SizedBox(width: 8),
            Text('Chế độ hiển thị'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _themeRadio(ctx, ThemeMode.system, 'Theo hệ thống', Icons.brightness_auto, current),
            _themeRadio(ctx, ThemeMode.light, 'Sáng', Icons.light_mode, current),
            _themeRadio(ctx, ThemeMode.dark, 'Tối', Icons.dark_mode, current),
          ],
        ),
      ),
    );
  }

  Widget _themeRadio(BuildContext ctx, ThemeMode mode, String label, IconData icon, ThemeMode current) {
    return RadioListTile<ThemeMode>(
      value: mode,
      groupValue: current,
      title: Row(
        children: [
          Icon(icon, size: 20, color: mode == current ? AppColors.primary : AppColors.textSecondaryOf(context)),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontWeight: mode == current ? FontWeight.w600 : FontWeight.normal)),
        ],
      ),
      activeColor: AppColors.primary,
      onChanged: (val) {
        if (val != null) {
          LVTFieldApp.setThemeMode(val);
          setState(() {});
          Navigator.pop(ctx);
        }
      },
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
