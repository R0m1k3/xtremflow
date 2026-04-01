import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../../core/models/iptv_models.dart';
import '../../../core/models/playlist_config.dart';
import '../providers/xtream_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/player_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  ENTRÉE — Onglet "Enregistrements"
// ═══════════════════════════════════════════════════════════════════════════

class RecordingsTab extends StatefulWidget {
  final PlaylistConfig playlist;
  const RecordingsTab({super.key, required this.playlist});

  @override
  State<RecordingsTab> createState() => _RecordingsTabState();
}

class _RecordingsTabState extends State<RecordingsTab> {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            color: Colors.grey[900],
            child: const Row(
              children: [
                Icon(Icons.videocam, color: Colors.white, size: 28),
                SizedBox(width: 12),
                Text(
                  'Enregistrements',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _RecordingsListView(playlist: widget.playlist),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  ONGLET 1 — GUIDE TV
//  Charge les chaînes via liveChannelsByPlaylistProvider (même provider que
//  l'onglet Live TV) + EPG via XtreamService.getShortEpg (même mécanisme
//  qu'EPGWidget, qui passe par /api/xtream/ proxy).
// ═══════════════════════════════════════════════════════════════════════════

class _EpgGuideView extends ConsumerStatefulWidget {
  final PlaylistConfig playlist;
  const _EpgGuideView({required this.playlist});

  @override
  ConsumerState<_EpgGuideView> createState() => _EpgGuideViewState();
}

class _EpgGuideViewState extends ConsumerState<_EpgGuideView>
    with AutomaticKeepAliveClientMixin {
  // Garder l'état même quand l'onglet n'est pas visible
  @override
  bool get wantKeepAlive => true;

  String? _selectedCategory;
  Channel? _selectedChannel;
  // Map-based pour correspondre au format retourné par /api/epg/<id>
  List<Map<String, dynamic>> _programmes = [];
  bool _loadingEpg = false;
  String _epgError = '';

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(
      () => setState(() => _searchQuery = _searchCtrl.text.toLowerCase()),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Charge le guide EPG complet via le backend /api/epg/<channelId>
  Future<void> _loadEpg(Channel ch) async {
    setState(() {
      _selectedChannel = ch;
      _programmes = [];
      _loadingEpg = true;
      _epgError = '';
    });

    try {
      final response = await http.get(Uri.parse('/api/epg/${ch.streamId}'));
      if (mounted) {
        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          final list = (data['programmes'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .toList();
          setState(() {
            _programmes = list;
            _loadingEpg = false;
          });
        } else {
          setState(() {
            _epgError = 'Erreur ${response.statusCode}: ${response.body}';
            _loadingEpg = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingEpg = false;
          _epgError = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final settings = ref.watch(iptvSettingsProvider);
    final channelsAsync =
        ref.watch(liveChannelsByPlaylistProvider(widget.playlist));

    return Padding(
      padding: const EdgeInsets.all(16),
      child: channelsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (groupedChannels) {
          final categories = groupedChannels.keys
              .where(
                (cat) =>
                    settings.liveTvKeywords.isEmpty ||
                    settings.matchesLiveTvFilter(cat),
              )
              .toList();

          // Initial category selection
          if (_selectedCategory == null && categories.isNotEmpty) {
            _selectedCategory = categories.first;
          }

          final channelsInCategory = groupedChannels[_selectedCategory] ?? [];
          final visibleChannels = _searchQuery.isEmpty
              ? channelsInCategory
              : groupedChannels.values
                  .expand((l) => l)
                  .where((c) => c.name.toLowerCase().contains(_searchQuery))
                  .toList();

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Colonne 1 : CATÉGORIES ──
              SizedBox(
                width: 180,
                child: Column(
                  children: [
                    Text(
                      'GROUPES',
                      style: GoogleFonts.outfit(
                        color: Colors.white38,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: categories.length,
                        itemBuilder: (ctx, i) {
                          final cat = categories[i];
                          final isSelected = _selectedCategory == cat;
                          return InkWell(
                            onTap: () => setState(() {
                              _selectedCategory = cat;
                              _searchCtrl.clear();
                              _searchQuery = '';
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              margin: const EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.white.withOpacity(0.1)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                cat,
                                style: GoogleFonts.outfit(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white60,
                                  fontSize: 12,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              const VerticalDivider(width: 32, color: Colors.white10),

              // ── Colonne 2 : CHAÎNES ──
              SizedBox(
                width: 250,
                child: Column(
                  children: [
                    // Barre de recherche
                    TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Rechercher...',
                        hintStyle: const TextStyle(
                          color: Colors.white38,
                          fontSize: 13,
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.white38,
                          size: 18,
                        ),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.07),
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: visibleChannels.isEmpty
                          ? const Center(
                              child: Text(
                                'Aucune chaîne',
                                style: TextStyle(
                                  color: Colors.white24,
                                  fontSize: 12,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: visibleChannels.length,
                              itemBuilder: (ctx, i) {
                                final ch = visibleChannels[i];
                                final isSelected =
                                    _selectedChannel?.streamId == ch.streamId;
                                return InkWell(
                                  onTap: () => _loadEpg(ch),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 3),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
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
                                        ch.streamIcon.isNotEmpty
                                            ? Image.network(
                                                ch.streamIcon,
                                                width: 24,
                                                height: 16,
                                                fit: BoxFit.contain,
                                                errorBuilder: (_, __, ___) =>
                                                    const Icon(
                                                  Icons.tv,
                                                  color: Colors.white24,
                                                  size: 16,
                                                ),
                                              )
                                            : const Icon(
                                                Icons.tv,
                                                color: Colors.white24,
                                                size: 16,
                                              ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            ch.name,
                                            style: GoogleFonts.outfit(
                                              color: isSelected
                                                  ? Colors.white
                                                  : Colors.white70,
                                              fontSize: 12,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
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
              ),

              const VerticalDivider(width: 32, color: Colors.white10),

              // ── Colonne droite : programmes EPG ──
              Expanded(
                child: _selectedChannel == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.tv_off,
                              size: 64,
                              color: Color(0x1FFFFFFF),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Sélectionnez une chaîne\npour voir son guide des programmes',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                color: Colors.white38,
                                fontSize: 15,
                              ),
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
                                _selectedChannel!.name,
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(
                                  Icons.refresh,
                                  color: Colors.white54,
                                  size: 18,
                                ),
                                tooltip: 'Recharger l\'EPG',
                                onPressed: () => _loadEpg(_selectedChannel!),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white12),
                          Expanded(
                            child: _loadingEpg
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : _epgError.isNotEmpty
                                    ? Center(
                                        child: Text(
                                          'Erreur EPG: $_epgError',
                                          style: const TextStyle(
                                            color: Colors.redAccent,
                                            fontSize: 12,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      )
                                    : _programmes.isEmpty
                                        ? Center(
                                            child: Text(
                                              'Aucun programme EPG disponible\npour cette chaîne',
                                              textAlign: TextAlign.center,
                                              style: GoogleFonts.outfit(
                                                color: Colors.white38,
                                              ),
                                            ),
                                          )
                                        : ListView.builder(
                                            itemCount: _programmes.length,
                                            itemBuilder: (ctx, i) =>
                                                _ProgrammeCard(
                                              programme: _programmes[i],
                                              channel: _selectedChannel!,
                                            ),
                                          ),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  CARTE DE PROGRAMME EPG
// ═══════════════════════════════════════════════════════════════════════════

class _ProgrammeCard extends StatelessWidget {
  final Map<String, dynamic> programme;
  final Channel channel;

  const _ProgrammeCard({
    required this.programme,
    required this.channel,
  });

  String get _start => programme['start'] as String? ?? '';
  String get _end => programme['end'] as String? ?? '';
  String get _title => programme['title'] as String? ?? '';
  String get _description => programme['description'] as String? ?? '';

  String _fmt(String raw) {
    if (raw.isEmpty) return '';
    try {
      final dt = EpgEntry.parseDateTime(raw)?.toLocal();
      if (dt == null) return raw.length >= 16 ? raw.substring(11, 16) : raw;
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw.length >= 16 ? raw.substring(11, 16) : raw;
    }
  }

  DateTime? _parseTime(String raw) {
    return EpgEntry.parseDateTime(raw);
  }

  bool get _isNow {
    final s = _parseTime(_start);
    final e = _parseTime(_end);
    if (s == null || e == null) return false;
    final now = DateTime.now().toUtc();
    return now.isAfter(s) && now.isBefore(e);
  }

  bool get _isPast {
    final e = _parseTime(_end);
    if (e == null) return false;
    return DateTime.now().toUtc().isAfter(e);
  }

  void _record(BuildContext context) {
    final s = _parseTime(_start);
    final e = _parseTime(_end);
    if (s == null || e == null) return;
    _showConfirm(context, _title, s, e);
  }

  void _showConfirm(
    BuildContext context,
    String title,
    DateTime start,
    DateTime end,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Row(
          children: [
            const Icon(
              Icons.fiber_manual_record,
              color: Colors.redAccent,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Enregistrer',
                style: GoogleFonts.outfit(color: Colors.white),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.isEmpty ? channel.name : title,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_fmt(_start)} → ${_fmt(_end)}',
              style: const TextStyle(color: Colors.white70),
            ),
            if (_description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              await _saveRecording(
                context,
                title.isEmpty ? channel.name : title,
                start,
                end,
              );
            },
            child: const Text('🔴 Enregistrer'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveRecording(
    BuildContext context,
    String title,
    DateTime start,
    DateTime end,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('/api/recordings'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'channel_id': channel.streamId,
          'stream_url': '/api/live/${channel.streamId}.ts',
          'title': title,
          'start_time': start.toIso8601String(),
          'end_time': end.toIso8601String(),
        }),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response.statusCode == 200
                  ? '✅ "$title" planifié !'
                  : '❌ Erreur: ${response.body}',
            ),
            backgroundColor: response.statusCode == 200
                ? Colors.green.shade800
                : Colors.red.shade800,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNow = _isNow;
    final isPast = _isPast;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isNow
            ? Colors.red.withOpacity(0.15)
            : isPast
                ? Colors.white.withOpacity(0.03)
                : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isNow
              ? Colors.redAccent.withOpacity(0.4)
              : Colors.white.withOpacity(0.07),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: SizedBox(
          width: 52,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isNow)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'LIVE',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else
                Text(
                  _fmt(_start),
                  style: GoogleFonts.outfit(
                    color: isPast ? Colors.white24 : Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (!isNow)
                Text(
                  _fmt(_end),
                  style:
                      GoogleFonts.outfit(color: Colors.white24, fontSize: 10),
                ),
            ],
          ),
        ),
        title: Text(
          _title.isEmpty ? '—' : _title,
          style: GoogleFonts.outfit(
            color: isPast ? Colors.white38 : Colors.white,
            fontWeight: isNow ? FontWeight.bold : FontWeight.normal,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: _description.isNotEmpty
            ? Text(
                _description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              )
            : null,
        trailing: !isPast
            ? IconButton(
                icon: const Icon(
                  Icons.fiber_manual_record,
                  color: Colors.redAccent,
                  size: 20,
                ),
                tooltip: 'Enregistrer ce programme',
                onPressed: () => _record(context),
              )
            : null,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  ONGLET 2 — ENREGISTREMENTS
// ═══════════════════════════════════════════════════════════════════════════

class _RecordingsListView extends StatefulWidget {
  final PlaylistConfig playlist;
  const _RecordingsListView({required this.playlist});
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
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await http.get(Uri.parse('/api/recordings'));
      if (response.statusCode == 200) {
        setState(() {
          final decoded = json.decode(response.body);
          _recordings = decoded is List ? decoded : [];
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Erreur ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = '$e';
        _isLoading = false;
      });
    }
  }

  Future<void> _stopRecording(String id, String title) async {
    await http.post(Uri.parse('/api/recordings/stop/$id'));
    _fetchRecordings();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('⏹ "$title" arrêté')));
    }
  }

  Future<void> _deleteRecording(String id) async {
    await http.delete(Uri.parse('/api/recordings/$id'));
    _fetchRecordings();
  }

  Future<void> _playRecording(BuildContext context, Map<String, dynamic> rec) async {
    final recordingId = rec['id'] as String?;
    final title = rec['title'] as String? ?? 'Enregistrement';

    if (recordingId == null || recordingId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ID de lecture indisponible')),
      );
      return;
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => PlayerScreen(
          streamId: recordingId,
          title: title,
          playlist: widget.playlist,
          streamType: StreamType.recording,
          containerExtension: 'ts',
        ),
      ),
    );
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
          title: Text(
            title,
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
          ),
          content: SizedBox(
            width: 500,
            height: 300,
            child: SingleChildScrollView(
              child: Text(
                content,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur logs: $e')));
      }
    }
  }

  Color _statusColor(String status) => switch (status) {
        'recording' => Colors.redAccent,
        'completed' => Colors.green,
        'failed' => Colors.orangeAccent,
        _ => Colors.blueAccent,
      };

  String _statusLabel(String status) => switch (status) {
        'scheduled' => 'Planifié',
        'recording' => '● En cours',
        'completed' => 'Terminé',
        'failed' => 'Échoué',
        _ => status,
      };

  String _fmtDate(dynamic raw) {
    if (raw == null) return '?';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw.toString();
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
                    ? Center(
                        child: Text(
                          _error ?? 'Erreur',
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      )
                    : _recordings.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.videocam_off,
                                  size: 64,
                                  color: Color(0x1FFFFFFF),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Aucun enregistrement',
                                  style: GoogleFonts.outfit(
                                    color: Colors.white38,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _recordings.length,
                            itemBuilder: (ctx, i) {
                              final rec = _recordings[i];
                              final status =
                                  rec['status'] as String? ?? 'unknown';
                              final color = _statusColor(status);
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.1),
                                  ),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  leading: Icon(
                                    status == 'recording'
                                        ? Icons.fiber_manual_record
                                        : Icons.videocam,
                                    color: color,
                                    size: 28,
                                  ),
                                  title: Text(
                                    rec['title'] ?? '—',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${_fmtDate(rec['start_time'])} → ${_fmtDate(rec['end_time'])}',
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12,
                                        ),
                                      ),
                                      if (rec['error_reason'] != null)
                                        Text(
                                          '⚠ ${rec['error_reason']}',
                                          style: const TextStyle(
                                            color: Colors.orangeAccent,
                                            fontSize: 11,
                                          ),
                                        ),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: color.withOpacity(0.15),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border: Border.all(
                                            color: color.withOpacity(0.4),
                                          ),
                                        ),
                                        child: Text(
                                          _statusLabel(status),
                                          style: TextStyle(
                                            color: color,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      if (status == 'recording')
                                        IconButton(
                                          icon: const Icon(
                                            Icons.stop_circle,
                                            color: Colors.redAccent,
                                          ),
                                          tooltip: 'Arrêter',
                                          onPressed: () => _stopRecording(
                                            rec['id'],
                                            rec['title'] ?? '',
                                          ),
                                        ),
                                      if (status == 'completed')
                                        IconButton(
                                          icon: const Icon(
                                            Icons.play_circle_outline,
                                            color: Colors.greenAccent,
                                            size: 20,
                                          ),
                                          tooltip: 'Lecture',
                                          onPressed: () => _playRecording(context, rec),
                                        ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.description_outlined,
                                          color: Colors.blueAccent,
                                          size: 20,
                                        ),
                                        tooltip: 'Logs',
                                        onPressed: () => _showLogs(
                                          rec['id'],
                                          rec['title'] ?? '',
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.white38,
                                          size: 20,
                                        ),
                                        tooltip: 'Supprimer',
                                        onPressed: () =>
                                            _deleteRecording(rec['id']),
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

// ═══════════════════════════════════════════════════════════════════════════
//  ONGLET 3 — SEASON PASSES
// ═══════════════════════════════════════════════════════════════════════════

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
      final r = await http.get(Uri.parse('/api/season-passes'));
      if (r.statusCode == 200) {
        setState(() {
          _passes = json.decode(r.body);
          _isLoading = false;
        });
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Season Pass "$title" supprimé')),
      );
    }
  }

  void _showCreate() {
    final titleCtrl = TextEditingController();
    final channelCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Row(
          children: [
            const Icon(Icons.repeat, color: Colors.purpleAccent),
            const SizedBox(width: 8),
            Text(
              'Nouveau Season Pass',
              style: GoogleFonts.outfit(color: Colors.white),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enregistre automatiquement toutes les nouvelles diffusions d\'une émission.',
                style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              _buildField(
                titleCtrl,
                'Titre de l\'émission (ex: Champions League)',
              ),
              const SizedBox(height: 8),
              _buildField(channelCtrl, 'Channel ID (ex: 554021)'),
              const SizedBox(height: 8),
              _buildField(
                urlCtrl,
                'stream_url (optionnel, ex: /api/live/554021.ts)',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent),
            onPressed: () async {
              final t = titleCtrl.text.trim();
              final c = channelCtrl.text.trim();
              if (t.isEmpty || c.isEmpty) return;
              final u = urlCtrl.text.trim().isEmpty
                  ? '/api/live/$c.ts'
                  : urlCtrl.text.trim();
              Navigator.pop(ctx);
              final r = await http.post(
                Uri.parse('/api/season-passes'),
                headers: {'Content-Type': 'application/json'},
                body: json.encode(
                  {'show_title': t, 'channel_id': c, 'stream_url': u},
                ),
              );
              _loadPasses();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      r.statusCode == 201
                          ? '✅ Season Pass créé !'
                          : '❌ ${r.body}',
                    ),
                  ),
                );
              }
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );
  }

  Widget _buildField(TextEditingController c, String label) {
    return TextField(
      controller: c,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.white24),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.purpleAccent),
        ),
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
              Text(
                'Enregistrements automatiques',
                style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purpleAccent,
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nouveau'),
                onPressed: _showCreate,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.purpleAccent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.purpleAccent.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: Colors.purpleAccent,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Scanne l\'EPG toutes les 4h et programme automatiquement les nouvelles diffusions. Seuls les nouveaux épisodes sont enregistrés.',
                    style: GoogleFonts.outfit(
                      color: Colors.purpleAccent.shade100,
                      fontSize: 12,
                    ),
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
                            const Icon(
                              Icons.repeat,
                              size: 64,
                              color: Color(0x1FFFFFFF),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Aucun Season Pass actif',
                              style: GoogleFonts.outfit(
                                color: Colors.white38,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Créez-en un pour enregistrer automatiquement vos émissions préférées',
                              style: GoogleFonts.outfit(
                                color: Colors.white24,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _passes.length,
                        itemBuilder: (ctx, i) {
                          final p = _passes[i];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.purpleAccent.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.purpleAccent.withOpacity(0.2),
                              ),
                            ),
                            child: ListTile(
                              leading: const Icon(
                                Icons.repeat,
                                color: Colors.purpleAccent,
                              ),
                              title: Text(
                                p['show_title'] ?? '—',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Chaîne : ${p['channel_id']}',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                  Text(
                                    'Flux : ${p['stream_url']}',
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.white38,
                                ),
                                tooltip: 'Supprimer',
                                onPressed: () =>
                                    _deletePass(p['id'], p['show_title'] ?? ''),
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
