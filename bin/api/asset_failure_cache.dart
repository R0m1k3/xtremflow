/// Mémoire courte des hôtes d'images injoignables.
///
/// POURQUOI : les URL de picons pointent chez l'hébergeur du revendeur, pas
/// sur le panneau. Quand cette machine tombe (maintenance, DNS, quota), elle
/// répond 5xx en quelques millisecondes, le navigateur réessaie à chaque
/// rendu de la grille et le proxy relaie des centaines de requêtes mortes par
/// seconde. Le serveur tournant sur un unique isolate Dart, ce flot passe
/// devant les paquets vidéo dans la boucle d'événements : l'image saccade
/// pendant qu'on s'acharne sur un hôte qu'on sait hors service.
///
/// On coupe donc court : au bout de [threshold] échecs consécutifs, l'hôte
/// est considéré mort pendant [ttl] et les requêtes suivantes sont servies
/// localement, sans appel sortant.
class AssetFailureCache {
  AssetFailureCache({
    this.threshold = 3,
    this.ttl = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Nombre d'échecs consécutifs avant de couper un hôte. Un 5xx passager ne
  /// doit pas priver l'utilisateur de ses logos.
  final int threshold;

  /// Durée de la coupure. Assez courte pour qu'un hôte réparé revienne seul.
  final Duration ttl;

  final DateTime Function() _clock;

  final Map<String, int> _failures = {};
  final Map<String, DateTime> _downUntil = {};

  /// L'hôte est-il réputé hors service en ce moment ?
  bool isDown(String host) {
    final key = host.toLowerCase();
    final until = _downUntil[key];
    if (until == null) return false;
    if (_clock().isBefore(until)) return true;

    // Coupure expirée : on repart d'une ardoise vierge pour laisser une
    // vraie chance au prochain appel.
    _downUntil.remove(key);
    _failures.remove(key);
    return false;
  }

  void recordFailure(String host) {
    final key = host.toLowerCase();
    final count = (_failures[key] ?? 0) + 1;
    _failures[key] = count;
    if (count >= threshold) {
      _downUntil[key] = _clock().add(ttl);
    }
  }

  void recordSuccess(String host) {
    final key = host.toLowerCase();
    _failures.remove(key);
    _downUntil.remove(key);
  }
}
