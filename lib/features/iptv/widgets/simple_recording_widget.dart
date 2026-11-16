import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/api/authed_http.dart';
import '../../../core/models/iptv_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_dialog.dart';
import '../providers/recordings_refresh.dart';
import '../../../core/theme/app_theme.dart';

class SimpleRecordingWidget extends StatefulWidget {
  final Channel channel;
  final String streamUrl;

  const SimpleRecordingWidget({
    super.key,
    required this.channel,
    required this.streamUrl,
  });

  @override
  State<SimpleRecordingWidget> createState() => _SimpleRecordingWidgetState();
}

class _SimpleRecordingWidgetState extends State<SimpleRecordingWidget> {
  bool _isRecording = false;
  String _status = '';
  int _durationMinutes = 60;
  DateTime _startTime = DateTime.now();

  /// Record now for X minutes.
  Future<void> _recordNow(int minutes) async {
    setState(() => _status = 'Démarrage…');

    try {
      final response = await AuthedHttp.post(
        Uri.parse('/api/record/now'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'channel_id': widget.channel.streamId,
          'stream_url': widget.streamUrl,
          'title': widget.channel.name,
          'duration_minutes': minutes,
        }),
      );

      if (response.statusCode == 200) {
        notifyRecordingsChanged();
        setState(() {
          _isRecording = true;
          _status = 'Enregistrement en cours ($minutes min)';
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enregistrement démarré')),
          );
        }
      } else {
        throw Exception('Erreur API');
      }
    } catch (e) {
      setState(() => _status = 'Erreur : $e');
    }
  }

  /// Schedule for later.
  Future<void> _scheduleRecording() async {
    final endTime = _startTime.add(Duration(minutes: _durationMinutes));

    try {
      final response = await AuthedHttp.post(
        Uri.parse('/api/record/schedule'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'channel_id': widget.channel.streamId,
          'stream_url': widget.streamUrl,
          'title': widget.channel.name,
          'start_time': _startTime.toIso8601String(),
          'end_time': endTime.toIso8601String(),
        }),
      );

      if (response.statusCode == 200) {
        notifyRecordingsChanged();
        setState(() => _status = 'Programmé pour ${_startTime.toLocal()}');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enregistrement programmé')),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      setState(() => _status = 'Erreur : $e');
    }
  }

  /// Stop the recording.
  Future<void> _stopRecording() async {
    try {
      await AuthedHttp.post(
        Uri.parse('/api/record/stop/${widget.channel.streamId}'),
        headers: {'Content-Type': 'application/json'},
      );

      notifyRecordingsChanged();
      setState(() {
        _isRecording = false;
        _status = 'Arrêté';
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Enregistrement arrêté')));
      }
    } catch (e) {
      setState(() => _status = 'Erreur : $e');
    }
  }

  String get _startLabel =>
      '${_startTime.toLocal().hour}:${_startTime.toLocal().minute.toString().padLeft(2, '0')}';

  Future<void> _pickStart() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startTime),
    );
    if (time != null) {
      setState(() {
        _startTime = _startTime.copyWith(hour: time.hour, minute: time.minute);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Enregistrer « ${widget.channel.name} »',
      width: 500,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status
          if (_status.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.glassBottom,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  if (_isRecording) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.live,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      _status,
                      style: AppTheme.body(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Quick record buttons
          if (!_isRecording) ...[
            Text(
              'Enregistrer maintenant',
              style: AppTheme.body(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppDialogButton(
                  label: '30 min',
                  onPressed: () => _recordNow(30),
                ),
                AppDialogButton(label: '1 h', onPressed: () => _recordNow(60)),
                AppDialogButton(label: '2 h', onPressed: () => _recordNow(120)),
                AppDialogButton(label: '4 h', onPressed: () => _recordNow(240)),
              ],
            ),
            const SizedBox(height: 24),
          ],

          // Stop if recording
          if (_isRecording)
            AppDialogButton(
              label: "Arrêter l'enregistrement",
              destructive: true,
              onPressed: _stopRecording,
            ),

          if (!_isRecording) ...[
            // Schedule section
            Text(
              'Programmer pour plus tard',
              style: AppTheme.body(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            AppDialogTile(
              icon: Icons.access_time,
              label: 'Début',
              value: _startLabel,
              onPressed: _pickStart,
            ),
            const SizedBox(height: 10),
            Text(
              'Durée',
              style: AppTheme.body(fontSize: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [30, 60, 120, 240, 480]
                  .map(
                    (m) => AppDialogButton(
                      label: '$m min',
                      primary: _durationMinutes == m,
                      onPressed: () => setState(() => _durationMinutes = m),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            AppDialogButton(
              label: 'Programmer',
              primary: true,
              onPressed: _scheduleRecording,
            ),
          ],
        ],
      ),
      actions: [
        AppDialogButton(
          label: 'Fermer',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
