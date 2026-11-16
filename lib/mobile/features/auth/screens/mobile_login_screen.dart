import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/glass.dart';
import '../../../../core/widgets/xtremflow_mark.dart';
import '../../../../features/auth/providers/auth_provider.dart';
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
        backgroundColor: Colors.transparent,
        body: AmbientBackground(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(
                        child: XtremFlowWordmark(markHeight: 34, fontSize: 26),
                      ),
                      const SizedBox(height: 32),
                      Container(
                        decoration: const GlassDecoration(
                          radius: 16,
                          halo: false,
                        ),
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Connexion',
                                style: AppTheme.display(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Votre compte XtremFlow',
                                style: AppTheme.body(
                                  fontSize: 15,
                                  color: AppColors.textMuted,
                                ),
                              ),
                              const SizedBox(height: 24),
                              _buildInput(
                                controller: _usernameController,
                                label: 'Nom d’utilisateur',
                                icon: Icons.person_outline_rounded,
                              ),
                              const SizedBox(height: 12),
                              _buildInput(
                                controller: _passwordController,
                                label: 'Mot de passe',
                                icon: Icons.lock_outline_rounded,
                                isPassword: true,
                                obscureText: _obscurePassword,
                                onTogglePassword: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                onSubmitted: (_) => _handleLogin(),
                              ),
                              if (authState.errorMessage != null) ...[
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.errorContainer,
                                    borderRadius: BorderRadius.circular(
                                      AppTheme.radiusMd,
                                    ),
                                  ),
                                  child: Text(
                                    authState.errorMessage!,
                                    style: AppTheme.body(
                                      fontSize: 14,
                                      color: AppColors.onErrorContainer,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 24),
                              SizedBox(
                                height: 52,
                                child: FilledButton(
                                  onPressed: authState.isLoading
                                      ? null
                                      : _handleLogin,
                                  child: authState.isLoading
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppColors.textSecondary,
                                          ),
                                        )
                                      : const Text('Se connecter'),
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
          ),
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
      style: AppTheme.body(fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppTheme.body(fontSize: 15, color: AppColors.textMuted),
        floatingLabelStyle: AppTheme.body(
          fontSize: 14,
          color: AppColors.textSecondary,
        ),
        prefixIcon: Icon(icon, color: AppColors.textMuted),
        suffixIcon: isPassword
            ? IconButton(
                tooltip: obscureText
                    ? 'Afficher le mot de passe'
                    : 'Masquer le mot de passe',
                icon: Icon(
                  obscureText
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: AppColors.textMuted,
                ),
                onPressed: onTogglePassword,
              )
            : null,
        fillColor: AppColors.background,
        errorStyle: AppTheme.body(fontSize: 13, color: AppColors.error),
      ),
      validator: (value) =>
          (value == null || value.trim().isEmpty) ? 'Obligatoire' : null,
      onFieldSubmitted: onSubmitted,
    );
  }
}
