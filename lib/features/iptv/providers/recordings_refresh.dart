import 'package:flutter/foundation.dart';

/// Bus de notification global pour la liste des enregistrements.
///
/// L'onglet Enregistrements vit dans un IndexedStack : il n'est construit
/// qu'une seule fois au lancement. Tout code qui crée/modifie un
/// enregistrement (modal d'enregistrement, guide EPG, ...) appelle
/// [notifyRecordingsChanged] pour que la liste se recharge immédiatement,
/// sans attendre le prochain cycle de polling.
final ValueNotifier<int> recordingsRefreshBus = ValueNotifier<int>(0);

void notifyRecordingsChanged() {
  recordingsRefreshBus.value++;
}
