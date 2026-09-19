/// URL du logo d'une chaîne, servie par le backend (`/api/logo`).
///
/// Le backend tente d'abord [streamIcon] (l'URL fournie par le panneau), puis
/// cherche un logo par [name] quand l'hébergeur de picons du revendeur ne
/// répond pas. Le nom est donc transmis même sans `stream_icon` : c'est
/// souvent le seul moyen d'obtenir un logo.
///
/// Une chaîne sans logo trouvé reçoit un statut d'erreur : l'`errorBuilder`
/// de l'`Image.network` appelante affiche alors son propre repli.
String channelLogoUrl({required String streamIcon, required String name}) {
  final icon = streamIcon.trim();
  return Uri(
    path: '/api/logo',
    queryParameters: {
      if (icon.startsWith('http://') || icon.startsWith('https://'))
        'src': icon,
      'name': name,
    },
  ).toString();
}
