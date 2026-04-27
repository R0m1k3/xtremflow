import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../features/auth/providers/auth_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../theme/mobile_theme.dart';

class MobileLoginScreen extends ConsumerStatefulWidget {
  const MobileLoginScreen({super.key});

  @override
  ConsumerState<MobileLoginScreen> createState() => _MobileLoginScreenState();
}

class _MobileLoginScreenState extends ConsumerState<MobileLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    // Pre-fill for convenience (as requested in original file)
    _usernameController.text = 'admin';
    _passwordController.text = 'admin';
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = ref.read(authProvider.notifier);
    final success = await auth.login(
      _usernameController.text.trim(),
      _passwordController.text,
    );

    if (success && mounted) {
      context.go('/playlists');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Theme(
      data: MobileTheme.darkTheme,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: AppColors.background,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Cinematic Background Gradient
             Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF000000), // Deep Black
                    Color(0xFF0F0F12), // Subtle Gray
                    Color(0xFF000000), // Back to Black
                  ],
                ),
              ),
            ),
             // Ambient Glow Top Left
            Positioned(
              top: -100,
              left: -100,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withOpacity(0.15),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.15),
                      blurRadius: 150,
                      spreadRadius: 50,
                    ),
                  ],
                ),
              ),
            ),
            
            // Content
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: GlassContainer.floating(
                  borderRadius: 24,
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo / Icon
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainer,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.outlineVariant),
                        ),
                        child: const Icon(
                          Icons.live_tv_rounded,
                          color: AppColors.onSurface,
                          size: 40,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'XtremFlow',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                          letterSpacing: -1.0,
                        ),
                      ),
                       Text(
                        'Mobile Edition',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppColors.onSurfaceVariant,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 48),
            
                      // Form
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            _buildInput(
                              controller: _usernameController,
                              label: 'Username',
                              icon: Icons.person_outline_rounded,
                            ),
                            const SizedBox(height: 16),
                            _buildInput(
                              controller: _passwordController,
                              label: 'Password',
                              icon: Icons.lock_outline_rounded,
                              isPassword: true,
                              obscureText: _obscurePassword,
                              onTogglePassword: () => setState(() => _obscurePassword = !_obscurePassword),
                              onSubmitted: (_) => _handleLogin(),
                            ),
                            
                            if (authState.errorMessage != null) ...[
                              const SizedBox(height: 24),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.error.withOpacity(0.3)),
                                ),
                                child: Text(
                                  authState.errorMessage!,
                                  style: GoogleFonts.inter(color: AppColors.error, fontSize: 13),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                            
                            const SizedBox(height: 32),
                            
                            Container(
                              width: double.infinity,
                              height: 50,
                              decoration: BoxDecoration(
                                gradient: AppColors.primaryGradient,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.glowPrimary(0.4),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: FilledButton(
                                onPressed: authState.isLoading ? null : _handleLogin,
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 0,
                                ).copyWith(
                                  overlayColor: WidgetStateProperty.all(AppColors.onSurface.withOpacity(0.1)),
                                ),
                                child: authState.isLoading
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : Text(
                                        'Sign In',
                                        style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.white),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onTogglePassword,
    Function(String)? onSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      style: GoogleFonts.inter(color: AppColors.onSurface),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(color: AppColors.onSurfaceVariant),
        prefixIcon: Icon(icon, color: AppColors.onSurfaceVariant),
        suffixIcon: isPassword
          ? IconButton(
              icon: Icon(obscureText ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: AppColors.outline),
              onPressed: onTogglePassword,
            )
          : null,
        filled: true,
        fillColor: AppColors.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primaryContainer, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
      onFieldSubmitted: onSubmitted,
    );
  }
}
