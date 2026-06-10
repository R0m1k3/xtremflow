import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:http/http.dart' as http;
import '../models/playlist_config.dart';
import '../utils/log_redactor.dart';

/// Authenticated gateway to the Xtream `player_api.php` endpoint.
///
/// The frontend never sees the Xtream credentials: it calls
/// `GET /api/xtream-api?action=...` with its session token and the server
/// injects the username/password of the user's playlist before forwarding.
class XtreamApiHandler {
  final Future<PlaylistConfig?> Function(Request) _getPlaylist;
  final http.Client _client = http.Client();

  XtreamApiHandler(this._getPlaylist);

  /// Query parameters the client is allowed to pass through to Xtream.
  static const _allowedParams = {
    'action',
    'category_id',
    'stream_id',
    'series_id',
    'vod_id',
    'limit',
    'type',
  };

  Future<Response> handle(Request request) async {
    final playlist = await _getPlaylist(request);
    if (playlist == null) {
      return Response.forbidden(
        jsonEncode({'error': 'No playlist configured'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final params = <String, String>{
      'username': playlist.username,
      'password': playlist.password,
    };
    request.url.queryParameters.forEach((key, value) {
      if (_allowedParams.contains(key)) params[key] = value;
    });

    final base = Uri.parse('${playlist.dns}/player_api.php');
    final targetUrl = base.replace(queryParameters: params);

    try {
      final proxyRequest = http.Request('GET', targetUrl)
        ..headers['User-Agent'] = 'VLC/3.0.18 LibVLC/3.0.18'
        ..headers['Accept'] = '*/*'
        ..followRedirects = true;

      final response = await _client
          .send(proxyRequest)
          .timeout(const Duration(seconds: 90));

      return Response(
        response.statusCode,
        body: response.stream,
        headers: {
          'Content-Type':
              response.headers['content-type'] ?? 'application/json',
          'Cache-Control': 'no-store',
        },
      );
    } catch (e) {
      print(
        '[XtreamApi] Error forwarding to ${LogRedactor.redactUrl(targetUrl.toString())}: $e',
      );
      return Response.internalServerError(
        body: jsonEncode({'error': 'Upstream Xtream API error'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }
}
