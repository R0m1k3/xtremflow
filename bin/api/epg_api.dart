import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:http/http.dart' as http;
import '../models/playlist_config.dart';

/// API EPG — proxy vers Xtream avec cache 30 minutes
/// GET /api/epg/<channel_id>?days=1
class EpgApi {
  final Future<PlaylistConfig?> Function(Request) _getPlaylist;

  /// Cache mémoire : « dns|username|channelId » → {data, expiresAt}.
  ///
  /// La clé inclut le compte : les `stream_id` sont propres à chaque panneau,
  /// deux playlists distinctes peuvent parfaitement partager le même
  /// identifiant et se servaient alors le guide l'une de l'autre.
  final Map<String, _CacheEntry> _cache = {};

  EpgApi(this._getPlaylist);

  Future<Response> handleGetEpg(Request request, String channelId) async {
    final playlist = await _getPlaylist(request);
    if (playlist == null) {
      return Response.forbidden(
        json.encode({'error': 'Playlist non trouvée'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final cacheKey = '${playlist.dns}|${playlist.username}|$channelId';
    final cached = _cache[cacheKey];
    if (cached != null && DateTime.now().isBefore(cached.expiresAt)) {
      return Response.ok(
        cached.data,
        headers: {'Content-Type': 'application/json', 'X-Cache': 'HIT'},
      );
    }

    try {
      final dns = playlist.dns;
      Map<String, dynamic> epgData = {
        'channel_id': channelId,
        'programmes': [],
      };

      // Ordre d'essai des actions Xtream.
      //
      // `get_simple_data_table` d'abord : c'est la seule action réellement
      // universelle. `get_epg` n'existe pas sur beaucoup de panneaux — au lieu
      // d'une erreur, ils renvoient poliment le payload d'authentification,
      // sans champ `epg_listings`, ce qui produisait un guide vide impossible
      // à distinguer d'une chaîne sans programme.
      const actions = [
        'get_simple_data_table',
        'get_short_epg',
      ];

      for (final action in actions) {
        final url =
            '$dns/player_api.php?username=${playlist.username}&password=${playlist.password}'
            '&action=$action&stream_id=$channelId';

        final response =
            await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
        if (response.statusCode != 200) continue;

        try {
          epgData = transformEpgData(json.decode(response.body), channelId);
        } catch (_) {
          continue;
        }
        if ((epgData['programmes'] as List).isNotEmpty) break;
      }

      final jsonStr = json.encode(epgData);

      // Mettre en cache 30 minutes
      _cache[cacheKey] = _CacheEntry(
        data: jsonStr,
        expiresAt: DateTime.now().add(const Duration(minutes: 30)),
      );

      return Response.ok(
        jsonStr,
        headers: {'Content-Type': 'application/json', 'X-Cache': 'MISS'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: json.encode({'error': 'Erreur lors de la récupération EPG: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Normalise une réponse Xtream (`epg_listings`) vers le format servi au
  /// client. Public pour être couvert par `bin/test/epg_api_test.dart`.
  Map<String, dynamic> transformEpgData(dynamic raw, String channelId) {
    try {
      List<dynamic> listings = [];

      if (raw is Map && raw.containsKey('epg_listings')) {
        listings = raw['epg_listings'] as List<dynamic>? ?? [];
      } else if (raw is List) {
        listings = raw;
      }

      final programmes = listings.map((item) {
        // Les champs texte `start`/`end` sont exprimés dans le fuseau du
        // panneau (souvent Europe/Amsterdam), sans indicateur de zone : le
        // client les relisait comme de l'heure locale et décalait tout le
        // guide. Les `*_timestamp` sont de l'epoch UTC — on s'en sert dès
        // qu'ils sont présents et on émet de l'ISO-8601 UTC explicite.
        final start = _isoUtc(item['start_timestamp']) ??
            _normalizeDate(item['start'] as String? ?? '');
        final end = _isoUtc(item['stop_timestamp']) ??
            _isoUtc(item['end_timestamp']) ??
            _normalizeDate(
              (item['stop'] as String?) ?? (item['end'] as String?) ?? '',
            );

        // Décoder le titre (base64 si nécessaire)
        String title = item['title'] as String? ?? '';
        try {
          if (title.isNotEmpty) {
            final decoded = utf8.decode(base64Decode(title));
            if (decoded.isNotEmpty) title = decoded;
          }
        } catch (_) {}

        String description = item['description'] as String? ?? '';
        try {
          if (description.isNotEmpty) {
            final decoded = utf8.decode(base64Decode(description));
            if (decoded.isNotEmpty) description = decoded;
          }
        } catch (_) {}

        return {
          'title': title,
          'description': description,
          'start': start,
          'end': end,
          'channel_id': channelId,
        };
      }).toList();

      return {'channel_id': channelId, 'programmes': programmes};
    } catch (e) {
      return {'channel_id': channelId, 'programmes': [], 'error': e.toString()};
    }
  }

  /// Epoch (secondes, String ou int) → ISO-8601 UTC, ou `null` si absent.
  static String? _isoUtc(dynamic timestamp) {
    if (timestamp == null) return null;
    final seconds = timestamp is int ? timestamp : int.tryParse('$timestamp');
    if (seconds == null || seconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
        .toIso8601String();
  }

  /// Repli : « YYYY-MM-DD HH:MM:SS » → « YYYY-MM-DDTHH:MM:SS ».
  static String _normalizeDate(String raw) {
    if (raw.contains(' ') && !raw.contains('T')) {
      return raw.replaceFirst(' ', 'T');
    }
    return raw;
  }
}

class _CacheEntry {
  final String data;
  final DateTime expiresAt;
  _CacheEntry({required this.data, required this.expiresAt});
}
