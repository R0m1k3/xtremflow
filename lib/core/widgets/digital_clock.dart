import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';

class DigitalClock extends StatefulWidget {
  const DigitalClock({super.key});

  @override
  State<DigitalClock> createState() => _DigitalClockState();
}

class _DigitalClockState extends State<DigitalClock> {
  late Stream<DateTime> _clockStream;
  late DateFormat _format;

  @override
  void initState() {
    super.initState();
    _format = DateFormat('HH:mm');
    _clockStream = Stream.periodic(
      const Duration(seconds: 1),
      (_) => DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DateTime>(
      stream: _clockStream,
      initialData: DateTime.now(),
      builder: (context, snapshot) {
        final timeString = _format.format(snapshot.data ?? DateTime.now());
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const GlassDecoration(radius: 999, halo: false),
          child: Text(
            timeString,
            style: AppTheme.body(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
              fontFeatures: AppTheme.tabular,
            ),
          ),
        );
      },
    );
  }
}
