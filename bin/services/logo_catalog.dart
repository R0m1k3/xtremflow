import 'dart:convert';

import 'package:http/http.dart' as http;

/// Logos de chaînes de repli, tirés du dépôt public `tv-logo/tv-logos`.
///
/// POURQUOI : les URL `stream_icon` du panneau pointent chez l'hébergeur du
/// revendeur. Quand cette machine tombe — cas observé : serveur de picons en
/// maintenance, 503 sur toutes les URL —, toute la grille reste sans logo.
/// Le dépôt `tv-logos` est maintenu, nommé de façon régulière
/// (`countries/france/rmc-sport-2-fr.png`) et s'apparie au nom de chaîne.
class LogoCatalog {
  LogoCatalog({
    http.Client? client,
    this.listingTtl = const Duration(hours: 24),
    this.retryBackoff = const Duration(minutes: 15),
  }) : _client = client ?? http.Client();

  final http.Client _client;

  /// Durée de vie d'une liste de logos par pays. L'API GitHub non
  /// authentifiée plafonne à 60 requêtes par heure : une par jour suffit.
  final Duration listingTtl;

  /// Recul après un échec de téléchargement de liste (limite de débit,
  /// réseau), pour ne pas marteler l'API à chaque tuile affichée.
  final Duration retryBackoff;

  final Map<String, _Listing> _listings = {};
  final Map<String, Future<_Listing?>> _listingsInFlight = {};
  final Map<String, DateTime> _listingFailedAt = {};
  final Map<String, List<int>> _bytes = {};

  /// Octets PNG du logo correspondant à [channelName], ou `null`.
  Future<List<int>?> logoFor(String channelName) async {
    final country = countryFolderFor(channelName);
    final listing = await _listingFor(country);
    if (listing == null) return null;

    final key = matchLogoKey(channelName, listing.urls.keys);
    if (key == null) return null;

    final url = listing.urls[key]!;
    final cached = _bytes[url];
    if (cached != null) return cached;

    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      return _bytes[url] = response.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  Future<_Listing?> _listingFor(String country) async {
    final cached = _listings[country];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < listingTtl) {
      return cached;
    }

    final failedAt = _listingFailedAt[country];
    if (failedAt != null &&
        DateTime.now().difference(failedAt) < retryBackoff) {
      // Liste périmée plutôt que rien : les logos ne changent pas d'un jour
      // à l'autre.
      return cached;
    }

    // Les tuiles d'une grille arrivent en rafale : une seule requête de liste.
    return _listingsInFlight[country] ??=
        _fetchListing(country).whenComplete(() {
      _listingsInFlight.remove(country);
    });
  }

  Future<_Listing?> _fetchListing(String country) async {
    final url = 'https://api.github.com/repos/tv-logo/tv-logos/contents/'
        'countries/$country';
    try {
      final response = await _client.get(
        Uri.parse(url),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw StateError('HTTP ${response.statusCode}');
      }

      final urls = <String, String>{};
      final decoded = json.decode(response.body);
      if (decoded is List) {
        for (final entry in decoded) {
          if (entry is! Map) continue;
          final name = entry['name']?.toString() ?? '';
          final download = entry['download_url']?.toString();
          if (download == null || !name.endsWith('.png')) continue;
          urls[_keyFromFileName(name)] = download;
        }
      }

      final listing = _Listing(urls, DateTime.now());
      _listings[country] = listing;
      _listingFailedAt.remove(country);
      print('[LogoCatalog] $country : ${urls.length} logos');
      return listing;
    } catch (e) {
      _listingFailedAt[country] = DateTime.now();
      print('[LogoCatalog] liste $country indisponible : $e');
      return _listings[country];
    }
  }

  /// `rmc-sport-2-fr.png` → `rmc-sport-2`.
  static String _keyFromFileName(String name) {
    final base = name.substring(0, name.length - '.png'.length);
    return base.replaceFirst(RegExp(r'-[a-z]{2}$'), '');
  }
}

class _Listing {
  _Listing(this.urls, this.fetchedAt);

  /// Clé normalisée → URL de téléchargement brute.
  final Map<String, String> urls;
  final DateTime fetchedAt;
}

