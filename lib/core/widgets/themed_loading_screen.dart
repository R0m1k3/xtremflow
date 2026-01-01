import 'package:flutter/material.dart';

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
            Color(0xFF181920), // Soft Eerie Black
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              color: Color(0xFF007AFF), // Electric Blue (AppColors.primary)
              strokeWidth: 3,
            ),
            const SizedBox(height: 16),
            Text(
              'Loading...',
              style: TextStyle(
                fontFamily: 'Outfit', // Match AppTheme
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
