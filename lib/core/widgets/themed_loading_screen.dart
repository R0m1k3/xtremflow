import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class ThemedLoading extends StatelessWidget {
  const ThemedLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.2),
          radius: 1.5,
          colors: [
            Color(0xFF2C2C2E),
            Color(0xFF000000),
          ],
          stops: [0.0, 1.0],
        ),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 3,
        ),
      ),
    );
  }
}
