import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';

/// Author profile page with clickable contact links
/// Author: Lộc Vũ Trung
class AuthorPage extends StatefulWidget {
  const AuthorPage({super.key});

  @override
  State<AuthorPage> createState() => _AuthorPageState();
}

class _AuthorPageState extends State<AuthorPage> {
  String _versionText = '...';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _versionText = 'v${info.version} (Build ${info.buildNumber})');
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Gradient header with avatar
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF1B4332),
                      Color(0xFF2D6A4F),
                      Color(0xFF40916C),
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 16),
                      // Avatar circle
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.2),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.5),
                            width: 3,
                          ),
                        ),
                        child: const Center(
                          child: Text(
                            'LVT',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Lộc Vũ Trung',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'GIS Developer & Forest Engineer',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Contact card - all clickable
                  _buildSectionTitle('Liên hệ'),
                  Card(
                    child: Column(
                      children: [
                        _buildContactLink(
                          Icons.email_outlined,
                          'Email',
                          'Locvutrung@gmail.com',
                          () => _launchUrl('mailto:Locvutrung@gmail.com'),
                        ),
                        const Divider(height: 1),
                        _buildContactLink(
                          Icons.phone_outlined,
                          'Zalo / Phone',
                          '+84 913 191 178',
                          () => _launchUrl('tel:+84913191178'),
                        ),
                        const Divider(height: 1),
                        _buildContactLink(
                          Icons.message_outlined,
                          'WhatsApp',
                          '+84 913 191 178',
                          () => _launchUrl('https://wa.me/84913191178'),
                        ),
                        const Divider(height: 1),
                        _buildContactLink(
                          Icons.facebook,
                          'Facebook',
                          'facebook.com/locvutrung',
                          () => _launchUrl('https://www.facebook.com/locvutrung'),
                        ),
                        const Divider(height: 1),
                        _buildContactLink(
                          Icons.language,
                          'Website',
                          'locvutrung.lvtcenter.it.com',
                          () => _launchUrl('https://locvutrung.lvtcenter.it.com'),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(Icons.business_outlined,
                              color: isDark ? AppColors.primaryLight : AppColors.primary, size: 22),
                          title: Text('Đơn vị',
                              style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : AppColors.textSecondary)),
                          subtitle: Text(
                            'LVT Center - Giải pháp GIS Lâm nghiệp',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white : AppColors.textPrimary,
                            ),
                          ),
                          dense: true,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // App info card
                  _buildSectionTitle('Ứng dụng'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColors.primaryLight.withValues(alpha: 0.15)
                                      : AppColors.primarySurface,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(Icons.forest,
                                    color: isDark ? AppColors.primaryLight : AppColors.primary, size: 26),
                              ),
                              const SizedBox(width: 12),
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'LVTField',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: (isDark ? AppColors.primaryLight : AppColors.primary).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _versionText,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? AppColors.primaryLight : AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'LVTField là ứng dụng GIS di động chuyên dụng cho '
                            'khảo sát rừng và thu thập dữ liệu không gian. '
                            'Hỗ trợ GPS GNSS, vẽ điểm/đường/vùng, quản lý '
                            'lớp dữ liệu, chụp ảnh hiện trường, và xuất nhập '
                            'dữ liệu đa định dạng.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: isDark ? Colors.white60 : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _buildTechChip('Flutter', isDark),
                              _buildTechChip('Dart', isDark),
                              _buildTechChip('SQLite', isDark),
                              _buildTechChip('flutter_map', isDark),
                              _buildTechChip('Geolocator', isDark),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Copyright
                  Center(
                    child: Text(
                      '© 2024 Lộc Vũ Trung. All rights reserved.',
                      style: TextStyle(
                        fontSize: 12,
                        color: (isDark ? Colors.white : AppColors.textSecondary).withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }

  /// Clickable contact tile — opens link on tap
  Widget _buildContactLink(IconData icon, String label, String value, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final linkColor = isDark ? const Color(0xFF64B5F6) : const Color(0xFF1565C0);

    return ListTile(
      leading: Icon(icon, color: isDark ? AppColors.primaryLight : AppColors.primary, size: 22),
      title: Text(label,
          style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : AppColors.textSecondary)),
      subtitle: Text(
        value,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: linkColor,
          decoration: TextDecoration.underline,
          decorationColor: linkColor.withValues(alpha: 0.4),
        ),
      ),
      trailing: Icon(Icons.open_in_new, size: 16, color: linkColor.withValues(alpha: 0.6)),
      dense: true,
      onTap: onTap,
    );
  }

  Widget _buildTechChip(String label, bool isDark) {
    return Chip(
      label: Text(label, style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: isDark ? Colors.white70 : null,
      )),
      backgroundColor: isDark
          ? AppColors.primaryLight.withValues(alpha: 0.1)
          : AppColors.primarySurface,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}
