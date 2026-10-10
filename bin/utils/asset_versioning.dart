import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Versionnage des assets non hachés de la build web.
///
/// POURQUOI : `main.dart.js`, `flutter_bootstrap.js` et `xf-player-core.js`
/// gardent le même nom d'une build à l'autre. Un reverse proxy qui met les
/// `.js` en cache (option « Cache Assets » de Nginx Proxy Manager, constatée
/// en prod : cache jusqu'à 12 h, même sur un rechargement forcé) servait donc
/// l'ANCIEN lecteur et l'ANCIENNE app avec le NOUVEAU serveur après chaque
/// déploiement. En ajoutant `?v=<empreinte du contenu>` aux références,
/// chaque version a sa propre URL : aucun cache intermédiaire ne peut la
/// confondre avec la précédente.

/// Empreinte courte et stable de [bytes].
String contentVersion(List<int> bytes) =>
    md5.convert(bytes).toString().substring(0, 12);

/// Ajoute `?v=<version>` à chaque référence entre guillemets à un asset de
/// [versions] (`"main.dart.js"` → `"main.dart.js?v=…"`).
///
/// Seules les références exactes sont réécrites : `vendor/x.js` ou une
/// référence déjà versionnée restent intactes.
String versionAssetRefs(String content, Map<String, String> versions) {
  var out = content;
  versions.forEach((asset, version) {
    final pattern = RegExp('(["\'])${RegExp.escape(asset)}\\1');
    out = out.replaceAllMapped(
      pattern,
      (m) => '${m[1]}$asset?v=$version${m[1]}',
    );
  });
  return out;
}

/// Contenus réécrits, indexés par chemin relatif (`index.html`…), prêts à
/// être servis à la place des fichiers d'origine.
///
/// Calculé une fois au démarrage : la build web est figée dans l'image.
Map<String, String> buildVersionedEntryPoints(String webPath) {
  String? read(String name) {
    final file = File('$webPath/$name');
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  String? versionOf(String name) {
    final file = File('$webPath/$name');
    return file.existsSync() ? contentVersion(file.readAsBytesSync()) : null;
  }

  final rewritten = <String, String>{};

  // Le bootstrap référence main.dart.js : sa version dépend donc de celle
  // de main.dart.js, d'où une version calculée APRÈS réécriture.
  final bootstrap = read('flutter_bootstrap.js');
  final mainVersion = versionOf('main.dart.js');
  if (bootstrap != null && mainVersion != null) {
    final versioned =
        versionAssetRefs(bootstrap, {'main.dart.js': mainVersion});
    rewritten['flutter_bootstrap.js'] = versioned;
    final index = read('index.html');
    if (index != null) {
      rewritten['index.html'] = versionAssetRefs(index, {
        'flutter_bootstrap.js': contentVersion(utf8.encode(versioned)),
      });
    }
  }

  final playerAssets = <String, String>{
    for (final name in const ['xf-player-core.js', 'xf-player.css'])
      if (versionOf(name) case final v?) name: v,
  };
  for (final page in const [
    'player.html',
    'player_lite.html',
    'player_mobile.html',
  ]) {
    final html = read(page);
    if (html != null) rewritten[page] = versionAssetRefs(html, playerAssets);
  }
  return rewritten;
}
