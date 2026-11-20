import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/theme/glass.dart';
import '../../../core/widgets/xtremflow_mark.dart';
import '../../../core/theme/app_theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

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

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AmbientBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo
                const Hero(
                  tag: 'app_logo',
                  child: XtremFlowWordmark(markHeight: 48, fontSize: 34),
                ),
                const SizedBox(height: 16),
                Text(
                  'Connectez-vous pour retrouver vos playlists',
                  textAlign: TextAlign.center,
                  style: AppTheme.body(
                    fontSize: 17,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 40),

                // Login Form Container
                GlassContainer.floating(
                  width: 460,
                  padding: const EdgeInsets.all(36),
                  borderRadius: 20,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Username Input
                        _buildTvInput(
                          controller: _usernameController,
                          label: "Nom d'utilisateur",
                          icon: Icons.person_outline_rounded,
                          autofocus: true,
                          nextFocus: true,
                        ),
                        const SizedBox(height: 18),

                        // Password Input
                        _buildTvInput(
                          controller: _passwordController,
                          label: 'Mot de passe',
                          icon: Icons.lock_outline_rounded,
                          obscureText: _obscurePassword,
                          isLast: true,
                          onSubmitted: _handleLogin,
                          suffix: IconButton(
                            tooltip: _obscurePassword
                                ? 'Afficher le mot de passe'
                                : 'Masquer le mot de passe',
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: AppColors.textMuted,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),

                        // Error Message
                        if (authState.errorMessage != null) ...[
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.errorContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  color: AppColors.error,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    authState.errorMessage!,
                                    style: AppTheme.body(
                                      fontSize: 14,
                                      color: AppColors.onErrorContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 28),

                        // Sign In Button
                        SizedBox(
                          height: 54,
                          child: FilledButton(
                            onPressed: _handleLogin,
                            child: authState.isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: AppColors.onFocus,
                                    ),
                                  )
                                : Text(
                                    'Se connecter',
                                    style: AppTheme.body(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.onFocus,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTvInput({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    bool autofocus = false,
    bool nextFocus = false,
    bool isLast = false,
    VoidCallback? onSubmitted,
    Widget? suffix,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      style: AppTheme.body(fontSize: 17),
      cursorColor: AppColors.accent,
      autofocus: autofocus,
      textInputAction: nextFocus ? TextInputAction.next : TextInputAction.done,
      onFieldSubmitted: isLast ? (_) => onSubmitted?.call() : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppTheme.body(fontSize: 15, color: AppColors.textMuted),
        floatingLabelStyle: AppTheme.body(
          fontSize: 15,
          color: AppColors.accent,
        ),
        prefixIcon: Icon(icon, color: AppColors.textMuted),
        suffixIcon: suffix,
        fillColor: AppColors.rail,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusField),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return '$label requis';
        }
        return null;
      },
    );
  }
}
