import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../../core/models/iptv_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/tv_focusable_card.dart';

class RecordingModal extends StatefulWidget {
  final Channel channel;

  const RecordingModal({
    super.key,
    required this.channel,
  });

  static Future<void> show(BuildContext context, Channel channel) {
    return showDialog(
      context: context,
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

  Future<void> _scheduleRecording() async {
    setState(() => _isLoading = true);
    
    final endTime = _startTime.add(Duration(minutes: _durationMinutes));
    
    try {
      // Utilisation d'une URL relative en Web (ou d'une configuration pour autres plateformes)
      final response = await http.post(
        Uri.parse('/api/recordings'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'channel_id': widget.channel.streamId,
          'stream_url': widget.channel.streamIcon, // Hack temp: Utiliser streamId pour générer l'url via player logic plus tard
          'title': widget.channel.name,
          'start_time': _startTime.toIso8601String(),
          'end_time': endTime.toIso8601String(),
        }),
      );

      if (response.statusCode == 200) {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 450,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.background.withOpacity(0.9),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.primary.withOpacity(0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  const Icon(Icons.fiber_manual_record, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Programmer un enregistrement',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Informations Chaine
              Text(
                'Chaîne ciblée :',
                style: GoogleFonts.inter(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                widget.channel.name,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 24),

              // Heure de début
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Heure de début :',
                          style: GoogleFonts.inter(color: Colors.white54, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        TvFocusableCard(
                          onTap: () async {
                            final time = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(_startTime),
                            );
                            if (time != null) {
                              setState(() {
                                final now = DateTime.now();
                                _startTime = DateTime(
                                  now.year, now.month, now.day,
                                  time.hour, time.minute,
                                );
                                // Empêcher l'heure de passé de demain pour simplifier
                                if (_startTime.isBefore(now)) {
                                  _startTime = _startTime.add(const Duration(days: 1));
                                }
                              });
                            }
                          },
                          borderRadius: 8,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.access_time, color: Colors.white, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}',
                                  style: GoogleFonts.inter(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  
                  // Durée
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Durée (minutes) :',
                          style: GoogleFonts.inter(color: Colors.white54, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        GlassContainer(
                          borderRadius: 8,
                          opacity: 0.1,
                          padding: EdgeInsets.zero,
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove, color: Colors.white),
                                onPressed: () {
                                  if (_durationMinutes > 15) {
                                    setState(() => _durationMinutes -= 15);
                                  }
                                },
                              ),
                              Expanded(
                                child: Text(
                                  '$_durationMinutes m',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(color: Colors.white),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add, color: Colors.white),
                                onPressed: () {
                                  if (_durationMinutes < 300) {
                                    setState(() => _durationMinutes += 15);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                    child: Text(
                      'Annuler',
                      style: GoogleFonts.inter(color: Colors.white54),
                    ),
                  ),
                  const SizedBox(width: 16),
                  TvFocusableCard(
                    onTap: _isLoading ? () {} : _scheduleRecording,
                    borderRadius: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _isLoading 
                        ? const SizedBox(
                            width: 20, height: 20, 
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            'Enregistrer',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
