import 'package:test/test.dart';
import '../utils/asset_versioning.dart';

void main() {
  group('versionAssetRefs', () {
    test('versionne la balise script du lecteur', () {
      expect(
        versionAssetRefs(
          '<script src="xf-player-core.js"></script>',
          {'xf-player-core.js': 'abc123'},
        ),
        '<script src="xf-player-core.js?v=abc123"></script>',
      );
    });

    test('versionne mainJsPath dans la config de build Flutter', () {
      expect(
        versionAssetRefs(
          '{"compileTarget":"dart2js","mainJsPath":"main.dart.js"}',
          {'main.dart.js': 'f00'},
        ),
        '{"compileTarget":"dart2js","mainJsPath":"main.dart.js?v=f00"}',
      );
    });

    test('ne touche ni un nom qui ne fait que contenir l\'asset ni une ref déjà versionnée', () {
      const html = '<script src="vendor/xf-player-core.js"></script>'
          '<script src="xf-player-core.js?v=old"></script>';
      expect(versionAssetRefs(html, {'xf-player-core.js': 'new'}), html);
    });

    test('guillemets simples acceptés', () {
      expect(
        versionAssetRefs("<link href='xf-player.css'>", {'xf-player.css': '1'}),
        "<link href='xf-player.css?v=1'>",
      );
    });
  });

  group('contentVersion', () {
    test('stable pour un même contenu, différente sinon', () {
      expect(contentVersion([1, 2, 3]), contentVersion([1, 2, 3]));
      expect(contentVersion([1, 2, 3]), isNot(contentVersion([1, 2, 4])));
      expect(contentVersion([1, 2, 3]), hasLength(12));
    });
  });
}
