import 'package:test/test.dart';
import '../api/streaming_handler.dart';

void main() {
  group('vodContainerExtension', () {
    test('garde l\'extension réelle du catalogue', () {
      expect(vodContainerExtension('mp4'), 'mp4');
      expect(vodContainerExtension('MKV'), 'mkv');
      expect(vodContainerExtension('avi'), 'avi');
    });

    test('ancien client sans ext : mkv, comme avant', () {
      expect(vodContainerExtension(null), 'mkv');
      expect(vodContainerExtension(''), 'mkv');
    });

    test('refuse tout ce qui pourrait sortir du nom de fichier', () {
      expect(vodContainerExtension('mp4/../x'), 'mkv');
      expect(vodContainerExtension('mp4?a=b'), 'mkv');
      expect(vodContainerExtension('toolongext'), 'mkv');
    });
  });
}
