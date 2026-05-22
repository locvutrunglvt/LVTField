import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/services/auth_service.dart';

/// Login/Register screen for LVTField
/// Author: Lộc Vũ Trung
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _authService = AuthService();

  // Login form
  final _loginUsernameController = TextEditingController();
  final _loginPasswordController = TextEditingController();

  // Register form
  final _regFullNameController = TextEditingController();
  final _regUsernameController = TextEditingController();
  final _regPasswordController = TextEditingController();
  final _regConfirmPasswordController = TextEditingController();
  final _regOrganizationController = TextEditingController();

  bool _isLoading = false;
  bool _obscureLogin = true;
  bool _obscureReg = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginUsernameController.dispose();
    _loginPasswordController.dispose();
    _regFullNameController.dispose();
    _regUsernameController.dispose();
    _regPasswordController.dispose();
    _regConfirmPasswordController.dispose();
    _regOrganizationController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final username = _loginUsernameController.text.trim();
    final password = _loginPasswordController.text;

    if (username.isEmpty || password.isEmpty) {
      _showError('Vui lòng nhập tên đăng nhập và mật khẩu');
      return;
    }

    setState(() => _isLoading = true);

    final user = await _authService.login(username, password);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (user != null) {
      _showSuccess('Xin chào, ${user.displayName}!');
      context.go('/');
    } else {
      _showError('Sai tên đăng nhập hoặc mật khẩu');
    }
  }

  Future<void> _handleRegister() async {
    final fullName = _regFullNameController.text.trim();
    final username = _regUsernameController.text.trim();
    final password = _regPasswordController.text;
    final confirmPassword = _regConfirmPasswordController.text;
    final organization = _regOrganizationController.text.trim();

    if (fullName.isEmpty || username.isEmpty || password.isEmpty) {
      _showError('Vui lòng điền đầy đủ thông tin bắt buộc');
      return;
    }

    if (username.length < 3) {
      _showError('Tên đăng nhập phải có ít nhất 3 ký tự');
      return;
    }

    if (password.length < 4) {
      _showError('Mật khẩu phải có ít nhất 4 ký tự');
      return;
    }

    if (password != confirmPassword) {
      _showError('Mật khẩu xác nhận không khớp');
      return;
    }

    setState(() => _isLoading = true);

    final user = await _authService.register(
      username: username,
      password: password,
      fullName: fullName,
      organization: organization.isNotEmpty ? organization : null,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (user != null) {
      _showSuccess('Đăng ký thành công! Xin chào, ${user.displayName}!');
      context.go('/');
    } else {
      _showError('Tên đăng nhập đã tồn tại');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.primaryDark, AppColors.primary, AppColors.primaryLight],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSizes.lg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.forest,
                      size: 60,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: AppSizes.md),

                  // App name
                  const Text(
                    'LVTField',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: AppSizes.xs),
                  Text(
                    'Khảo sát rừng di động',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  const SizedBox(height: AppSizes.xl),

                  // Login/Register card
                  Container(
                    constraints: const BoxConstraints(maxWidth: 420),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Tab bar
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.primarySurface,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(AppSizes.radiusLg),
                            ),
                          ),
                          child: TabBar(
                            controller: _tabController,
                            indicatorColor: AppColors.primary,
                            indicatorWeight: 3,
                            labelColor: AppColors.primary,
                            unselectedLabelColor: AppColors.textSecondary,
                            labelStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            tabs: const [
                              Tab(text: 'Đăng nhập'),
                              Tab(text: 'Đăng ký'),
                            ],
                          ),
                        ),

                        // Tab content
                        SizedBox(
                          height: _tabController.index == 1 ? 420 : 280,
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildLoginForm(),
                              _buildRegisterForm(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSizes.xl),

                  // Footer
                  Text(
                    'Phát triển bởi Lộc Vũ Trung',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Padding(
      padding: const EdgeInsets.all(AppSizes.lg),
      child: Column(
        children: [
          // Username
          TextField(
            controller: _loginUsernameController,
            decoration: const InputDecoration(
              labelText: 'Tên đăng nhập',
              prefixIcon: Icon(Icons.person_outline),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSizes.md),

          // Password
          TextField(
            controller: _loginPasswordController,
            obscureText: _obscureLogin,
            decoration: InputDecoration(
              labelText: 'Mật khẩu',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscureLogin ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscureLogin = !_obscureLogin),
              ),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _handleLogin(),
          ),
          const SizedBox(height: AppSizes.lg),

          // Login button
          SizedBox(
            width: double.infinity,
            height: AppSizes.buttonHeight,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleLogin,
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Đăng nhập', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSizes.lg),
      child: Column(
        children: [
          // Full name
          TextField(
            controller: _regFullNameController,
            decoration: const InputDecoration(
              labelText: 'Họ và tên *',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSizes.sm),

          // Username
          TextField(
            controller: _regUsernameController,
            decoration: const InputDecoration(
              labelText: 'Tên đăng nhập *',
              prefixIcon: Icon(Icons.person_outline),
              hintText: 'Ít nhất 3 ký tự',
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSizes.sm),

          // Password
          TextField(
            controller: _regPasswordController,
            obscureText: _obscureReg,
            decoration: InputDecoration(
              labelText: 'Mật khẩu *',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscureReg ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscureReg = !_obscureReg),
              ),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSizes.sm),

          // Confirm password
          TextField(
            controller: _regConfirmPasswordController,
            obscureText: _obscureConfirm,
            decoration: InputDecoration(
              labelText: 'Xác nhận mật khẩu *',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSizes.sm),

          // Organization
          TextField(
            controller: _regOrganizationController,
            decoration: const InputDecoration(
              labelText: 'Đơn vị (tùy chọn)',
              prefixIcon: Icon(Icons.business_outlined),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _handleRegister(),
          ),
          const SizedBox(height: AppSizes.md),

          // Register button
          SizedBox(
            width: double.infinity,
            height: AppSizes.buttonHeight,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleRegister,
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Đăng ký', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}
