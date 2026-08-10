import 'dart:html' as html;
import 'package:http/http.dart' as http;

/// Client HTTP authentifié pour les routes `/api/*` protégées.
///
/// POURQUOI CE FICHIER EXISTE
/// Les routes `/api/epg`, `/api/recordings` et `/api/season-passes` sont
/// montées derrière `authMiddleware` côté serveur. Or plusieurs écrans les
/// appelaient avec `package:http` nu, qui n'envoie ni en-tête `Authorization`
/// ni cookie : sur le web, `BrowserClient` a `withCredentials = false`, donc
/// le cookie `session` reste à quai. Toutes ces requêtes repartaient en 401 —
/// guide TV vide, liste d'enregistrements vide, season passes vides.
///
/// Ce wrapper injecte le même jeton que `ApiClient` et `XtreamService`
/// (`localStorage['auth_token']`), de sorte qu'il n'existe qu'une seule
/// source de vérité pour la session.
class AuthedHttp {
  AuthedHttp._();

  /// Jeton de session posé par `ApiClient.setToken` à la connexion.
  static String? get _token {
    final t = html.window.localStorage['auth_token'];
    return (t != null && t.isNotEmpty) ? t : null;
  }

  static Map<String, String> _headers([Map<String, String>? extra]) {
    final token = _token;
    return {
      if (extra != null) ...extra,
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<http.Response> get(Uri url, {Map<String, String>? headers}) =>
      http.get(url, headers: _headers(headers));

  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) =>
      http.post(url, headers: _headers(headers), body: body);

  static Future<http.Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) =>
      http.put(url, headers: _headers(headers), body: body);

  static Future<http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) =>
      http.delete(url, headers: _headers(headers), body: body);
}
