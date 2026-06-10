import 'package:test/test.dart';
import '../utils/log_redactor.dart';

void main() {
  group('LogRedactor.redactUrl', () {
    test('masks credentials in query strings', () {
      final out = LogRedactor.redactUrl(
        'http://srv:8080/player_api.php?username=john&password=hunter2&action=get_live_streams',
      );
      expect(out, isNot(contains('john')));
      expect(out, isNot(contains('hunter2')));
      expect(out, contains('username=***'));
      expect(out, contains('password=***'));
      expect(out, contains('action=get_live_streams'));
    });

    test('masks credentials in live/movie/series path segments', () {
      for (final kind in ['live', 'movie', 'series']) {
        final out = LogRedactor.redactUrl(
          'http://srv:8080/$kind/john/hunter2/12345.ts',
        );
        expect(out, isNot(contains('john')), reason: kind);
        expect(out, isNot(contains('hunter2')), reason: kind);
        expect(out, contains('/$kind/***/***/12345.ts'), reason: kind);
      }
    });

    test('leaves URLs without credentials untouched', () {
      const url = 'http://srv:8080/images/logo.png';
      expect(LogRedactor.redactUrl(url), url);
    });
  });
}
