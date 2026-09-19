import 'package:flutter_test/flutter_test.dart';
import 'package:xtremflow/core/api/channel_logo.dart';

void main() {
  group('channelLogoUrl', () {
    test('transmet l’URL panneau et le nom, encodés', () {
      final url = Uri.parse(
        channelLogoUrl(
          streamIcon: 'http://picons.example/logos/1.png?x=1&y=2',
          name: 'FR - CANAL+ SPORT',
        ),
      );

      expect(url.path, '/api/logo');
      expect(
        url.queryParameters['src'],
        'http://picons.example/logos/1.png?x=1&y=2',
      );
      // Le « + » doit survivre à l'encodage : sinon Canal+ devient « Canal ».
      expect(url.queryParameters['name'], 'FR - CANAL+ SPORT');
    });

    test('envoie le nom seul sans stream_icon exploitable', () {
      // Sans URL panneau, le nom reste le seul moyen de trouver un logo.
      for (final icon in ['', '   ', 'logo.png']) {
        final url = Uri.parse(channelLogoUrl(streamIcon: icon, name: 'TF1'));
        expect(url.queryParameters.containsKey('src'), isFalse);
        expect(url.queryParameters['name'], 'TF1');
      }
    });
  });
}
