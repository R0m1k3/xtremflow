import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_container.dart';

class RecordingsTab extends StatefulWidget {
  const RecordingsTab({super.key});

  @override
  State<RecordingsTab> createState() => _RecordingsTabState();
}

class _RecordingsTabState extends State<RecordingsTab> {
  List<dynamic> _recordings = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchRecordings();
  }

  Future<void> _fetchRecordings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await http.get(Uri.parse('/api/recordings'));
      
      if (response.statusCode == 200) {
        setState(() {
          _recordings = json.decode(response.body);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Erreur serveur: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Impossible de contacter le serveur d\'enregistrement: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteRecording(String id) async {
    try {
      final response = await http.delete(Uri.parse('/api/recordings/$id'));
      if (response.statusCode == 200) {
        _fetchRecordings(); // Refresh list
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enregistrement supprimé')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la suppression'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showLogs(String id, String title) async {
    try {
      final response = await http.get(Uri.parse('/api/recordings/$id/log'));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final logs = data['logs'] ?? 'Aucun log trouvé.';
        
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              title: Text('Journaux pour "$title"', style: const TextStyle(color: Colors.white)),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: SingleChildScrollView(
                  child: Text(
                    logs,
                    style: GoogleFonts.firaCode(
                      fontSize: 12,
                      color: Colors.greenAccent,
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Fermer', style: TextStyle(color: Colors.blueAccent)),
                ),
              ],
            ),
          );
        }
      } else {
        if (mounted) {
          final data = json.decode(response.body);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['error'] ?? 'Erreur lors de la récupération des logs'), backgroundColor: Colors.orangeAccent),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible de récupérer les logs: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'recording':
        return Colors.redAccent;
      case 'completed':
        return Colors.green;
      case 'failed':
        return Colors.orangeAccent;
      default:
        return Colors.blueAccent;
    }
  }

  String _formatStatus(String status) {
    switch (status) {
      case 'scheduled': return 'Planifié';
      case 'recording': return 'En cours';
      case 'completed': return 'Terminé';
      case 'failed': return 'Échoué';
      default: return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Mes Enregistrements',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: _fetchRecordings,
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text(_error!, style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            )
          else if (_recordings.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'Aucun enregistrement trouvé.',
                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 16),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _recordings.length,
                itemBuilder: (context, index) {
                  final rec = _recordings[index];
                  final statusColor = _getStatusColor(rec['status']);
                  
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: CircleAvatar(
                        backgroundColor: statusColor.withOpacity(0.2),
                        child: Icon(
                          rec['status'] == 'recording' ? Icons.fiber_manual_record : Icons.tv,
                          color: statusColor,
                        ),
                      ),
                      title: Text(
                        rec['title'] ?? 'Inconnu',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          Text(
                            'De: ${DateTime.parse(rec['start_time']).toLocal().toString().replaceAll('.000', '')}\n'
                            'À: ${DateTime.parse(rec['end_time']).toLocal().toString().replaceAll('.000', '')}',
                            style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
                          ),
                          if (rec['error_reason'] != null && rec['error_reason'].toString().isNotEmpty)
                             Padding(
                               padding: const EdgeInsets.only(top: 4),
                               child: Text('Erreur: ${rec['error_reason']}', style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                             )
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: statusColor.withOpacity(0.5)),
                            ),
                            child: Text(
                              _formatStatus(rec['status']),
                              style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.description_outlined, color: Colors.blueAccent),
                            tooltip: 'Voir les logs',
                            onPressed: () => _showLogs(rec['id'], rec['title'] ?? 'Inconnu'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.white54),
                            tooltip: 'Supprimer',
                            onPressed: () => _deleteRecording(rec['id']),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