/// Code pays du préfixe panneau → dossier du dépôt `tv-logos`.
const _countryFolders = {
  'fr': 'france',
  'be': 'belgium',
  'ch': 'switzerland',
  'uk': 'united-kingdom',
  'gb': 'united-kingdom',
  'us': 'united-states',
  'ca': 'canada',
  'de': 'germany',
  'es': 'spain',
  'it': 'italy',
  'pt': 'portugal',
  'nl': 'netherlands',
};

/// Préfixe pays des noms panneau : `FR - `, `FR: `, `|FR| `.
final _countryPrefix = RegExp(r'^\W*([A-Za-z]{2})[\s\-:|]+');

/// Dossier `tv-logos` à consulter pour [channelName]. France par défaut :
/// c'est l'audience de l'application.
String countryFolderFor(String channelName) {
  final match = _countryPrefix.firstMatch(channelName);
  final code = match?.group(1)?.toLowerCase();
  return _countryFolders[code] ?? 'france';
}

/// Mots sans rapport avec l'identité de la chaîne : qualité, codec, variante
/// de flux. Ils sont propres au panneau et absents des noms de logos.
const _noise = {
  'fhd', 'uhd', 'hd', 'sd', '4k', '8k', 'hdr', 'hevc', 'h264', 'h265',
  '1080p', '720p', '50fps', 'fps', 'raw', 'backup', 'vip', 'multi',
  'vf', 'vo', 'vostfr',
};

const _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'è': 'e', 'é': 'e', 'ê': 'e',
  'ë': 'e', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ò': 'o', 'ó': 'o',
  'ô': 'o', 'ö': 'o', 'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ç': 'c',
};

List<String> _tokens(String channelName) {
  var name = channelName;
  final prefix = _countryPrefix.firstMatch(name);
  if (prefix != null &&
      _countryFolders.containsKey(prefix.group(1)!.toLowerCase())) {
    name = name.substring(prefix.end);
  }

  final folded = StringBuffer();
  for (final rune in name.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    folded.write(_accents[char] ?? char);
  }

  return folded
      .toString()
      .replaceAll('+', ' plus ')
      .replaceAll('&', ' and ')
      .split(RegExp(r'[^a-z0-9]+'))
      .where((t) => t.isNotEmpty && !_noise.contains(t))
      .toList();
}

/// Clé de logo la plus proche de [channelName] parmi [available], ou `null`.
///
/// Par ordre de confiance : nom exact, nom sans « live », variante plus
/// longue du même identifiant (`bein-sports-1` → `bein-sports-1-french`),
/// puis la marque sans numéro de canal (`rmc-sport-live-5` → `rmc-sport-1`).
/// Aucune approximation sur un mot seul : « France » ne doit pas devenir
/// France 24.
String? matchLogoKey(String channelName, Iterable<String> available) {
  final keys = available.toSet();
  final tokens = _tokens(channelName);
  if (tokens.isEmpty) return null;

  List<String> withoutLive(List<String> parts) =>
      parts.where((t) => t != 'live').toList();

  String? exact(List<String> parts) {
    final slug = parts.join('-');
    return parts.isNotEmpty && keys.contains(slug) ? slug : null;
  }

  String? longerVariant(List<String> parts) {
    if (parts.length < 2) return null;
    final slug = parts.join('-');
    final longer = keys.where((k) => k.startsWith('$slug-')).toList()
      ..sort((a, b) {
        final byLength = a.length.compareTo(b.length);
        return byLength != 0 ? byLength : a.compareTo(b);
      });
    return longer.isEmpty ? null : longer.first;
  }

  final noLive = withoutLive(tokens);
  final direct = exact(tokens) ??
      exact(noLive) ??
      longerVariant(tokens) ??
      longerVariant(noLive);
  if (direct != null) return direct;

  // Marque sans numéro de canal, seulement s'il reste au moins deux mots.
  if (RegExp(r'^\d+$').hasMatch(tokens.last)) {
    final brand = withoutLive(tokens.sublist(0, tokens.length - 1));
    if (brand.length >= 2) return exact(brand) ?? longerVariant(brand);
  }
  return null;
}
