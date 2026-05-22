import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Author profile page - inspired by LVT4U
/// Author: Lộc Vũ Trung
class AuthorPage extends StatelessWidget {
  const AuthorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Gradient header with avatar
          SliverAppBar(
            expandedHeight: 240,
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
                      const SizedBox(height: 20),
                      // Avatar circle
                      Container(
                        width: 90,
                        height: 90,
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
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Lộc Vũ Trung',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'GIS Developer & Forest Engineer',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w400,
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
                  // Contact card
                  _buildSectionTitle('Liên hệ'),
                  Card(
                    child: Column(
                      children: [
                        _buildContactTile(
                          Icons.email_outlined,
                          'Email',
                          'locvutrung@lvt4u.com',
                        ),
                        const Divider(height: 1),
                        _buildContactTile(
                          Icons.phone_outlined,
                          'Điện thoại',
                          '+84 xxx xxx xxx',
                        ),
                        const Divider(height: 1),
                        _buildContactTile(
                          Icons.language,
                          'Website',
                          'https://lvt4u.com',
                        ),
                        const Divider(height: 1),
                        _buildContactTile(
                          Icons.business_outlined,
                          'Đơn vị',
                          'LVT4U - Giải pháp GIS Lâm nghiệp',
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
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: AppColors.primarySurface,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.forest,
                                  color: AppColors.primary,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'LVTField',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'Phiên bản 1.0.0 (Build 1)',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'LVTField là ứng dụng GIS di động chuyên dụng cho '
                            'khảo sát rừng và thu thập dữ liệu không gian. '
                            'Hỗ trợ GPS GNSS, vẽ điểm/đường/vùng, quản lý '
                            'lớp dữ liệu, chụp ảnh hiện trường, và xuất nhập '
                            'dữ liệu đa định dạng.',
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _buildTechChip('Flutter'),
                              _buildTechChip('Dart'),
                              _buildTechChip('SQLite'),
                              _buildTechChip('flutter_map'),
                              _buildTechChip('Geolocator'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Social links
                  _buildSectionTitle('Mạng xã hội'),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildSocialButton(Icons.code, 'GitHub', const Color(0xFF333333)),
                      const SizedBox(width: 16),
                      _buildSocialButton(Icons.facebook, 'Facebook', const Color(0xFF1877F2)),
                      const SizedBox(width: 16),
                      _buildSocialButton(Icons.email, 'Email', AppColors.primary),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Copyright
                  Center(
                    child: Text(
                      '© 2024 Lộc Vũ Trung. All rights reserved.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary.withValues(alpha: 0.6),
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

  Widget _buildContactTile(IconData icon, String label, String value) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary, size: 22),
      title: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      subtitle: Text(
        value,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
      ),
      dense: true,
    );
  }

  static Widget _buildTechChip(String label) {
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
      backgroundColor: AppColors.primarySurface,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildSocialButton(IconData icon, String label, Color color) {
    return Column(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 26),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
