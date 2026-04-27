import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

/// Stitch-themed loading screen with dark gradient and blue accent.
class ThemedLoading extends StatelessWidget {
  const ThemedLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0F1014), // Deep Space Dark
            Color(0xFF121317), // Stitch background
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              color: Color(0xFF4b8eff), // AppColors.primaryContainer
              strokeWidth: 3,
            ),
            const SizedBox(height: 16),
            Text(
              'Loading...',
              style: GoogleFonts.inter(
                color: AppColors.onSurfaceVariant,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
