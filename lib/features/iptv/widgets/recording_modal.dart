import 'package:flutter/material.dart';

import '../../../core/api/recording_requests.dart';
import '../../../core/models/iptv_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/tv_focusable.dart';
import '../providers/recordings_refresh.dart';
import '../../../core/theme/app_theme.dart';

class RecordingModal extends StatefulWidget {
  final Channel channel;

  const RecordingModal({super.key, required this.channel});

  static Future<void> show(BuildContext context, Channel channel) {
    return showAppDialog<void>(
      context,
      builder: (context) => RecordingModal(channel: channel),
    );
  }

  @override
  State<RecordingModal> createState() => _RecordingModalState();
}

class _RecordingModalState extends State<RecordingModal> {
  DateTime _startTime = DateTime.now();
  int _durationMinutes = 60;
  bool _isLoading = false;

  Future<void> _recordNow() async {
    setState(() {
      _startTime = DateTime.now();
    });
    await _scheduleRecording();
  }

  Future<void> _scheduleRecording() async {
    setState(() => _isLoading = true);

    final endTime = _startTime.add(Duration(minutes: _durationMinutes));

    try {
      // _startTime est une vraie heure locale (pickers) : postRecording la
      // convertit en UTC — seule convention acceptée par le backend.
      final response = await postRecording(
        channelId: widget.channel.streamId,
        title: widget.channel.name,
        start: _startTime,
        end: endTime,
      );

      if (response.statusCode == 200) {
        notifyRecordingsChanged();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enregistrement programmé !')),
          );
          Navigator.of(context).pop();
        }
      } else {
        throw Exception('Erreur API');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String get _dateLabel =>
      '${_startTime.day.toString().padLeft(2, '0')}/${_startTime.month.toString().padLeft(2, '0')}/${_startTime.year}';

  String get _timeLabel =>
      '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      setState(() {
        _startTime = DateTime(
          date.year,
          date.month,
          date.day,
          _startTime.hour,
          _startTime.minute,
        );
      });
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startTime),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (time != null) {
      setState(() {
        final now = DateTime.now();
        _startTime = DateTime(
          _startTime.year,
          _startTime.month,
          _startTime.day,
          time.hour,
          time.minute,
        );
        // Empêcher l'heure de passé si c'est aujourd'hui
        if (_startTime.isBefore(now)) {
          _startTime = _startTime.add(const Duration(days: 1));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Programmer un enregistrement',
      width: 600,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Informations chaîne
          Text(
            'Chaîne',
            style: AppTheme.body(fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            widget.channel.name,
            style: AppTheme.body(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 20),

          // Date, heure et durée
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AppDialogTile(
                  icon: Icons.calendar_today,
                  label: 'Date',
                  value: _dateLabel,
                  onPressed: _pickDate,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppDialogTile(
                  icon: Icons.access_time,
                  label: 'Heure',
                  value: _timeLabel,
                  onPressed: _pickTime,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DurationStepper(
                  minutes: _durationMinutes,
                  onMinus: () {
                    if (_durationMinutes > 15) {
                      setState(() => _durationMinutes -= 15);
                    }
                  },
                  onPlus: () {
                    if (_durationMinutes < 300) {
                      setState(() => _durationMinutes += 15);
                    }
                  },
                ),
              ),
            ],
          ),
          if (_isLoading) ...[
            const SizedBox(height: 18),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ],
      ),
      actions: [
        AppDialogButton(
          label: 'Annuler',
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
        ),
        AppDialogButton(
          label: 'Enregistrer maintenant',
          onPressed: _isLoading ? null : _recordNow,
        ),
        AppDialogButton(
          label: 'Programmer',
          primary: true,
          autofocus: true,
          onPressed: _isLoading ? null : _scheduleRecording,
        ),
      ],
    );
  }
}

/// Duration in minutes, by steps of 15: − value +.
class _DurationStepper extends StatelessWidget {
  const _DurationStepper({
    required this.minutes,
    required this.onMinus,
    required this.onPlus,
  });

  final int minutes;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.glassBottom,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _StepButton(icon: Icons.remove, onPressed: onMinus),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Durée',
                  style: AppTheme.body(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                  ),
                ),
                Text(
                  '$minutes min',
                  maxLines: 1,
                  style: AppTheme.body(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    fontFeatures: AppTheme.tabular,
                  ),
                ),
              ],
            ),
          ),
          _StepButton(icon: Icons.add, onPressed: onPlus),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TVFocusable(
      paintsOwnFocus: true,
      scale: 1.06,
      borderRadius: BorderRadius.circular(10),
      onPressed: onPressed,
      child: Builder(
        builder: (context) {
          final lit = TVFocusable.isFocused(context);
          return AnimatedContainer(
            duration: AppTheme.durationFocus,
            curve: AppTheme.curveFocus,
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: lit ? AppColors.focusTop : AppColors.track,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 18,
              color: lit ? AppColors.onFocus : AppColors.textPrimary,
            ),
          );
        },
      ),
    );
  }
}
