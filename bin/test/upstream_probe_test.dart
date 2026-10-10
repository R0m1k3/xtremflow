import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../api/upstream_probe.dart';
import '../models/playlist_config.dart';

void main() {
  final playlist = PlaylistConfig(
    id: 'p',
    name: 'n',
    dns: 'http://panel.test',
    username: 'secretuser',
    password: 'secretpass',
    createdAt: DateTime(2026),
  );

  // Panneau simulé : redirige vers un serveur de diffusion avec jeton.
  final client = MockClient.streaming((request, _) async {
    final path = request.url.path;
    if (request.url.host == 'panel.test') {
      return http.StreamedResponse(
        const Stream.empty(),
        302,
        headers: {
          'location': 'http://lb.test$path?token=secrettoken',
        },
      );
    }
    if (path.endsWith('.m3u8')) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(
          '#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,\nseg1.ts\n'
          '#EXTINF:6,\nseg2.ts\n',
        )),
        200,
      );
    }
    return http.StreamedResponse(Stream.value(List.filled(2000, 0x47)), 200);
  });

  test('chronomètre .ts et .m3u8 en suivant les redirections', () async {
    final result = await probeUpstream(playlist, '123', client: client);
    final ts = result['ts'] as Map;
    expect((ts['hops'] as List).map((h) => (h as Map)['status']), [302, 200]);
    expect(ts['firstByteMs'], isNotNull);

    final hls = result['m3u8'] as Map;
    expect(hls['segments'], 2);
    expect(hls['targetDuration'], '6');
    expect((hls['segment'] as Map)['firstByteMs'], isNotNull);
  });

  test('aucun identifiant ni jeton dans la réponse', () async {
    final json = jsonEncode(await probeUpstream(playlist, '123', client: client));
    expect(json, isNot(contains('secretuser')));
    expect(json, isNot(contains('secretpass')));
    expect(json, isNot(contains('secrettoken')));
  });
}
