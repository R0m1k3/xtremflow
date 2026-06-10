/// Redacts IPTV credentials from URLs before they reach logs.
///
/// Xtream Codes embeds credentials both in query strings
/// (`?username=u&password=p`) and in path segments
/// (`/live/<user>/<pass>/<id>.ts`, `/movie/...`, `/series/...`).
class LogRedactor {
  static final RegExp _queryCreds = RegExp(
    r'(username|password)=[^&\s]*',
    caseSensitive: false,
  );

  static final RegExp _pathCreds = RegExp(
    r'/(live|movie|series)/[^/\s]+/[^/\s]+/',
    caseSensitive: false,
  );

  /// Returns [url] with credentials replaced by `***`.
  static String redactUrl(String url) {
    var redacted = url.replaceAllMapped(
      _queryCreds,
      (m) => '${m.group(1)}=***',
    );
    redacted = redacted.replaceAllMapped(
      _pathCreds,
      (m) => '/${m.group(1)}/***/***/',
    );
    return redacted;
  }
}
