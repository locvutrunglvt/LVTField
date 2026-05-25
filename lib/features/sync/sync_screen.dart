import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/services/sync_service.dart';

/// LVT Sync Screen - Cloud synchronization management
/// Author: Lộc Vũ Trung
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen>
    with SingleTickerProviderStateMixin {
  final SyncService _syncService = SyncService();
  bool _isLoading = false;
  String? _statusMessage;
  bool _syncSuccess = false;
  late AnimationController _syncIconController;

  // Login form
  final _emailController = TextEditingController(text: 'locvutrung@gmail.com');
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  // Theme colors
  static const _primaryGreen = Color(0xFF2E7D32);
  static const _accentOrange = Color(0xFFE65100);

  @override
  void initState() {
    super.initState();
    _syncIconController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void dispose() {
    _syncIconController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Handle email/password login
  Future<void> _handleEmailLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _statusMessage = 'Vui lòng nhập email và mật khẩu';
        _syncSuccess = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    final success = await _syncService.loginWithEmail(email, password);

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (success) {
        _statusMessage = 'Đăng nhập thành công!';
        _syncSuccess = true;
      } else {
        _statusMessage =
            'Đăng nhập thất bại: ${_syncService.lastError ?? "Sai email hoặc mật khẩu"}';
        _syncSuccess = false;
      }
    });
  }

  /// Handle sync
  Future<void> _handleSync() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Đang đồng bộ...';
      _syncSuccess = true;
    });
    _syncIconController.repeat();

    final result = await _syncService.syncAll();

    if (!mounted) return;
    _syncIconController.stop();
    _syncIconController.reset();
    setState(() {
      _isLoading = false;
      _statusMessage = result.message;
      _syncSuccess = result.success;
    });
  }

  /// Handle logout
  void _handleLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đăng xuất'),
        content: const Text('Bạn có chắc muốn đăng xuất khỏi LVT Sync?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _syncService.logout();
              setState(() {
                _statusMessage = 'Đã đăng xuất';
                _syncSuccess = false;
              });
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'LVT Sync',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: _primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header icon
            const SizedBox(height: 8),
            Icon(
              Icons.cloud_sync_rounded,
              size: 64,
              color: _primaryGreen.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 8),
            Text(
              'Đồng bộ dữ liệu đám mây',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 24),

            // Auth section
            if (!_syncService.isAuthenticated) ...[
              _buildLoginCard(),
            ] else ...[
              _buildUserCard(),
              const SizedBox(height: 16),
              _buildSyncCard(),
            ],

            // Status message
            if (_statusMessage != null) ...[
              const SizedBox(height: 16),
              _buildStatusCard(),
            ],

            // Loading indicator
            if (_isLoading) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],



          ],
        ),
      ),
    );
  }

  /// Login card with Email/Password form
  Widget _buildLoginCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.account_circle_outlined,
              size: 56,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            const Text(
              'Đăng nhập để đồng bộ',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Nhập email và mật khẩu tài khoản LVTField',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 20),

            // Email field
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email',
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
              ),
            ),
            const SizedBox(height: 12),

            // Password field
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Mật khẩu',
                prefixIcon: const Icon(Icons.lock_outlined),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off
                        : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
              ),
              onSubmitted: (_) => _handleEmailLogin(),
            ),
            const SizedBox(height: 20),

            // Login button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _handleEmailLogin,
                icon: const Icon(Icons.login, size: 22),
                label: const Text(
                  'Đăng nhập',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryGreen,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// User info card (after login)
  Widget _buildUserCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 28,
              backgroundColor: _primaryGreen.withValues(alpha: 0.1),
              child: Text(
                (_syncService.currentUserName ?? 'U')
                    .substring(0, 1)
                    .toUpperCase(),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: _primaryGreen,
                ),
              ),
            ),
            const SizedBox(width: 16),
            // User info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _syncService.currentUserName ?? 'Người dùng',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _syncService.currentUserEmail ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _primaryGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '✓ Đã kết nối',
                      style: TextStyle(
                        fontSize: 11,
                        color: _primaryGreen,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Logout button
            IconButton(
              onPressed: _handleLogout,
              icon: const Icon(Icons.logout, color: Colors.red),
              tooltip: 'Đăng xuất',
            ),
          ],
        ),
      ),
    );
  }

  /// Sync action card
  Widget _buildSyncCard() {
    final lastSync = _syncService.lastSyncTime;
    final lastSyncText = lastSync != null
        ? DateFormat('HH:mm:ss - dd/MM/yyyy').format(lastSync)
        : 'Chưa đồng bộ';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Sync button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _handleSync,
                icon: RotationTransition(
                  turns: _syncIconController,
                  child: const Icon(Icons.cloud_sync, size: 24),
                ),
                label: Text(
                  _isLoading ? 'Đang đồng bộ...' : 'Đồng bộ ngay',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryGreen,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Last sync info
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: Colors.grey.shade500),
                const SizedBox(width: 8),
                Text(
                  'Lần đồng bộ cuối: $lastSyncText',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Status message card
  Widget _buildStatusCard() {
    return Card(
      elevation: 1,
      color: _syncSuccess
          ? _primaryGreen.withValues(alpha: 0.05)
          : _accentOrange.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _syncSuccess
              ? _primaryGreen.withValues(alpha: 0.3)
              : _accentOrange.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              _syncSuccess ? Icons.check_circle : Icons.warning_amber_rounded,
              color: _syncSuccess ? _primaryGreen : _accentOrange,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _statusMessage ?? '',
                style: TextStyle(
                  fontSize: 13,
                  color: _syncSuccess
                      ? _primaryGreen
                      : _accentOrange,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Info card about sync
  Widget _buildInfoCard() {
    return Card(
      elevation: 0,
      color: Colors.blue.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'Thông tin đồng bộ',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _infoRow('Máy chủ', 'lvtfield.lvtcenter.it.com'),
            _infoRow('Dữ liệu', 'Dự án, lớp, đối tượng'),
            _infoRow('Xác thực', 'Email / Mật khẩu'),
            _infoRow('Phiên bản', '2.4.1'),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
