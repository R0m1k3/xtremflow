import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/playlist_config.dart';

/// Diagnostic admin : chronomètre l'ouverture d'une chaîne chez le
/// fournisseur, en `.ts` et en `.m3u8`.
///
/// POURQUOI : ~4,3 s des ~4,6 s d'un zap se passent avant le premier octet
/// du panneau (mesuré en prod). Le panneau autorise aussi le HLS ; reste à
/// savoir lequel des deux formats démarre le plus vite, et où part le temps
/// (redirection, en-têtes, premier octet). Les identifiants n'apparaissent
/// jamais dans la réponse : seuls l'hôte et les durées sont rendus.
Future<Map<String, Object?>> probeUpstream(
  PlaylistConfig playlist,
  String streamId, {
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  try {
    final base = '${playlist.dns}/live/${playlist.username}/'
        '${playlist.password}/$streamId';
    final ts = await _probeStream(c, Uri.parse('$base.ts'));
    // Laisser le panneau libérer la connexion (comptes à une connexion).
    await Future<void>.delayed(const Duration(seconds: 2));
    final hls = await _probeHls(c, Uri.parse('$base.m3u8'));
    return {'stream': streamId, 'ts': ts, 'm3u8': hls};
  } finally {
    if (client == null) c.close();
  }
}

/// Suit les redirections à la main pour chronométrer chaque saut.
Future<({http.StreamedResponse? response, List<Map<String, Object?>> hops, Uri url})>
    _open(http.Client c, Uri url, Stopwatch sw) async {
  final hops = <Map<String, Object?>>[];
  var current = url;
  for (var i = 0; i < 5; i++) {
    final request = http.Request('GET', current)
      ..followRedirects = false
      ..headers['User-Agent'] = 'VLC/3.0.18 LibVLC/3.0.18';
    final response =
        await c.send(request).timeout(const Duration(seconds: 20));
    hops.add({
      'host': current.host,
      'status': response.statusCode,
      'headersMs': sw.elapsedMilliseconds,
    });
    final location = response.headers['location'];
    if (const {301, 302, 303, 307, 308}.contains(response.statusCode) &&
        location != null) {
      await response.stream.drain<void>().catchError((_) {});
      current = current.resolve(location);
      continue;
    }
    return (response: response, hops: hops, url: current);
  }
  return (response: null, hops: hops, url: current);
}

Future<Map<String, Object?>> _probeStream(http.Client c, Uri url) async {
  final sw = Stopwatch()..start();
  try {
    final opened = await _open(c, url, sw);
    final response = opened.response;
    if (response == null || response.statusCode != 200) {
      return {'hops': opened.hops, 'error': 'status ${response?.statusCode}'};
    }
    var bytes = 0;
    int? firstByteMs;
    final sub = response.stream.listen(null);
    final done = Completer<void>();
    sub.onData((chunk) {
      firstByteMs ??= sw.elapsedMilliseconds;
      bytes += chunk.length;
      // 1 Mo suffit à voir le premier envoi (préchargement du panneau).
      if (bytes > 1000000 && !done.isCompleted) done.complete();
    });
    sub.onDone(() {
      if (!done.isCompleted) done.complete();
    });
    await done.future.timeout(const Duration(seconds: 15), onTimeout: () {});
    await sub.cancel();
    return {
      'hops': opened.hops,
      'firstByteMs': firstByteMs,
      'firstMegabyteMs': bytes > 1000000 ? sw.elapsedMilliseconds : null,
    };
  } catch (e) {
    return {'error': e.runtimeType.toString(), 'afterMs': sw.elapsedMilliseconds};
  }
}

Future<Map<String, Object?>> _probeHls(http.Client c, Uri url) async {
  final sw = Stopwatch()..start();
  try {
    final opened = await _open(c, url, sw);
    final response = opened.response;
    if (response == null || response.statusCode != 200) {
      return {'hops': opened.hops, 'error': 'status ${response?.statusCode}'};
    }
    final body = await response.stream.bytesToString();
    final playlistMs = sw.elapsedMilliseconds;
    final lines = const LineSplitter().convert(body);
    final segments =
        lines.where((l) => l.isNotEmpty && !l.startsWith('#')).toList();
    final target = lines
        .firstWhere((l) => l.startsWith('#EXT-X-TARGETDURATION'),
            orElse: () => '')
        .split(':')
        .last;
    if (segments.isEmpty) {
      return {'hops': opened.hops, 'playlistMs': playlistMs, 'segments': 0};
    }
    // Un lecteur démarre près du direct : chronométrer l'avant-dernier.
    final pick = segments.length >= 2
        ? segments[segments.length - 2]
        : segments.last;
    final segment = await _probeStream(c, opened.url.resolve(pick));
    return {
      'hops': opened.hops,
      'playlistMs': playlistMs,
      'segments': segments.length,
      'targetDuration': target,
      'segment': segment,
      'segmentStartedAtMs': playlistMs,
    };
  } catch (e) {
    return {'error': e.runtimeType.toString(), 'afterMs': sw.elapsedMilliseconds};
  }
}
