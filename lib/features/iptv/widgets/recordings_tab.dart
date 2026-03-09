import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../../core/models/iptv_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_container.dart';
import '../providers/xtream_provider.dart';
import '../providers/settings_provider.dart';

/// Onglet "Enregistrements & Guide TV" — combine guide EPG, enregistrements actifs et season passes
class RecordingsTab extends StatefulWidget {
  const RecordingsTab({super.key});

  @override
  State<RecordingsTab> createState() => _RecordingsTabState();
}

class _RecordingsTabState extends State<RecordingsTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() => _selectedTab = _tabController.index);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header + TabBar combinés
        Container(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.tv, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'TV & Enregistrements',
                    style: GoogleFonts.outfit(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TabBar(
                controller: _tabController,
                labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14),
                unselectedLabelStyle: GoogleFonts.outfit(fontSize: 14),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                indicatorColor: Colors.redAccent,
                indicatorWeight: 3,
                tabs: const [
                  Tab(icon: Icon(Icons.grid_view, size: 18), text: 'Guide TV'),
                  Tab(icon: Icon(Icons.fiber_manual_record, size: 18), text: 'Enregistrements'),
                  Tab(icon: Icon(Icons.repeat, size: 18), text: 'Season Passes'),
                ],
              ),
            ],
          ),
        ),
        // Corps des onglets
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _EpgGuideView(),
              _RecordingsListView(),
              _SeasonPassesView(),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
//  ONGLET 1 — GUIDE TV (EPG)
// ═══════════════════════════════════════════════════════

/// Guide TV EPG — charge les chaînes filtrées depuis les Settings (comme l'onglet TV)
class _EpgGuideView extends ConsumerStatefulWidget {
  const _EpgGuideView();
  @override
  ConsumerState<_EpgGuideView> createState() => _EpgGuideViewState();
}

