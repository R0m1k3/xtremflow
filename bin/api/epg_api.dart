import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:http/http.dart' as http;
import '../database/database.dart';
import '../models/playlist_config.dart';

/// API EPG — proxy vers Xtream avec cache 30 minutes
/// GET /api/epg/<channel_id>?days=1
class EpgApi {
  final AppDatabase _db;
  final Future<PlaylistConfig?> Function(Request) _getPlaylist;

  // Cache simple en mémoire : channelId → {data, expiresAt}
  final Map<String, _CacheEntry> _cache = {};

  EpgApi(this._db, this._getPlaylist);

  Future<Response> handleGetEpg(Request request, String channelId) async {
    // Vérifier le cache
    final cached = _cache[channelId];
    if (cached != null && DateTime.now().isBefore(cached.expiresAt)) {
      return Response.ok(
        cached.data,
        headers: {'Content-Type': 'application/json', 'X-Cache': 'HIT'},
      );
    }

    try {
      final playlist = await _getPlaylist(request);
      if (playlist == null) {
        return Response.forbidden(json.encode({'error': 'Playlist non trouvée'}),
            headers: {'Content-Type': 'application/json'});
      }

      final dns = playlist.dns;
      // Appel API Xtream pour l'EPG complet de la chaîne
      final url =
          '$dns/player_api.php?username=${playlist.username}&password=${playlist.password}'
          '&action=get_simple_data_table&stream_id=$channelId&type=epg&limit=48';

      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return Response(response.statusCode,
            body: json.encode({'error': 'Erreur API Xtream: ${response.statusCode}'}),
            headers: {'Content-Type': 'application/json'});
      }

      // Reformater les données pour la grille TV
      final raw = json.decode(response.body);
      final epgData = _transformEpgData(raw, channelId);
      final jsonStr = json.encode(epgData);

      // Mettre en cache 30 minutes
      _cache[channelId] = _CacheEntry(
        data: jsonStr,
        expiresAt: DateTime.now().add(const Duration(minutes: 30)),
      );

      return Response.ok(jsonStr, headers: {'Content-Type': 'application/json', 'X-Cache': 'MISS'});
    } catch (e) {
      return Response.internalServerError(
        body: json.encode({'error': 'Erreur lors de la récupération EPG: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Map<String, dynamic> _transformEpgData(dynamic raw, String channelId) {
    try {
      List<dynamic> listings = [];

      if (raw is Map && raw.containsKey('epg_listings')) {
        listings = raw['epg_listings'] as List<dynamic>? ?? [];
      } else if (raw is List) {
        listings = raw;
      }

      final programmes = listings.map((item) {
        final startRaw = item['start'] as String? ?? '';
        final endRaw = item['stop'] as String? ?? item['end'] as String? ?? '';

        // Décoder le titre (base64 si nécessaire)
        String title = item['title'] as String? ?? '';
        try {
          title = utf8.decode(base64Decode(title));
        } catch (_) {
          // n'est pas du base64, garder tel quel
        }

        String description = item['description'] as String? ?? '';
        try {
          description = utf8.decode(base64Decode(description));
        } catch (_) {}

        return {
          'title': title,
          'description': description,
          'start': startRaw,
          'end': endRaw,
          'channel_id': channelId,
        };
      }).toList();

      return {'channel_id': channelId, 'programmes': programmes};
    } catch (e) {
      return {'channel_id': channelId, 'programmes': [], 'error': e.toString()};
    }
  }
}

class _CacheEntry {
  final String data;
  final DateTime expiresAt;
  _CacheEntry({required this.data, required this.expiresAt});
}
