import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'xtremflow_mark.dart';

/// Écran de chargement « Salle obscure » : le logo et un fin anneau bleu
/// clair, sur le fond de la page qui l'accueille (transparent, pour laisser
/// voir l'`AmbientBackground` dans les onglets).
class ThemedLoading extends StatelessWidget {
  const ThemedLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          XtremFlowMark(height: 40),
          SizedBox(height: 28),
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              color: AppColors.accent,
              backgroundColor: AppColors.track,
              strokeWidth: 2,
            ),
          ),
          SizedBox(height: 16),
          _LoadingLabel(),
        ],
      ),
    );
  }
}

class _LoadingLabel extends StatelessWidget {
  const _LoadingLabel();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Chargement…',
      style: AppTheme.body(fontSize: 14, color: AppColors.textMuted),
    );
  }
}
