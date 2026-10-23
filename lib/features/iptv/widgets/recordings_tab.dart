import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/api/authed_http.dart';
import '../../../core/api/recording_requests.dart';
import '../../../core/api/channel_logo.dart';
import '../../../core/models/iptv_models.dart';
import '../../../core/models/playlist_config.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/playback_positions_provider.dart';
import '../providers/recordings_refresh.dart';
import '../providers/xtream_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/player_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  ENTRÉE — Onglet "Enregistrements"
//  Quatre vues : Guide TV (programmer depuis l'EPG), Enregistrements (liste),
//  Season Passes (enregistrements récurrents), Auto NBA (matchs en direct
//  sur beIN Sports FR). _EpgGuideView et
//  _SeasonPassesView existaient déjà mais n'étaient plus instanciés depuis
//  une refonte : les fonctions étaient codées mais inaccessibles.
// ═══════════════════════════════════════════════════════════════════════════

class RecordingsTab extends StatefulWidget {
  final PlaylistConfig playlist;
  const RecordingsTab({super.key, required this.playlist});

  @override
  State<RecordingsTab> createState() => _RecordingsTabState();
}

class _RecordingsTabState extends State<RecordingsTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    // Ouvrir sur la liste des enregistrements (onglet du milieu), l'usage le
    // plus fréquent ; le guide sert à en programmer de nouveaux.
    _tabController = TabController(length: 4, vsync: this, initialIndex: 1);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Guide, enregistrements, season passes et Auto NBA visent cette IPTV.
    AuthedHttp.usePlaylist(widget.playlist.id);
    return Container(
      color: Colors.black,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            color: Colors.grey[900],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.videocam, color: AppColors.onSurface, size: 28),
                    SizedBox(width: 12),
                    Text(
                      'Enregistrements',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  indicatorColor: AppColors.primary,
                  labelColor: AppColors.onSurface,
                  unselectedLabelColor: AppColors.onSurface54,
                  tabs: const [
                    Tab(
                      icon: Icon(Icons.calendar_month, size: 18),
                      text: 'Guide TV',
                    ),
                    Tab(
                      icon: Icon(Icons.fiber_manual_record, size: 18),
                      text: 'Enregistrements',
                    ),
                    Tab(
                      icon: Icon(Icons.repeat, size: 18),
                      text: 'Season Passes',
                    ),
                    Tab(
                      icon: Icon(Icons.sports_basketball, size: 18),
                      text: 'Auto NBA',
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _EpgGuideView(playlist: widget.playlist),
                _RecordingsListView(playlist: widget.playlist),
                const _SeasonPassesView(),
                _AutoNbaView(playlist: widget.playlist),
              ],
            ),
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
      final response = await AuthedHttp.get(Uri.parse('/api/epg/${ch.streamId}'));
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
                      style: GoogleFonts.fraunces(
                        color: AppColors.onSurface38,
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
                                    ? AppColors.onSurface.withOpacity(0.1)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                cat,
                                style: GoogleFonts.fraunces(
                                  color: isSelected
                                      ? AppColors.onSurface
                                      : AppColors.onSurface54,
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

              const VerticalDivider(width: 32, color: AppColors.onSurface06),

              // ── Colonne 2 : CHAÎNES ──
              SizedBox(
                width: 250,
                child: Column(
                  children: [
                    // Barre de recherche
                    TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(color: AppColors.onSurface, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Rechercher...',
                        hintStyle: const TextStyle(
                          color: AppColors.onSurface38,
                          fontSize: 13,
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: AppColors.onSurface38,
                          size: 18,
                        ),
                        filled: true,
                        fillColor: AppColors.onSurface.withOpacity(0.07),
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
                                  color: AppColors.onSurface24,
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
                                          ? AppColors.live.withOpacity(0.2)
                                          : AppColors.onSurface.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSelected
                                            ? AppColors.live.withOpacity(0.5)
                                            : Colors.transparent,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        // URL panneau brute auparavant : en
                                        // http depuis une page https, le
                                        // navigateur la bloquait.
                                        Image.network(
                                          channelLogoUrl(
                                            streamIcon: ch.streamIcon,
                                            name: ch.name,
                                          ),
                                          width: 24,
                                          height: 16,
                                          cacheWidth: 64,
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(
                                            Icons.tv,
                                            color: AppColors.onSurface24,
                                            size: 16,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            ch.name,
                                            style: GoogleFonts.fraunces(
                                              color: isSelected
                                                  ? AppColors.onSurface
                                                  : AppColors.onSurfaceVariant,
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

              const VerticalDivider(width: 32, color: AppColors.onSurface06),

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
                              color: AppColors.glassLevel1Border,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Sélectionnez une chaîne\npour voir son guide des programmes',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.fraunces(
                                color: AppColors.onSurface38,
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
                                style: GoogleFonts.fraunces(
                                  color: AppColors.onSurface,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(
                                  Icons.refresh,
                                  color: AppColors.onSurface54,
                                  size: 18,
                                ),
                                tooltip: 'Recharger l\'EPG',
                                onPressed: () => _loadEpg(_selectedChannel!),
                              ),
                            ],
                          ),
                          const Divider(color: AppColors.onSurface12),
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
                                            color: AppColors.live,
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
                                              style: GoogleFonts.fraunces(
                                                color: AppColors.onSurface38,
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
        backgroundColor: AppColors.surfaceContainer,
        title: Row(
          children: [
            const Icon(
              Icons.fiber_manual_record,
              color: AppColors.live,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Enregistrer',
                style: GoogleFonts.fraunces(color: AppColors.onSurface),
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
              style: GoogleFonts.fraunces(
                color: AppColors.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_fmt(_start)} → ${_fmt(_end)}',
              style: const TextStyle(color: AppColors.onSurfaceVariant),
            ),
            if (_description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.onSurface38, fontSize: 12),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.errorContainer,
              foregroundColor: AppColors.onErrorContainer,
            ),
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
      // Les horaires EPG sont des heures UTC naïves : wallClockIsUtc les
      // re-tague sans décalage (l'ancien envoi naïf était interprété dans le
      // fuseau du serveur → enregistrement décalé de 1-2 h).
      final response = await postRecording(
        channelId: channel.streamId,
        title: title,
        start: start,
        end: end,
        wallClockIsUtc: true,
      );
      if (response.statusCode == 200) notifyRecordingsChanged();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response.statusCode == 200
                  ? '✅ "$title" planifié !'
                  : '❌ Erreur: ${response.body}',
            ),
            backgroundColor: AppColors.surfaceContainerHigh,
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
            ? AppColors.live.withValues(alpha: 0.15)
            : isPast
                ? AppColors.onSurface.withOpacity(0.03)
                : AppColors.onSurface.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isNow
              ? AppColors.live.withOpacity(0.4)
              : AppColors.onSurface.withOpacity(0.07),
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
                    color: AppColors.live,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'LIVE',
                    style: GoogleFonts.fraunces(
                      color: AppColors.onSurface,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else
                Text(
                  _fmt(_start),
                  style: GoogleFonts.fraunces(
                    color: isPast ? AppColors.onSurface24 : AppColors.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (!isNow)
                Text(
                  _fmt(_end),
                  style:
                      GoogleFonts.fraunces(color: AppColors.onSurface24, fontSize: 10),
                ),
            ],
          ),
        ),
        title: Text(
          _title.isEmpty ? '—' : _title,
          style: GoogleFonts.fraunces(
            color: isPast ? AppColors.onSurface38 : AppColors.onSurface,
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
                style: const TextStyle(color: AppColors.onSurface38, fontSize: 11),
              )
            : null,
        trailing: !isPast
            ? IconButton(
                icon: const Icon(
                  Icons.fiber_manual_record,
                  color: AppColors.live,
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

class _RecordingsListView extends ConsumerStatefulWidget {
  final PlaylistConfig playlist;
  const _RecordingsListView({required this.playlist});
  @override
  ConsumerState<_RecordingsListView> createState() =>
      _RecordingsListViewState();
}

class _RecordingsListViewState extends ConsumerState<_RecordingsListView> {
  List<dynamic> _recordings = [];
  bool _isLoading = true;
  String? _error;
  Timer? _pollTimer;
  DateTime? _lastRefresh;

  // Polling rapproché quand un enregistrement est en cours, plus espacé sinon.
  static const _activeInterval = Duration(seconds: 5);
  static const _idleInterval = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    recordingsRefreshBus.addListener(_onExternalChange);
    _fetchRecordings();
  }

  @override
  void dispose() {
    recordingsRefreshBus.removeListener(_onExternalChange);
    _pollTimer?.cancel();
    super.dispose();
  }

  /// Un enregistrement vient d'être créé/modifié ailleurs dans l'app.
  void _onExternalChange() {
    _fetchRecordings(silent: true);
  }

  bool get _hasActiveOrPending => _recordings.any((rec) {
        final status = rec is Map ? rec['status'] as String? : null;
        return status == 'recording' || status == 'scheduled';
      });

  void _scheduleNextPoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer(
      _hasActiveOrPending ? _activeInterval : _idleInterval,
      () => _fetchRecordings(silent: true),
    );
  }

  /// [silent] : recharge en arrière-plan sans spinner ni vidage de la liste,
  /// pour que le suivi automatique ne fasse pas clignoter l'écran.
  Future<void> _fetchRecordings({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final response = await AuthedHttp.get(Uri.parse('/api/recordings'));
      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() {
          final decoded = json.decode(response.body);
          _recordings = decoded is List ? decoded : [];
          _isLoading = false;
          _error = null;
          _lastRefresh = DateTime.now();
        });
      } else if (!silent) {
        setState(() {
          _error = 'Erreur ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      // En mode silencieux on garde la liste affichée plutôt que
      // de remplacer l'écran par une erreur transitoire.
      if (!silent) {
        setState(() {
          _error = '$e';
          _isLoading = false;
        });
      }
    } finally {
      if (mounted) _scheduleNextPoll();
    }
  }

  Future<void> _stopRecording(String id, String title) async {
    await AuthedHttp.post(Uri.parse('/api/recordings/stop/$id'));
    _fetchRecordings();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('⏹ "$title" arrêté')));
    }
  }

  /// Demande confirmation avant suppression : l'ancienne corbeille supprimait
  /// immédiatement, sans retour ni possibilité d'annuler.
  Future<void> _deleteRecording(String id, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainer,
        title: Text(
          'Supprimer l\'enregistrement ?',
          style: GoogleFonts.fraunces(color: AppColors.onSurface, fontSize: 18),
        ),
        content: Text(
          '« $title » et son fichier seront définitivement supprimés.',
          style: const TextStyle(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.errorContainer,
              foregroundColor: AppColors.onErrorContainer,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await AuthedHttp.delete(Uri.parse('/api/recordings/$id'));
    _fetchRecordings();
  }

  /// Clé de reprise d'un enregistrement (même convention que le lecteur).
  static String _resumeKey(String recordingId) => 'rec_$recordingId';

  /// Position sauvegardée, ou 0 s'il n'y en a pas d'exploitable.
  double _savedPosition(Map<String, dynamic> rec) {
    final id = rec['id'] as String?;
    if (id == null || id.isEmpty) return 0;
    return ref.read(playbackPositionsProvider).getPosition(_resumeKey(id));
  }

  /// Durée du média : celle mesurée par le serveur si disponible, sinon la
  /// durée programmée. Un enregistrement arrêté en avance est plus court que
  /// `end_time - start_time`.
  Duration? _recordingDuration(Map<String, dynamic> rec) {
    final probed = rec['duration_seconds'];
    if (probed is num && probed > 0) {
      return Duration(seconds: probed.round());
    }
    try {
      if (rec['start_time'] != null && rec['end_time'] != null) {
        final start = DateTime.parse(rec['start_time'].toString());
        final end = DateTime.parse(rec['end_time'].toString());
        final scheduled = end.difference(start);
        if (scheduled > Duration.zero) return scheduled;
      }
    } catch (_) {}
    return null;
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

    final recordingDuration = _recordingDuration(rec);
    final saved = _savedPosition(rec);

    // Reprise proposée, jamais imposée : un enregistrement déjà vu se
    // relance parfois depuis le début.
    double? startAt;
    if (saved > 30) {
      if (!mounted) return;
      final resume = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surfaceContainer,
          title: Text(
            'Reprendre la lecture ?',
            style: GoogleFonts.fraunces(color: AppColors.onSurface),
          ),
          content: Text(
            '« $title » a été interrompu à '
            '${PlaybackPositionsNotifier.formatTime(saved)}.',
            style: const TextStyle(color: AppColors.onSurfaceVariant),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Depuis le début'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Reprendre'),
            ),
          ],
        ),
      );
      if (resume == null) return; // dialogue fermé : on n'ouvre rien
      if (resume) {
        startAt = saved;
      } else {
        ref
            .read(playbackPositionsProvider.notifier)
            .clearPosition(_resumeKey(recordingId));
      }
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => PlayerScreen(
          streamId: recordingId,
          title: title,
          playlist: widget.playlist,
          streamType: StreamType.recording,
          containerExtension: 'ts',
          duration: recordingDuration,
          startTime: startAt,
        ),
      ),
    );
    // Au retour du lecteur, la progression affichée dans la liste doit
    // refléter la position atteinte.
    if (mounted) setState(() {});
  }

  /// Barre « déjà vu jusqu'ici » sous un enregistrement entamé.
  List<Widget> _buildResumeIndicator(Map<String, dynamic> rec) {
    final saved = _savedPosition(rec);
    if (saved <= 30) return const [];

    final total = _recordingDuration(rec)?.inSeconds ?? 0;
    final ratio = total > 0 ? (saved / total).clamp(0.0, 1.0) : null;

    return [
      const SizedBox(height: 6),
      Row(
        children: [
          if (ratio != null)
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 4,
                  backgroundColor: AppColors.onSurface.withOpacity(0.1),
                  valueColor:
                      const AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
            ),
          if (ratio != null) const SizedBox(width: 8),
          Text(
            'Reprendre à ${PlaybackPositionsNotifier.formatTime(saved)}',
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    ];
  }

  /// Message `error` renvoyé par l'API, précédé d'un séparateur.
  String _errorDetail(String body) {
    try {
      final error = json.decode(body)['error'];
      return error is String && error.isNotEmpty ? ' : $error' : '';
    } catch (_) {
      return '';
    }
  }

  Future<void> _showLogs(String id, String title) async {
    try {
      final response = await AuthedHttp.get(Uri.parse('/api/recordings/logs/$id'));
      if (!mounted) return;
      final content = response.statusCode == 200
          ? (json.decode(response.body)['logs'] as String? ?? 'Aucun log')
          : 'Logs non disponibles (${response.statusCode})${_errorDetail(response.body)}';
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surfaceContainer,
          title: Text(
            title,
            style: GoogleFonts.fraunces(color: AppColors.onSurface, fontSize: 14),
          ),
          content: SizedBox(
            width: 500,
            height: 300,
            child: SingleChildScrollView(
              child: Text(
                content,
                style: const TextStyle(
                  color: AppColors.onSurfaceVariant,
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
        'recording' => AppColors.live,
        'completed' => AppColors.success,
        'failed' => AppColors.warning,
        'cancelled' => AppColors.onSurface38,
        _ => AppColors.primaryContainer,
      };

  String _statusLabel(String status) => switch (status) {
        'scheduled' => 'Planifié',
        'recording' => '● En cours',
        'completed' => 'Terminé',
        'failed' => 'Échoué',
        'cancelled' => 'Annulé',
        _ => status,
      };

  String _fmtSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} Go';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} Mo';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} Ko';
  }

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
    // Les positions de reprise arrivent de façon asynchrone (SharedPreferences)
    // et changent au retour du lecteur : sans cette écoute, la mention
    // « Reprendre à … » n'apparaîtrait qu'au prochain rafraîchissement.
    ref.watch(playbackPositionsProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(
                Icons.autorenew,
                color: _hasActiveOrPending
                    ? AppColors.success
                    : AppColors.onSurface38,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                _lastRefresh == null
                    ? 'Suivi automatique'
                    : 'Suivi auto · ${_lastRefresh!.hour.toString().padLeft(2, '0')}:${_lastRefresh!.minute.toString().padLeft(2, '0')}:${_lastRefresh!.second.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  color: AppColors.onSurface38,
                  fontSize: 11,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: AppColors.onSurfaceVariant),
                onPressed: _fetchRecordings,
                tooltip: 'Rafraîchir maintenant',
              ),
            ],
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Impossible de charger les enregistrements',
                              style: TextStyle(color: AppColors.live),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('Réessayer'),
                              onPressed: _fetchRecordings,
                            ),
                          ],
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
                                  color: AppColors.glassLevel1Border,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Aucun enregistrement',
                                  style: GoogleFonts.fraunces(
                                    color: AppColors.onSurface38,
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
                                  color: AppColors.onSurface.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.onSurface.withOpacity(0.1),
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
                                    style: GoogleFonts.fraunces(
                                      color: AppColors.onSurface,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${_fmtDate(rec['start_time'])} → ${_fmtDate(rec['end_time'])}'
                                        '${rec['file_size_bytes'] is int ? ' · ${_fmtSize(rec['file_size_bytes'] as int)}' : ''}',
                                        style: const TextStyle(
                                          color: AppColors.onSurface54,
                                          fontSize: 12,
                                        ),
                                      ),
                                      if (status == 'recording' &&
                                          rec['progress_pct'] is int) ...[
                                        const SizedBox(height: 6),
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(3),
                                          child: LinearProgressIndicator(
                                            value:
                                                (rec['progress_pct'] as int) /
                                                    100,
                                            minHeight: 4,
                                            backgroundColor: AppColors
                                                .onSurface
                                                .withOpacity(0.1),
                                            valueColor:
                                                const AlwaysStoppedAnimation(
                                              AppColors.live,
                                            ),
                                          ),
                                        ),
                                      ],
                                      if (status == 'completed')
                                        ..._buildResumeIndicator(rec),
                                      if (rec['error_reason'] != null)
                                        Text(
                                          '⚠ ${rec['error_reason']}',
                                          style: const TextStyle(
                                            color: AppColors.warning,
                                            fontSize: 11,
                                          ),
                                        ),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (rec['source_rule_id'] != null) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.tertiary
                                                .withOpacity(0.15),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            border: Border.all(
                                              color: AppColors.tertiary
                                                  .withOpacity(0.4),
                                            ),
                                          ),
                                          child: const Text(
                                            'Auto NBA',
                                            style: TextStyle(
                                              color: AppColors.tertiary,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                      ],
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
                                            color: AppColors.live,
                                          ),
                                          tooltip: 'Arrêter',
                                          onPressed: () => _stopRecording(
                                            rec['id'],
                                            rec['title'] ?? '',
                                          ),
                                        ),
                                      if (status == 'completed')
                                        IconButton(
                                          icon: Icon(
                                            _savedPosition(rec) > 30
                                                ? Icons.play_circle_fill
                                                : Icons.play_circle_outline,
                                            color: AppColors.success,
                                            size: 20,
                                          ),
                                          tooltip: _savedPosition(rec) > 30
                                              ? 'Reprendre'
                                              : 'Lecture',
                                          onPressed: () =>
                                              _playRecording(context, rec),
                                        ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.description_outlined,
                                          color: AppColors.primaryContainer,
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
                                          color: AppColors.onSurface38,
                                          size: 20,
                                        ),
                                        tooltip: 'Supprimer',
                                        onPressed: () => _deleteRecording(
                                          rec['id'],
                                          rec['title'] ?? '',
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
      final r = await AuthedHttp.get(Uri.parse('/api/season-passes'));
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
    await AuthedHttp.delete(Uri.parse('/api/season-passes/$id'));
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
        backgroundColor: AppColors.surfaceContainer,
        title: Row(
          children: [
            const Icon(Icons.repeat, color: AppColors.secondary),
            const SizedBox(width: 8),
            Text(
              'Nouveau Season Pass',
              style: GoogleFonts.fraunces(color: AppColors.onSurface),
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
                style: GoogleFonts.fraunces(color: AppColors.onSurface54, fontSize: 13),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondaryContainer,
              foregroundColor: AppColors.onSecondaryContainer,
            ),
            onPressed: () async {
              final t = titleCtrl.text.trim();
              final c = channelCtrl.text.trim();
              if (t.isEmpty || c.isEmpty) return;
              final u = urlCtrl.text.trim().isEmpty
                  ? '/api/live/$c.ts'
                  : urlCtrl.text.trim();
              Navigator.pop(ctx);
              final r = await AuthedHttp.post(
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
      style: const TextStyle(color: AppColors.onSurface),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.onSurface54, fontSize: 12),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.onSurface24),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.secondary),
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
                style: GoogleFonts.fraunces(color: AppColors.onSurface54, fontSize: 13),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondaryContainer,
                  foregroundColor: AppColors.onSecondaryContainer,
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
              color: AppColors.secondary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.secondary.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: AppColors.secondary,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Scanne l\'EPG toutes les 4h et programme automatiquement les nouvelles diffusions. Seuls les nouveaux épisodes sont enregistrés.',
                    style: GoogleFonts.fraunces(
                      color: AppColors.secondaryFixed,
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
                              color: AppColors.glassLevel1Border,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Aucun Season Pass actif',
                              style: GoogleFonts.fraunces(
                                color: AppColors.onSurface38,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Créez-en un pour enregistrer automatiquement vos émissions préférées',
                              style: GoogleFonts.fraunces(
                                color: AppColors.onSurface24,
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
                              color: AppColors.secondary.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.secondary.withOpacity(0.2),
                              ),
                            ),
                            child: ListTile(
                              leading: const Icon(
                                Icons.repeat,
                                color: AppColors.secondary,
                              ),
                              title: Text(
                                p['show_title'] ?? '—',
                                style: GoogleFonts.fraunces(
                                  color: AppColors.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Chaîne : ${p['channel_id']}',
                                    style: const TextStyle(
                                      color: AppColors.onSurface54,
                                      fontSize: 11,
                                    ),
                                  ),
                                  Text(
                                    'Flux : ${p['stream_url']}',
                                    style: const TextStyle(
                                      color: AppColors.onSurface38,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: AppColors.onSurface38,
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

// ═══════════════════════════════════════════════════════════════════════════
//  ONGLET 4 — AUTO NBA
//  Règle serveur `/api/auto-rules` : enregistre chaque match NBA diffusé EN
//  DIRECT sur les beIN Sports françaises (jamais les rediffusions). Le
//  calendrier NBA donne les matchs des semaines à l'avance ; l'EPG confirme
//  la chaîne ~48 h avant. Chaque match peut être accepté ou refusé d'avance.
// ═══════════════════════════════════════════════════════════════════════════

const _jours = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
const _mois = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

class _AutoNbaView extends StatefulWidget {
  /// IPTV dont la règle est affichée et qui capture les matchs choisis.
  final PlaylistConfig playlist;
  const _AutoNbaView({required this.playlist});
  @override
  State<_AutoNbaView> createState() => _AutoNbaViewState();
}

class _AutoNbaViewState extends State<_AutoNbaView> {
  Map<String, dynamic>? _rule;
  List<dynamic> _games = [];
  bool _isLoading = true;
  bool _busy = false;
  String? _error;
  bool _showOffBein = false;
  // Liste des chaînes en cours de chargement avant l'ouverture des réglages :
  // sans ce verrou, chaque clic ouvrait un dialogue de plus, et enregistrer
  // celui du dessus découvrait l'ancienne sélection en dessous.
  bool _openingSettings = false;
  // Dernier diagnostic serveur : source, diffusions, chaînes reliées.
  Map<String, dynamic>? _diag;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _AutoNbaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Autre IPTV : autre règle, autres matchs choisis.
    if (oldWidget.playlist.id != widget.playlist.id) {
      AuthedHttp.usePlaylist(widget.playlist.id);
      setState(() {
        _rule = null;
        _games = [];
        _diag = null;
      });
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = _rule == null;
      _error = null;
    });
    try {
      final r = await AuthedHttp.get(Uri.parse('/api/auto-rules'));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final rules = (json.decode(r.body) as List)
          .where((x) => x['kind'] == 'nba')
          .toList();
      if (rules.isEmpty) {
        if (!mounted) return;
        setState(() {
          _rule = null;
          _games = [];
          _isLoading = false;
        });
        return;
      }
      final rule = rules.first as Map<String, dynamic>;
      final g = await AuthedHttp.get(
        Uri.parse('/api/auto-rules/${rule['id']}/games?days=21'),
      );
      if (g.statusCode != 200) throw Exception('HTTP ${g.statusCode}');
      if (!mounted) return;
      setState(() {
        _rule = rule;
        final body = json.decode(g.body);
        _games = body['games'] as List;
        _diag = body['diagnostic'] as Map<String, dynamic>?;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _isLoading = false;
      });
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _createRule() async {
    setState(() => _busy = true);
    final r = await AuthedHttp.post(
      Uri.parse('/api/auto-rules'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({}),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.statusCode == 201) {
      final channels = (json.decode(r.body)['channel_ids'] as List).length;
      _snack('✅ Auto NBA activé · $channels chaîne(s) beIN Sports FR');
      await _load();
      // Le calendrier se charge en tâche de fond côté serveur.
      Future.delayed(const Duration(seconds: 8), () {
        if (mounted) _load();
      });
    } else {
      _snack('❌ ${r.body}');
    }
  }

  Future<void> _updateRule(Map<String, dynamic> changes) async {
    final id = _rule?['id'];
    if (id == null) return;
    final r = await AuthedHttp.put(
      Uri.parse('/api/auto-rules/$id'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(changes),
    );
    if (!mounted) return;
    if (r.statusCode == 200) {
      setState(() => _rule = json.decode(r.body) as Map<String, dynamic>);
      // La réconciliation tourne en tâche de fond : relire peu après.
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) _load();
      });
    } else {
      _snack('❌ ${r.body}');
    }
  }

  Future<void> _refreshNow() async {
    final id = _rule?['id'];
    if (id == null) return;
    setState(() => _busy = true);
    final r = await AuthedHttp.post(Uri.parse('/api/auto-rules/$id/refresh'));
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.statusCode == 200) {
      final body = json.decode(r.body);
      setState(() {
        _games = body['games'] as List;
        _diag = body['diagnostic'] as Map<String, dynamic>?;
      });
      notifyRecordingsChanged();
    } else {
      _snack('❌ ${r.body}');
    }
  }

  Future<void> _decide(Map<String, dynamic> game, bool yes) async {
    final id = _rule?['id'];
    if (id == null || _busy) return;
    // Tous les boutons sont figés pendant la requête : pas de double clic ni
    // de second choix sur le même créneau avant la réponse.
    setState(() => _busy = true);
    try {
      final r = await AuthedHttp.post(
        Uri.parse('/api/auto-rules/$id/games/${game['game_id']}/decision'),
        headers: {'Content-Type': 'application/json'},
        // Retirer son choix remet le match en attente : rien n'est
        // enregistré sans un oui explicite.
        body: json.encode({'decision': yes ? 'accepted' : 'auto'}),
      );
      if (!mounted) return;
      if (r.statusCode == 200) {
        notifyRecordingsChanged();
      } else {
        String message = r.body;
        try {
          message = json.decode(r.body)['error'] ?? r.body;
        } catch (_) {}
        _snack('❌ $message');
      }
      // Relire toute la liste : le serveur recalcule « Créneau pris » pour
      // les autres matchs du créneau, qui deviennent inactifs.
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Réglages ────────────────────────────────────────────────────────────

  Future<void> _showSettings() async {
    final rule = _rule;
    if (rule == null || _openingSettings) return;
    setState(() => _openingSettings = true);
    List<dynamic> channels = [];
    try {
      final r = await AuthedHttp.get(
        Uri.parse('/api/auto-rules/${rule['id']}/channels'),
      );
      if (r.statusCode == 200) {
        channels = json.decode(r.body)['channels'] as List;
      }
    } finally {
      if (mounted) setState(() => _openingSettings = false);
    }
    if (!mounted) return;

    final selected = <String>{
      for (final c in (rule['channel_ids'] as List)) c.toString(),
    };
    final beforeCtrl =
        TextEditingController(text: '${rule['pad_before_min'] ?? 5}');
    final afterCtrl =
        TextEditingController(text: '${rule['pad_after_min'] ?? 45}');
    final keepCtrl = TextEditingController(
      text: rule['keep_days'] == null ? '' : '${rule['keep_days']}',
    );
    // Françaises d'abord ; les autres restent sélectionnables en cas
    // d'erreur de détection.
    final fr = channels.where((c) => c['is_fr'] == true).toList();
    final others = channels.where((c) => c['is_fr'] != true).toList();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          Widget channelRow(dynamic c) => SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  c['label'] ?? c['name'],
                  style: GoogleFonts.fraunces(
                    color: AppColors.onSurface,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  c['name'] ?? '',
                  style: const TextStyle(
                    color: AppColors.onSurface38,
                    fontSize: 11,
                  ),
                ),
                value: selected.contains(c['stream_id'].toString()),
                activeThumbColor: AppColors.primary,
                trackColor: _switchTrack,
                onChanged: (v) => setDialog(() {
                  final id = c['stream_id'].toString();
                  v ? selected.add(id) : selected.remove(id);
                }),
              );
          return AlertDialog(
            backgroundColor: AppColors.surfaceContainer,
            title: Row(
              children: [
                const Icon(Icons.sports_basketball, color: AppColors.secondary),
                const SizedBox(width: 8),
                Text(
                  'Réglages Auto NBA',
                  style: GoogleFonts.fraunces(color: AppColors.onSurface),
                ),
              ],
            ),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _underlineField(
                            beforeCtrl,
                            'Marge avant (min)',
                            number: true,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _underlineField(
                            afterCtrl,
                            'Marge après (min)',
                            number: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _underlineField(
                      keepCtrl,
                      'Garder les matchs (jours, vide = toujours)',
                      number: true,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Chaînes beIN Sports françaises',
                      style: GoogleFonts.fraunces(
                        color: AppColors.onSurface54,
                        fontSize: 13,
                      ),
                    ),
                    if (fr.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Aucune beIN Sports FR détectée dans la playlist',
                          style: TextStyle(
                            color: AppColors.warning,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ...fr.map(channelRow),
                    if (others.isNotEmpty)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(
                          'Autres beIN (${others.length})',
                          style: GoogleFonts.fraunces(
                            color: AppColors.onSurface54,
                            fontSize: 13,
                          ),
                        ),
                        children: others.map(channelRow).toList(),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondaryContainer,
                  foregroundColor: AppColors.onSecondaryContainer,
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  final keep = int.tryParse(keepCtrl.text.trim());
                  _updateRule({
                    'channel_ids': selected.toList(),
                    'pad_before_min':
                        int.tryParse(beforeCtrl.text.trim()) ?? 5,
                    'pad_after_min': int.tryParse(afterCtrl.text.trim()) ?? 45,
                    'keep_days': (keep != null && keep > 0) ? keep : null,
                  });
                },
                child: const Text('Enregistrer'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _underlineField(
    TextEditingController c,
    String label, {
    bool number = false,
  }) {
    return TextField(
      controller: c,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: AppColors.onSurface),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.onSurface54, fontSize: 12),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.onSurface24),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.secondary),
        ),
      ),
    );
  }

  // ── Présentation ────────────────────────────────────────────────────────

  (String, Color) _status(Map<String, dynamic> g) {
    if (g['conflict'] == true) return ('Conflit', AppColors.warning);
    return switch (g['status']) {
      'scheduled' => ('Programmé', AppColors.primaryContainer),
      'confirmed' => ('Confirmé', AppColors.tertiary),
      'recorded' => ('Enregistré', AppColors.success),
      'missed' => ('Manqué', AppColors.warning),
      'not_on_bein' => ('Pas sur beIN', AppColors.onSurface38),
      _ => ('Prévu', AppColors.onSurface38),
    };
  }

  /// Résumé du dernier passage serveur, pour comprendre une liste vide.
  String? _diagText() {
    final d = _diag;
    if (d == null) return null;
    final parts = <String>[];
    final calendar = d['games_in_calendar'];
    if (calendar == 0) parts.add('Calendrier NBA vide ou injoignable');
    if (d['source'] == 'bein') {
      parts.add('${d['live_broadcasts'] ?? 0} direct(s) NBA au guide beIN');
    } else if (d['source'] == 'iptv') {
      parts.add('Guide beIN injoignable, repli sur le guide IPTV');
    }
    if (d['has_playlist'] == false) parts.add('aucune playlist IPTV');
    final linked = (d['linked_channels'] as List?) ?? const [];
    parts.add(
      linked.isEmpty
          ? 'aucune beIN trouvée dans la playlist'
          : '${linked.length} beIN reliée(s) à la playlist',
    );
    final missing = (d['missing_channels'] as List?) ?? const [];
    if (missing.isNotEmpty) parts.add('absentes : ${missing.join(', ')}');
    if (d['matched_games'] != null) {
      parts.add('${d['matched_games']} match(s) rapproché(s)');
    }
    return parts.join(' · ');
  }

  /// Nuit de diffusion : un match à 02:30 appartient à la nuit de la veille.
  String _nightLabel(DateTime local) {
    final d = local.subtract(const Duration(hours: 12));
    return 'Nuit du ${_jours[d.weekday - 1]} ${d.day} ${_mois[d.month - 1]}';
  }

  String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// Piste lisible quel que soit l'état (même rendu que l'interrupteur de
  /// thème des Réglages) : sans elle, curseur et piste orange se confondent.
  static final _switchTrack = WidgetStateProperty.resolveWith<Color>(
    (states) => states.contains(WidgetState.selected)
        ? AppColors.primary.withOpacity(0.5)
        : AppColors.surfaceContainerHigh,
  );

  /// Choix explicite par match : rien n'est enregistré sans ce bouton.
  Widget _choiceButton(Map<String, dynamic> g, bool locked) {
    const compact = VisualDensity.compact;
    if (g['wanted'] == true) {
      return Tooltip(
        message: locked ? 'Choisi' : 'Cliquer pour ne plus enregistrer',
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.secondaryContainer,
            foregroundColor: AppColors.onSecondaryContainer,
            visualDensity: compact,
          ),
          icon: const Icon(Icons.check, size: 16),
          label: const Text('Choisi'),
          onPressed: (locked || _busy) ? null : () => _decide(g, false),
        ),
      );
    }
    final taken = g['slot_taken_by'] as String?;
    if (taken != null) {
      return Tooltip(
        message: 'Créneau déjà pris par « $taken » : un seul enregistrement '
            'à la fois',
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(visualDensity: compact),
          icon: const Icon(Icons.block, size: 16),
          label: const Text('Créneau pris'),
          onPressed: null,
        ),
      );
    }
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(visualDensity: compact),
      icon: const Icon(Icons.fiber_manual_record, size: 16),
      label: const Text('Enregistrer'),
      onPressed: (locked || _busy) ? null : () => _decide(g, true),
    );
  }

  Widget _pill(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
      );

  Widget _gameCard(Map<String, dynamic> g) {
    final tipoff = DateTime.parse(g['tipoff_utc']).toLocal();
    final (label, color) = _status(g);
    final channel = g['channel_name'] as String?;
    // Chaîne beIN reliée à un flux de la playlist : sinon pas d'enregistrement.
    final recordable = g['channel_id'] != null;
    final locked =
        ['recorded', 'missed', 'not_on_bein'].contains(g['status']) ||
            tipoff.isBefore(DateTime.now()) ||
            (!recordable && g['wanted'] != true);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.onSurface.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.onSurface.withOpacity(0.1)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            g['artwork_url'],
            width: 128,
            height: 72,
            cacheWidth: 256,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox(
              width: 128,
              height: 72,
              child: Icon(
                Icons.sports_basketball,
                color: AppColors.onSurface24,
              ),
            ),
          ),
        ),
        title: Text(
          '${g['away']} @ ${g['home']}',
          style: GoogleFonts.fraunces(
            color: AppColors.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_hhmm(tipoff)} · ${channel ?? 'pas annoncé sur beIN'}'
              '${channel != null && !recordable ? ' · absente de la playlist' : ''}',
              style: const TextStyle(
                color: AppColors.onSurface54,
                fontSize: 12,
              ),
            ),
            if (g['epg_title'] != null)
              Text(
                'Guide : ${g['epg_title']}',
                style: const TextStyle(
                  color: AppColors.onSurface38,
                  fontSize: 11,
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pill(label, color),
            const SizedBox(width: 8),
            _choiceButton(g, locked),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(
    IconData icon,
    String title,
    String subtitle, {
    Widget? action,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: AppColors.glassLevel1Border),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.fraunces(
              color: AppColors.onSurface38,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: GoogleFonts.fraunces(
              color: AppColors.onSurface24,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[const SizedBox(height: 16), action],
        ],
      ),
    );
  }

  Widget _body() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Impossible de charger les matchs NBA',
              style: TextStyle(color: AppColors.live),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Réessayer'),
              onPressed: _load,
            ),
          ],
        ),
      );
    }
    if (_rule == null) {
      return _emptyState(
        Icons.sports_basketball,
        'Auto NBA désactivé',
        'Choisissez les matchs NBA à enregistrer en direct sur beIN Sports FR, '
            'sans les rediffusions.',
        action: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.secondaryContainer,
            foregroundColor: AppColors.onSecondaryContainer,
          ),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Activer'),
          onPressed: _busy ? null : _createRule,
        ),
      );
    }
    final visible = _games
        // Par défaut, seuls les matchs annoncés en direct sur une beIN FR
        // (ou déjà choisis) : le reste du calendrier NBA n'est pas diffusé.
        .where(
          (g) =>
              _showOffBein ||
              g['channel_name'] != null ||
              g['wanted'] == true,
        )
        .toList();
    if (visible.isEmpty) {
      return _emptyState(
        Icons.event_busy,
        'Aucun match NBA annoncé sur beIN Sports',
        _diagText() ??
            'Le programme beIN couvre environ 8 jours et est relu toutes les 30 min',
      );
    }
    // Liste aplatie : intertitre de nuit puis ses matchs.
    final items = <Object>[];
    String? night;
    for (final g in visible) {
      final label = _nightLabel(DateTime.parse(g['tipoff_utc']).toLocal());
      if (label != night) {
        items.add(label);
        night = label;
      }
      items.add(g);
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final item = items[i];
        if (item is String) {
          return Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 12, bottom: 8),
            child: Text(
              item,
              style: GoogleFonts.fraunces(
                color: AppColors.onSurface54,
                fontSize: 13,
              ),
            ),
          );
        }
        return _gameCard(item as Map<String, dynamic>);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final rule = _rule;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Matchs NBA en direct sur beIN Sports FR · '
                  'enregistrés sur « ${widget.playlist.name} »',
                  style: GoogleFonts.fraunces(
                    color: AppColors.onSurface54,
                    fontSize: 13,
                  ),
                ),
              ),
              if (rule != null) ...[
                Tooltip(
                  message: rule['enabled'] == true
                      ? 'Auto NBA actif'
                      : 'Auto NBA en pause',
                  child: Switch(
                    value: rule['enabled'] == true,
                    activeThumbColor: AppColors.primary,
                    trackColor: _switchTrack,
                    onChanged: (v) => _updateRule({'enabled': v}),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _showOffBein ? Icons.visibility : Icons.visibility_off,
                    color: AppColors.onSurfaceVariant,
                  ),
                  tooltip: _showOffBein
                      ? 'Masquer les matchs hors beIN'
                      : 'Afficher les matchs hors beIN',
                  onPressed: () => setState(() => _showOffBein = !_showOffBein),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.refresh,
                    color: AppColors.onSurfaceVariant,
                  ),
                  tooltip: 'Rafraîchir maintenant',
                  onPressed: _busy ? null : _refreshNow,
                ),
                IconButton(
                  icon: _openingSettings
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onSurface,
                          ),
                        )
                      : const Icon(
                          Icons.tune,
                          color: AppColors.onSurfaceVariant,
                        ),
                  tooltip: 'Réglages',
                  onPressed: _openingSettings ? null : _showSettings,
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.secondary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.secondary.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: AppColors.secondary,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Matchs NBA diffusés en direct sur beIN Sports FR, '
                    "d'après le programme officiel beIN (~8 jours). Rien n'est "
                    'enregistré sans votre choix : cliquez sur « Enregistrer ». '
                    'Les rediffusions sont ignorées. Un seul '
                    "enregistrement à la fois : le flux IPTV ne permet qu'une "
                    'lecture.',
                    style: GoogleFonts.fraunces(
                      color: AppColors.secondaryFixed,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(child: _body()),
        ],
      ),
    );
  }
}
