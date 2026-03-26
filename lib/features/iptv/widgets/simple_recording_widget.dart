import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/iptv_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_container.dart';

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

  /// 🟢 Record NOW for X minutes
  Future<void> _recordNow(int minutes) async {
    setState(() => _status = 'Starting...');

    try {
      final response = await http.post(
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
        setState(() {
          _isRecording = true;
          _status = '🔴 Recording for $minutes min';
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Recording started!')),
          );
        }
      } else {
        throw Exception('API error');
      }
    } catch (e) {
      setState(() => _status = '❌ Error: $e');
    }
  }

  /// 🔵 Schedule for later
  Future<void> _scheduleRecording() async {
    final endTime = _startTime.add(Duration(minutes: _durationMinutes));

    try {
      final response = await http.post(
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
        setState(() => _status = '⏰ Scheduled for ${_startTime.toLocal()}');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Recording scheduled!')),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      setState(() => _status = '❌ Error: $e');
    }
  }

  /// 🔴 Stop recording
  Future<void> _stopRecording() async {
    try {
      await http.post(
        Uri.parse('/api/record/stop/${widget.channel.streamId}'),
        headers: {'Content-Type': 'application/json'},
      );

      setState(() {
        _isRecording = false;
        _status = 'Stopped';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Recording stopped!')),
        );
      }
    } catch (e) {
      setState(() => _status = '❌ Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: GlassContainer(
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              Text(
                '🎬 Record "${widget.channel.name}"',
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),

              // Status
              if (_status.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _status,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                ),
              const SizedBox(height: 20),

              // 🟢 Quick record buttons
              if (!_isRecording) ...[
                Text(
                  '⚡ Quick Record',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _QuickButton(
                      label: '30 min',
                      onTap: () => _recordNow(30),
                    ),
                    _QuickButton(
                      label: '1 hour',
                      onTap: () => _recordNow(60),
                    ),
                    _QuickButton(
                      label: '2 hours',
                      onTap: () => _recordNow(120),
                    ),
                    _QuickButton(
                      label: '4 hours',
                      onTap: () => _recordNow(240),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
              ],

              // 🔴 Stop if recording
              if (_isRecording)
                ElevatedButton.icon(
                  onPressed: _stopRecording,
                  icon: const Icon(Icons.stop),
                  label: const Text('STOP RECORDING'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),

              if (!_isRecording) ...[
                // 🔵 Schedule section
                ExpansionTile(
                  title: Text(
                    '🔵 Schedule for Later',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // Start time picker
                          ListTile(
                            title: const Text('Start'),
                            trailing: Text(
                              '${_startTime.toLocal().hour}:${_startTime.toLocal().minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(color: Colors.grey),
                            ),
                            onTap: () async {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.fromDateTime(_startTime),
                              );
                              if (time != null) {
                                setState(() {
                                  _startTime = _startTime.copyWith(
                                    hour: time.hour,
                                    minute: time.minute,
                                  );
                                });
                              }
                            },
                          ),

                          // Duration selector
                          ListTile(
                            title: const Text('Duration'),
                            trailing: DropdownButton<int>(
                              value: _durationMinutes,
                              dropdownColor: Colors.grey[800],
                              items: [30, 60, 120, 240, 480]
                                  .map((m) => DropdownMenuItem(
                                value: m,
                                child: Text('$m min'),
                              ))
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _durationMinutes = v);
                                }
                              },
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Schedule button
                          ElevatedButton.icon(
                            onPressed: _scheduleRecording,
                            icon: const Icon(Icons.schedule),
                            label: const Text('SCHEDULE'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              minimumSize: const Size.fromHeight(48),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 16),

              // Close button
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quick button component
class _QuickButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary.withOpacity(0.7),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Text(label),
    );
  }
}