class _EpgGuideViewState extends ConsumerState<_EpgGuideView> {
  String? _selectedChannelId;
  String? _selectedChannelName;
  String? _selectedStreamUrl;
  List<dynamic> _programmes = [];
  bool _loadingEpg = false;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _searchQuery = _searchCtrl.text.toLowerCase()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEpg(String channelId) async {
    setState(() { _loadingEpg = true; _programmes = []; });
    try {
      final response = await http.get(Uri.parse('/api/epg/$channelId'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _programmes = (data['programmes'] as List<dynamic>? ?? []);
          _loadingEpg = false;
        });
      } else {
        setState(() => _loadingEpg = false);
      }
    } catch (e) {
      setState(() => _loadingEpg = false);
    }
  }

  void _selectChannel(Channel ch) {
    setState(() {
      _selectedChannelId = ch.streamId.toString();
      _selectedChannelName = ch.name;
      _selectedStreamUrl = '/api/live/${ch.streamId}.ts';
      _programmes = [];
    });
    _loadEpg(ch.streamId.toString());
  }

  @override
  Widget build(BuildContext context) {
    final playlist = ref.watch(selectedPlaylistProvider);
    final settings = ref.watch(iptvSettingsProvider);

    // Charger les chaînes seulement si on a une playlist active
    final channelsAsync = playlist != null
        ? ref.watch(liveChannelsByPlaylistProvider(playlist))
        : null;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Colonne gauche : liste des chaînes filtrées ───
          SizedBox(
            width: 220,
            child: Column(
              children: [
                // Barre de recherche
                TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Chercher une chaîne...',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.07),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: channelsAsync == null
                      ? Center(
                          child: Text('Aucune playlist
active',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12)),
                        )
                      : channelsAsync.when(
                          loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          error: (e, _) => Center(child: Text('Erreur: $e', style: const TextStyle(color: Colors.red, fontSize: 12))),
                          data: (groupedChannels) {
                            // Appliquer le même filtre que l'onglet TV
                            final filteredChannels = <Channel>[];
                            for (final entry in groupedChannels.entries) {
                              if (settings.liveTvKeywords.isEmpty ||
                                  settings.matchesLiveTvFilter(entry.key)) {
                                filteredChannels.addAll(entry.value);
                              }
                            }
                            // Tri alphabétique
                            filteredChannels.sort((a, b) => a.name.compareTo(b.name));

                            // Filtre par recherche
                            final visible = _searchQuery.isEmpty
                                ? filteredChannels
                                : filteredChannels
                                    .where((c) => c.name.toLowerCase().contains(_searchQuery))
                                    .toList();

                            if (visible.isEmpty) {
                              return Center(
                                child: Text('Aucune chaîne\n(vérifiez les filtres dans Settings)',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12)),
                              );
                            }

                            return ListView.builder(
                              itemCount: visible.length,
                              itemBuilder: (ctx, i) {
                                final ch = visible[i];
                                final isSelected = ch.streamId.toString() == _selectedChannelId;
                                return InkWell(
                                  onTap: () => _selectChannel(ch),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.redAccent.withOpacity(0.2)
                                          : Colors.white.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSelected
                                            ? Colors.redAccent.withOpacity(0.5)
                                            : Colors.transparent,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        if (ch.streamIcon != null && ch.streamIcon!.isNotEmpty)
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(4),
                                            child: Image.network(
                                              ch.streamIcon!,
                                              width: 28,
                                              height: 20,
                                              fit: BoxFit.contain,
                                              errorBuilder: (_, __, ___) =>
                                                  const Icon(Icons.tv, color: Colors.white38, size: 20),
                                            ),
                                          )
                                        else
                                          const Icon(Icons.tv, color: Colors.white38, size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            ch.name,
                                            style: GoogleFonts.outfit(
                                              color: isSelected ? Colors.white : Colors.white70,
                                              fontSize: 12,
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // ─── Colonne droite : programmes de la chaîne sélectionnée ───
          Expanded(
            child: _selectedChannelId == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.tv_off, size: 64, color: Color(0x1FFFFFFF)),
                        const SizedBox(height: 16),
                        Text(
                          'Sélectionnez une chaîne pour\nvoir son guide des programmes',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(color: Colors.white38, fontSize: 15),
                        ),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _selectedChannelName ?? '',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.refresh, color: Colors.white54, size: 18),
                            onPressed: () => _loadEpg(_selectedChannelId!),
                            tooltip: 'Recharger l\'EPG',
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white12),
                      Expanded(
                        child: _loadingEpg
                            ? const Center(child: CircularProgressIndicator())
                            : _programmes.isEmpty
                                ? Center(
                                    child: Text('Aucun programme EPG disponible',
                                        style: GoogleFonts.outfit(color: Colors.white38)),
                                  )
                                : ListView.builder(
                                    itemCount: _programmes.length,
                                    itemBuilder: (ctx, i) => _ProgrammeCard(
                                      programme: _programmes[i],
                                      channelName: _selectedChannelName ?? '',
                                      channelId: _selectedChannelId!,
                                      streamUrl: _selectedStreamUrl ?? '/api/live/$_selectedChannelId.ts',
                                    ),
                                  ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProgrammeCard extends StatelessWidget {
  final Map<String, dynamic> programme;
  final String channelName;
  final String channelId;
  final String streamUrl;

  const _ProgrammeCard({
    required this.programme,
    required this.channelName,
    required this.channelId,
    required this.streamUrl,
  });

  String _formatTime(String rawTime) {
    try {
      final dt = DateTime.parse(rawTime).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return rawTime.length >= 5 ? rawTime.substring(11, 16) : rawTime;
    }
  }

  bool get _isNow {
    try {
      final start = DateTime.parse(programme['start'] as String);
      final end = DateTime.parse(programme['end'] as String);
      final now = DateTime.now().toUtc();
      return now.isAfter(start) && now.isBefore(end);
    } catch (_) { return false; }
  }

  bool get _isPast {
    try {
      final end = DateTime.parse(programme['end'] as String);
      return DateTime.now().toUtc().isAfter(end);
    } catch (_) { return false; }
  }

  void _scheduleRecording(BuildContext context) {
    try {
      final start = DateTime.parse(programme['start'] as String).toUtc();
      final end = DateTime.parse(programme['end'] as String).toUtc();
      final title = programme['title'] as String? ?? channelName;
      _showRecordingConfirm(context, title, start, end);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de programmer: $e')),
      );
    }
  }

  void _showRecordingConfirm(BuildContext context, String title, DateTime start, DateTime end) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Row(
          children: [
            const Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('Enregistrer', style: GoogleFonts.outfit(color: Colors.white))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              '${_formatTime(programme['start'])} → ${_formatTime(programme['end'])}',
              style: const TextStyle(color: Colors.white70),
            ),
            if ((programme['description'] as String? ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                programme['description'] as String,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              await _saveRecording(context, title, start, end);
            },
            child: const Text('🔴 Enregistrer'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveRecording(BuildContext context, String title, DateTime start, DateTime end) async {
    try {
      final response = await http.post(
        Uri.parse('/api/recordings'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'channel_id': channelId,
          'stream_url': streamUrl,
          'title': title,
          'start_time': start.toIso8601String(),
          'end_time': end.toIso8601String(),
        }),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.statusCode == 200 ? '✅ "$title" planifié !' : '❌ Erreur: ${response.body}'),
            backgroundColor: response.statusCode == 200 ? Colors.green.shade800 : Colors.red.shade800,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNow = _isNow;
    final isPast = _isPast;
    final title = programme['title'] as String? ?? '—';
    final start = programme['start'] as String? ?? '';
    final end = programme['end'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isNow
            ? Colors.red.withOpacity(0.15)
            : isPast
                ? Colors.white.withOpacity(0.03)
                : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isNow ? Colors.redAccent.withOpacity(0.5) : Colors.white.withOpacity(0.08),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (isNow)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('LIVE', style: GoogleFonts.outfit(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
              )
            else
              Text(
                _formatTime(start),
                style: GoogleFonts.outfit(
                  color: isPast ? Colors.white24 : Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (!isNow)
              Text(
                _formatTime(end),
                style: GoogleFonts.outfit(color: Colors.white24, fontSize: 11),
              ),
          ],
        ),
        title: Text(
          title,
          style: GoogleFonts.outfit(
            color: isPast ? Colors.white38 : Colors.white,
            fontWeight: isNow ? FontWeight.bold : FontWeight.normal,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: (programme['description'] as String? ?? '').isNotEmpty
            ? Text(
                programme['description'] as String,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white38, fontSize: 11),
              )
            : null,
        trailing: !isPast
            ? IconButton(
                icon: const Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 22),
                tooltip: 'Enregistrer ce programme',
                onPressed: () => _scheduleRecording(context),
              )
            : null,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  ONGLET 2 — MES ENREGISTREMENTS
// ═══════════════════════════════════════════════════════

class _RecordingsListView extends StatefulWidget {
  const _RecordingsListView();
  @override
  State<_RecordingsListView> createState() => _RecordingsListViewState();
}

class _RecordingsListViewState extends State<_RecordingsListView> {
  List<dynamic> _recordings = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchRecordings();
  }

  Future<void> _fetchRecordings() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final response = await http.get(Uri.parse('/api/recordings'));
      if (response.statusCode == 200) {
        setState(() { _recordings = json.decode(response.body); _isLoading = false; });
      } else {
        setState(() { _error = 'Erreur ${response.statusCode}'; _isLoading = false; });
      }
    } catch (e) {
      setState(() { _error = '$e'; _isLoading = false; });
    }
  }

  Future<void> _stopRecording(String id, String title) async {
    final response = await http.post(Uri.parse('/api/recordings/stop/$id'));
    if (response.statusCode == 200) {
      _fetchRecordings();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⏹ "$title" arrêté')));
    }
  }

  Future<void> _deleteRecording(String id) async {
    await http.delete(Uri.parse('/api/recordings/$id'));
    _fetchRecordings();
  }

  Future<void> _showLogs(String id, String title) async {
    try {
      final response = await http.get(Uri.parse('/api/recordings/logs/$id'));
      if (!mounted) return;
      final content = response.statusCode == 200
          ? (json.decode(response.body)['logs'] as String? ?? 'Aucun log')
          : 'Logs non disponibles (${response.statusCode})';
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: Text(title, style: GoogleFonts.outfit(color: Colors.white, fontSize: 14)),
          content: SizedBox(
            width: 500,
            height: 300,
            child: SingleChildScrollView(
              child: Text(content, style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace')),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))],
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur logs: $e')));
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'recording': return Colors.redAccent;
      case 'completed': return Colors.green;
      case 'failed': return Colors.orangeAccent;
      default: return Colors.blueAccent;
    }
  }

  String _formatStatus(String status) {
    switch (status) {
      case 'scheduled': return 'Planifié';
      case 'recording': return '● En cours';
      case 'completed': return 'Terminé';
      case 'failed': return 'Échoué';
      default: return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white70),
                onPressed: _fetchRecordings,
                tooltip: 'Rafraîchir',
              ),
            ],
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
                    : _recordings.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.videocam_off, size: 64, color: Colors.white12),
                                const SizedBox(height: 16),
                                Text('Aucun enregistrement',
                                    style: GoogleFonts.outfit(color: Colors.white38, fontSize: 16)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _recordings.length,
                            itemBuilder: (ctx, i) {
                              final rec = _recordings[i];
                              final status = rec['status'] as String? ?? 'unknown';
                              final statusColor = _statusColor(status);
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  leading: Icon(
                                    status == 'recording' ? Icons.fiber_manual_record : Icons.videocam,
                                    color: statusColor,
                                    size: 28,
                                  ),
                                  title: Text(rec['title'] ?? '—',
                                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${_fmtDate(rec['start_time'])} → ${_fmtDate(rec['end_time'])}',
                                        style: TextStyle(color: Colors.white54, fontSize: 12),
                                      ),
                                      if (rec['error_reason'] != null)
                                        Text('⚠ ${rec['error_reason']}',
                                            style: const TextStyle(color: Colors.orangeAccent, fontSize: 11)),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: statusColor.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: statusColor.withOpacity(0.4)),
                                        ),
                                        child: Text(_formatStatus(status),
                                            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11)),
                                      ),
                                      const SizedBox(width: 4),
                                      if (status == 'recording')
                                        IconButton(
                                          icon: const Icon(Icons.stop_circle, color: Colors.redAccent),
                                          tooltip: 'Arrêter',
                                          onPressed: () => _stopRecording(rec['id'], rec['title'] ?? ''),
                                        ),
                                      IconButton(
                                        icon: const Icon(Icons.description_outlined, color: Colors.blueAccent, size: 20),
                                        tooltip: 'Logs',
                                        onPressed: () => _showLogs(rec['id'], rec['title'] ?? ''),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 20),
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

  String _fmtDate(dynamic raw) {
    if (raw == null) return '?';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      return '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    } catch (_) { return raw.toString(); }
  }
}

// ═══════════════════════════════════════════════════════
//  ONGLET 3 — SEASON PASSES
// ═══════════════════════════════════════════════════════

class _SeasonPassesView extends StatefulWidget {
  const _SeasonPassesView();
  @override
  State<_SeasonPassesView> createState() => _SeasonPassesViewState();
}

class _SeasonPassesViewState extends State<_SeasonPassesView> {
  List<dynamic> _passes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPasses();
  }

  Future<void> _loadPasses() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse('/api/season-passes'));
      if (response.statusCode == 200) {
        setState(() { _passes = json.decode(response.body); _isLoading = false; });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deletePass(String id, String title) async {
    await http.delete(Uri.parse('/api/season-passes/$id'));
    _loadPasses();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Season Pass "$title" supprimé')));
    }
  }

  void _showCreateDialog() {
    final titleController = TextEditingController();
    final channelIdController = TextEditingController();
    final streamUrlController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Row(
          children: [
            const Icon(Icons.repeat, color: Colors.purpleAccent),
            const SizedBox(width: 8),
            Text('Nouveau Season Pass', style: GoogleFonts.outfit(color: Colors.white)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enregistre automatiquement toutes les nouvelles diffusions d\'une émission sur une chaîne.',
                style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              _Field(controller: titleController, label: 'Titre de l\'émission (ex: Champions League)'),
              const SizedBox(height: 8),
              _Field(controller: channelIdController, label: 'Channel ID (ex: 554021)'),
              const SizedBox(height: 8),
              _Field(controller: streamUrlController, label: 'stream_url (ex: /api/live/554021.ts)'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent),
            onPressed: () async {
              final title = titleController.text.trim();
              final channelId = channelIdController.text.trim();
              final streamUrl = streamUrlController.text.trim().isEmpty
                  ? '/api/live/${channelIdController.text.trim()}.ts'
                  : streamUrlController.text.trim();
              if (title.isEmpty || channelId.isEmpty) return;
              Navigator.pop(ctx);
              final response = await http.post(
                Uri.parse('/api/season-passes'),
                headers: {'Content-Type': 'application/json'},
                body: json.encode({'show_title': title, 'channel_id': channelId, 'stream_url': streamUrl}),
              );
              _loadPasses();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(response.statusCode == 201 ? '✅ Season Pass créé !' : '❌ ${response.body}'),
                ));
              }
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Enregistrements automatiques',
                  style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nouveau'),
                onPressed: _showCreateDialog,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Explication du fonctionnement
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.purpleAccent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.purpleAccent.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.purpleAccent, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Le Season Pass scanne l\'EPG toutes les 4h et programme automatiquement les nouvelles diffusions. Seuls les nouveaux épisodes sont enregistrés.',
                    style: GoogleFonts.outfit(color: Colors.purpleAccent.shade100, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _passes.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.repeat, size: 64, color: Colors.white12),
                            const SizedBox(height: 16),
                            Text('Aucun Season Pass actif',
                                style: GoogleFonts.outfit(color: Colors.white38, fontSize: 16)),
                            const SizedBox(height: 8),
                            Text('Créez-en un pour enregistrer automatiquement vos émissions préférées',
                                style: GoogleFonts.outfit(color: Colors.white24, fontSize: 12),
                                textAlign: TextAlign.center),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _passes.length,
                        itemBuilder: (ctx, i) {
                          final pass = _passes[i];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.purpleAccent.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.purpleAccent.withOpacity(0.2)),
                            ),
                            child: ListTile(
                              leading: const Icon(Icons.repeat, color: Colors.purpleAccent),
                              title: Text(pass['show_title'] ?? '—',
                                  style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Chaîne : ${pass['channel_id']}',
                                      style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                  Text('Flux : ${pass['stream_url']}',
                                      style: const TextStyle(color: Colors.white38, fontSize: 10)),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.white38),
                                tooltip: 'Supprimer',
                                onPressed: () => _deletePass(pass['id'], pass['show_title'] ?? ''),
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

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  const _Field({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.purpleAccent)),
      ),
    );
  }
}
