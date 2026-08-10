import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

/// Écran de chargement « Warm Cinema » — salle qui s'éteint avant projection.
class ThemedLoading extends StatelessWidget {
  const ThemedLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                color: AppColors.primaryContainer,
                strokeWidth: 2,
              ),
            ),
            SizedBox(height: 20),
            _LoadingLabel(),
          ],
        ),
      ),
    );
  }
}

class _LoadingLabel extends StatelessWidget {
  const _LoadingLabel();

  @override
  Widget build(BuildContext context) {
    return Text(
      'PROJECTION',
      style: GoogleFonts.karla(
        color: AppColors.textTertiary,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 3.2,
      ),
    );
  }
}
