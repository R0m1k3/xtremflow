import 'dart:async';

/// Relaie [source] vers le client en conservant la contre-pression.
///
/// POURQUOI : un `StreamController` nu ne transmet pas la pause de son
/// abonné à la source. Quand le navigateur lit plus lentement que FFmpeg ne
/// produit — réseau domestique, onglet en arrière-plan —, le serveur empilait
/// donc les paquets en mémoire sans jamais ralentir le producteur : la
/// consommation grimpe et la lecture dérive derrière le direct, ce qui se voit
/// à l'écran comme des saccades.
///
/// [onStop] est appelé une seule fois, quand le client se déconnecte ou que la
/// source se termine : c'est là qu'on tue le processus FFmpeg, sinon il en
/// reste un par zapping.
Stream<List<int>> pipeWithBackpressure(
  Stream<List<int>> source, {
  required void Function() onStop,
}) {
  late final StreamController<List<int>> controller;
  late final StreamSubscription<List<int>> subscription;
  var stopped = false;

  void stop() {
    if (stopped) return;
    stopped = true;
    onStop();
  }

  controller = StreamController<List<int>>(
    onPause: () => subscription.pause(),
    onResume: () => subscription.resume(),
    onCancel: () {
      final cancelled = subscription.cancel();
      stop();
      return cancelled;
    },
  );

  subscription = source.listen(
    controller.add,
    onError: controller.addError,
    onDone: () {
      controller.close();
      stop();
    },
  );

  return controller.stream;
}
