/// Adressage des sessions de lecture d'un enregistrement.
///
/// Un enregistrement est transcodé à la volée par FFmpeg, séquentiellement.
/// Reprendre à 45 min sans le lui dire imposerait d'attendre que l'encodeur
/// y arrive : le lecteur demande donc une playlist qui *commence* à cette
/// position (`?start=2700`), servie par une session FFmpeg dédiée.
///
/// Ces fonctions sont isolées du handler HTTP pour rester testables.
library;

/// Position de départ demandée (`?start=<secondes>`), bornée au positif.
/// Toute valeur absente, négative ou non numérique vaut « depuis le début ».
int parseRecordingStart(String? raw) {
  final value = double.tryParse(raw ?? '');
  if (value == null || !value.isFinite || value <= 0) return 0;
  return value.floor();
}

/// Segment de chemin qui rattache un segment `.ts` à SA session.
///
/// Les segments sont référencés en relatif dans la playlist et la
/// query string n'y survit pas : sans ce répertoire virtuel, la playlist
/// démarrée à 0 s et celle démarrée à 45 min demanderaient toutes deux
/// `segment_000.ts` à la même URL.
String recordingOffsetKey(int start) => 't$start';

/// Inverse de [recordingOffsetKey] ; `null` si la clé est mal formée.
int? parseRecordingOffsetKey(String key) {
  if (!key.startsWith('t') || key.length < 2) return null;
  final value = int.tryParse(key.substring(1));
  return (value == null || value < 0) ? null : value;
}

/// Préfixe les segments de [playlist] par [offsetKey].
///
/// Seules les lignes de segment sont touchées : les balises `#EXT-X-…` et
/// les lignes vides passent telles quelles.
String rewriteRecordingPlaylist(String playlist, String offsetKey) {
  return playlist.replaceAllMapped(
    RegExp(r'^(segment_\d+\.ts)\s*$', multiLine: true),
    (m) => '$offsetKey/${m[1]}',
  );
}
