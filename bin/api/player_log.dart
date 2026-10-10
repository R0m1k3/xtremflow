import 'dart:convert';

import 'package:shelf/shelf.dart';

/// Journal des incidents de lecture remontés par le lecteur web.
///
/// POURQUOI : les freezes (image et son figés puis reprise) se produisent
/// chez l'utilisateur, dans son navigateur ; le serveur n'en voit rien. Le
/// lecteur envoie ici chaque coupure, erreur, recréation et saut, et le
/// serveur les écrit dans `docker logs` (`[Player] …`) : on sait alors si un
/// freeze vient d'un buffer à sec, d'une erreur du démuxeur ou d'une
/// relance du flux.
///
/// Entrée non fiable : seuls des champs connus, courts et typés passent.

const _events = {
  'start', 'first_frame', 'stall', 'seek', 'mpegts_error', 'recreate',
  'fallback_hls', 'hls_error', 'profile', 'error_shown', 'heartbeat',
};

const _numericFields = {
  't', 'ms', 'buffer', 'pos', 'from', 'to', 'stalls', 'stallMs', 'seeks',
  'errors', 'rate',
};

const _textFields = {'session', 'ch', 'mode', 'profile', 'detail'};

/// Ligne de journal pour l'événement [raw], ou null s'il est invalide.
String? formatPlayerEvent(Object? raw) {
  if (raw is! Map) return null;
  final event = raw['event'];
  if (event is! String || !_events.contains(event)) return null;

  final parts = <String>[event];
  for (final key in _textFields) {
    final value = raw[key];
    if (value is String && value.isNotEmpty) {
      // Ni espace, ni retour ligne, ni URL : jamais d'injection de faux
      // journaux, jamais d'identifiants recopiés depuis une URL d'erreur.
      final safe = value
          .replaceAll(RegExp(r'https?://\S+'), '<url>')
          .replaceAll(RegExp(r'[^\w.\-:/<>]'), '_');
      parts.add('$key=${safe.length > 60 ? safe.substring(0, 60) : safe}');
    }
  }
  for (final key in _numericFields) {
    final value = raw[key];
    if (value is num && value.isFinite) {
      parts.add('$key=${value is int ? value : value.toStringAsFixed(1)}');
    }
  }
  return '[Player] ${parts.join(' ')}';
}

Future<Response> handlePlayerLog(Request request) async {
  final body = await request.readAsString();
  if (body.length > 4096) return Response(413);
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    return Response.badRequest();
  }
  final events = decoded is List ? decoded.take(20) : [decoded];
  for (final event in events) {
    final line = formatPlayerEvent(event);
    if (line != null) print(line);
  }
  return Response(204);
}
