import 'dart:convert';
import 'package:http/http.dart' as http;
import 'authed_http.dart';

/// Point d'entrée unique pour créer un enregistrement via POST /api/recordings.
///
/// Le backend exige désormais des dates ISO-8601 AVEC fuseau (suffixe 'Z' ou
/// offset) et rejette les dates naïves en 400 : trois conventions d'envoi
/// coexistaient dans l'app (UTC, local naïf, UTC naïf), d'où des
/// enregistrements décalés de 1-2 h selon l'écran utilisé.
///
/// [wallClockIsUtc] : les horaires issus de l'EPG sont des heures UTC
/// « naïves » (parsées sans fuseau par Dart mais comparées à `now.toUtc()`
/// partout dans l'app). true les re-tague en UTC sans décalage ; false (par
/// défaut) convertit depuis l'heure locale réelle (cas d'un DateTime.now()).
Future<http.Response> postRecording({
  required String channelId,
  required String title,
  required DateTime start,
  required DateTime end,
  String? streamUrl,
  bool wallClockIsUtc = false,
}) {
  DateTime asUtc(DateTime d) {
    if (d.isUtc) return d;
    return wallClockIsUtc
        ? DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second)
        : d.toUtc();
  }

  return AuthedHttp.post(
    Uri.parse('/api/recordings'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode({
      'channel_id': channelId,
      'stream_url': streamUrl ?? '/api/live/$channelId.ts',
      'title': title,
      'start_time': asUtc(start).toIso8601String(),
      'end_time': asUtc(end).toIso8601String(),
    }),
  );
}
