import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/services/team_service.dart';
import '../../core/services/live_tracking_service.dart';
import '../../core/services/gps_service.dart';

/// Team Management Screen - Nhóm tuần tra
/// Author: Lộc Vũ Trung
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  final _teamService = TeamService();
  final _liveTracking = LiveTrackingService();

  final _emailController = TextEditingController(text: 'locvutrung@gmail.com');
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  bool _isLoggedIn = false;
  bool _isLoading = false;
  List<TeamInfo> _teams = [];
  String? _expandedTeamId; // show members for this team
  List<TeamMember> _expandedMembers = [];
  String? _sharingTeamId; // currently sharing position for this team

  String? _statusMessage;
  bool _statusSuccess = false;

  // Theme colors (matching sync_screen style)
  static const _primaryGreen = Color(0xFF2E7D32);
  static const _accentOrange = Color(0xFFE65100);

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _setStatus('Vui lòng nhập email và mật khẩu', false);
      return;
    }

    setState(() => _isLoading = true);

    final success = await _teamService.login(email, password);

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _isLoggedIn = success;
    });

    if (success) {
      _setStatus('Đăng nhập thành công!', true);
      await _loadTeams();
    } else {
      _setStatus('Đăng nhập thất bại. Kiểm tra lại email/mật khẩu.', false);
    }
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đăng xuất'),
        content: const Text('Bạn có chắc muốn đăng xuất?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _teamService.pb.authStore.clear();
              setState(() {
                _isLoggedIn = false;
                _teams = [];
                _expandedTeamId = null;
                _expandedMembers = [];
                _sharingTeamId = null;
              });
              _setStatus('Đã đăng xuất', false);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Teams CRUD
  // ---------------------------------------------------------------------------

  Future<void> _loadTeams() async {
    setState(() => _isLoading = true);
    final teams = await _teamService.getMyTeams();
    if (!mounted) return;
    setState(() {
      _teams = teams;
      _isLoading = false;
    });
  }

  Future<void> _createTeam() async {
    final nameController = TextEditingController();
    final orgController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.group_add, color: _primaryGreen, size: 24),
            SizedBox(width: 8),
            Text('Tạo nhóm mới'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Tên nhóm',
                prefixIcon: const Icon(Icons.label_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: orgController,
              decoration: InputDecoration(
                labelText: 'Tổ chức (tùy chọn)',
                prefixIcon: const Icon(Icons.business_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryGreen,
              foregroundColor: Colors.white,
            ),
            child: const Text('Tạo'),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      setState(() => _isLoading = true);
      final team = await _teamService.createTeam(
        nameController.text.trim(),
        orgController.text.trim(),
      );
      if (!mounted) return;
      if (team != null) {
        _setStatus('Đã tạo nhóm "${team.name}" · Mã: ${team.code}', true);
        await _loadTeams();
      } else {
        setState(() => _isLoading = false);
        _setStatus('Không thể tạo nhóm', false);
      }
    }

    nameController.dispose();
    orgController.dispose();
  }

  Future<void> _joinTeam() async {
    final codeController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.link, color: _primaryGreen, size: 24),
            SizedBox(width: 8),
            Text('Tham gia nhóm'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Nhập mã mời từ trưởng nhóm',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              decoration: InputDecoration(
                labelText: 'Mã nhóm',
                prefixIcon: const Icon(Icons.vpn_key_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                counterText: '',
              ),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryGreen,
              foregroundColor: Colors.white,
            ),
            child: const Text('Tham gia'),
          ),
        ],
      ),
    );

    if (result == true && codeController.text.trim().isNotEmpty) {
      setState(() => _isLoading = true);
      final success = await _teamService.joinTeam(codeController.text.trim());
      if (!mounted) return;
      if (success) {
        _setStatus('Đã tham gia nhóm thành công!', true);
        await _loadTeams();
      } else {
        setState(() => _isLoading = false);
        _setStatus('Không tìm thấy nhóm với mã này', false);
      }
    }

    codeController.dispose();
  }

  Future<void> _leaveTeam(String teamId, String teamName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rời nhóm'),
        content: Text('Bạn có chắc muốn rời nhóm "$teamName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Rời nhóm'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Stop sharing if active for this team
      if (_sharingTeamId == teamId) {
        await _liveTracking.stopSharing();
        _sharingTeamId = null;
      }

      setState(() => _isLoading = true);
      final success = await _teamService.leaveTeam(teamId);
      if (!mounted) return;
      if (success) {
        _setStatus('Đã rời nhóm "$teamName"', true);
        if (_expandedTeamId == teamId) {
          _expandedTeamId = null;
          _expandedMembers = [];
        }
        await _loadTeams();
      } else {
        setState(() => _isLoading = false);
        _setStatus('Không thể rời nhóm', false);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Live Tracking
  // ---------------------------------------------------------------------------

  Future<void> _toggleSharing(String teamId) async {
    if (_sharingTeamId == teamId) {
      // Stop sharing
      await _liveTracking.stopSharing();
      setState(() => _sharingTeamId = null);
      _setStatus('Đã dừng chia sẻ vị trí', true);
    } else {
      // Stop any existing sharing first
      if (_sharingTeamId != null) {
        await _liveTracking.stopSharing();
      }

      // Start GPS tracking if not active
      final gps = GpsService();
      await gps.startTracking();

      // Start sharing for this team
      await _liveTracking.startSharing(teamId);
      setState(() => _sharingTeamId = teamId);
      _setStatus('Đang chia sẻ vị trí trong nhóm', true);
    }
  }

  // ---------------------------------------------------------------------------
  // Expand / Members
  // ---------------------------------------------------------------------------

  Future<void> _expandTeam(String teamId) async {
    if (_expandedTeamId == teamId) {
      // Collapse
      setState(() {
        _expandedTeamId = null;
        _expandedMembers = [];
      });
      return;
    }

    setState(() {
      _expandedTeamId = teamId;
      _isLoading = true;
    });

    final members = await _teamService.getTeamMembers(teamId);
    if (!mounted) return;
    setState(() {
      _expandedMembers = members;
      _isLoading = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _setStatus(String msg, bool success) {
    setState(() {
      _statusMessage = msg;
      _statusSuccess = success;
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        title: const Text(
          'Nhóm tuần tra',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        elevation: 0,
        actions: _isLoggedIn
            ? [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Tải lại',
                  onPressed: _isLoading ? null : _loadTeams,
                ),
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Đăng xuất',
                  onPressed: _logout,
                ),
              ]
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header icon
            const SizedBox(height: 8),
            Icon(
              Icons.groups_rounded,
              size: 64,
              color: AppColors.primary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 8),
            Text(
              'Quản lý nhóm và chia sẻ vị trí',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
            const SizedBox(height: 24),

            // Auth section
            if (!_isLoggedIn) ...[
              _buildLoginCard(),
            ] else ...[
              _buildUserCard(),
              const SizedBox(height: 16),
              _buildTeamsSection(),
              const SizedBox(height: 16),
              _buildActionButtons(),
              if (_expandedTeamId != null) ...[
                const SizedBox(height: 16),
                _buildMembersSection(),
              ],
            ],

            // Status message
            if (_statusMessage != null) ...[
              const SizedBox(height: 16),
              _buildStatusCard(),
            ],

            // Loading
            if (_isLoading) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Login Card
  // ---------------------------------------------------------------------------

  Widget _buildLoginCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.lock_outline,
              size: 56,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            const Text(
              'Đăng nhập PocketBase',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Nhập email và mật khẩu tài khoản LVTField',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
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
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onSubmitted: (_) => _login(),
            ),
            const SizedBox(height: 20),

            // Login button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _login,
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

  // ---------------------------------------------------------------------------
  // User Card (after login)
  // ---------------------------------------------------------------------------

  Widget _buildUserCard() {
    final name = _teamService.pb.authStore.record?.getStringValue('name') ??
        'Người dùng';
    final email =
        _teamService.pb.authStore.record?.getStringValue('email') ?? '';

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
                name.isNotEmpty ? name[0].toUpperCase() : 'U',
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
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondaryOf(context),
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
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Teams Section
  // ---------------------------------------------------------------------------

  Widget _buildTeamsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Icon(Icons.list_alt, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Nhóm của tôi',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              const Spacer(),
              Text(
                '${_teams.length} nhóm',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
            ],
          ),
        ),

        if (_teams.isEmpty && !_isLoading)
          Card(
            elevation: 0,
            color: AppColors.primarySurfaceOf(context),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Bạn chưa tham gia nhóm nào.\nTạo nhóm mới hoặc tham gia bằng mã mời.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ),
          ),

        // Team cards
        ..._teams.map((team) => _buildTeamCard(team)),
      ],
    );
  }

  Widget _buildTeamCard(TeamInfo team) {
    final isExpanded = _expandedTeamId == team.id;
    final isSharing = _sharingTeamId == team.id;
    final isOwner = team.ownerId == _teamService.currentUserId;

    return Card(
      elevation: isExpanded ? 3 : 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isSharing
              ? _primaryGreen.withValues(alpha: 0.6)
              : isExpanded
                  ? AppColors.primary.withValues(alpha: 0.3)
                  : AppColors.borderOf(context),
          width: isSharing ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _expandTeam(team.id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Team name row
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primarySurfaceOf(context),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.groups,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          team.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              'Mã: ${team.code}',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondaryOf(context),
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (team.org.isNotEmpty) ...[
                              Text(
                                ' · ${team.org}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondaryOf(context),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Expand indicator
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ],
              ),

              // Actions row
              const SizedBox(height: 10),
              Row(
                children: [
                  // Copy code button
                  _SmallActionChip(
                    icon: Icons.copy,
                    label: 'Mã',
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: team.code));
                      _setStatus(
                          'Đã sao chép mã nhóm: ${team.code}', true);
                    },
                  ),
                  const SizedBox(width: 8),
                  // Share location toggle
                  _SmallActionChip(
                    icon: isSharing
                        ? Icons.location_on
                        : Icons.location_off_outlined,
                    label: isSharing ? 'Đang chia sẻ' : 'Chia sẻ vị trí',
                    isActive: isSharing,
                    onTap: () => _toggleSharing(team.id),
                  ),
                  const Spacer(),
                  // Leave team
                  if (!isOwner)
                    _SmallActionChip(
                      icon: Icons.exit_to_app,
                      label: 'Rời',
                      isDestructive: true,
                      onTap: () => _leaveTeam(team.id, team.name),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Action Buttons (Create / Join)
  // ---------------------------------------------------------------------------

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _isLoading ? null : _createTeam,
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Tạo nhóm'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isLoading ? null : _joinTeam,
            icon: const Icon(Icons.link, size: 20),
            label: const Text('Tham gia'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Members Section (expandable)
  // ---------------------------------------------------------------------------

  Widget _buildMembersSection() {
    final teamName =
        _teams.where((t) => t.id == _expandedTeamId).firstOrNull?.name ??
            'Nhóm';

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.people, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Thành viên — $teamName',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_expandedMembers.length} người',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 4),

            if (_expandedMembers.isEmpty && !_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'Không có thành viên',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ),

            // Member list
            ..._expandedMembers.map((m) => _buildMemberTile(m)),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberTile(TeamMember member) {
    final isLeader = member.role == 'leader';
    final isOnline = member.isActive;
    final isMe = member.userId == _teamService.currentUserId;

    final name = member.userName ?? member.userEmail ?? member.userId;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 18,
            backgroundColor: isLeader
                ? _accentOrange.withValues(alpha: 0.15)
                : AppColors.primarySurfaceOf(context),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isLeader ? _accentOrange : AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Name + status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              isMe ? FontWeight.w700 : FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isMe)
                      const Text(
                        ' (Bạn)',
                        style: TextStyle(
                          fontSize: 12,
                          color: _primaryGreen,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    // Role badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: isLeader
                            ? _accentOrange.withValues(alpha: 0.12)
                            : AppColors.borderOf(context),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isLeader ? 'Trưởng nhóm' : 'Thành viên',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isLeader
                              ? _accentOrange
                              : AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Online status
                    Icon(
                      Icons.circle,
                      size: 8,
                      color: isOnline ? _primaryGreen : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                        fontSize: 11,
                        color: isOnline ? _primaryGreen : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Status Card
  // ---------------------------------------------------------------------------

  Widget _buildStatusCard() {
    return Card(
      elevation: 1,
      color: _statusSuccess
          ? _primaryGreen.withValues(alpha: 0.05)
          : _accentOrange.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _statusSuccess
              ? _primaryGreen.withValues(alpha: 0.3)
              : _accentOrange.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              _statusSuccess
                  ? Icons.check_circle
                  : Icons.warning_amber_rounded,
              color: _statusSuccess ? _primaryGreen : _accentOrange,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _statusMessage ?? '',
                style: TextStyle(
                  fontSize: 13,
                  color: _statusSuccess ? _primaryGreen : _accentOrange,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Small Action Chip widget
// =============================================================================

class _SmallActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;
  final bool isDestructive;

  const _SmallActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive
        ? Colors.red
        : isActive
            ? const Color(0xFF2E7D32)
            : AppColors.textSecondaryOf(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF2E7D32).withValues(alpha: 0.1)
              : isDestructive
                  ? Colors.red.withValues(alpha: 0.06)
                  : AppColors.borderOf(context).withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? const Color(0xFF2E7D32).withValues(alpha: 0.4)
                : isDestructive
                    ? Colors.red.withValues(alpha: 0.3)
                    : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
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
