/// Repli GPU → CPU des transcodages.
///
/// Quand la VRAM est saturée (plusieurs sessions NVENC, un autre processus
/// sur la carte) ou que le GPU dépasse son quota de sessions d'encodage,
/// FFmpeg échoue à l'ouverture de l'encodeur et meurt en une seconde. Sans
/// repli, le lecteur recevait un 502, relançait… et retombait sur le même
/// GPU saturé : le flux restait illisible tant que la carte était pleine.

/// Signatures FFmpeg d'un échec imputable au GPU NVIDIA (NVENC/NVDEC/CUDA).
///
/// N'est consulté que pour une session lancée sur le GPU : « opening
/// encoder » y désigne donc forcément h264_nvenc.
final _gpuFailurePattern = RegExp(
  r'nvenc|cuda|cuvid|nvdec|OpenEncodeSession|No capable devices|'
  r'out of memory|Device creation failed|hwaccel|opening encoder',
  caseSensitive: false,
);

/// Vrai si [error] (stderr récent de FFmpeg) trahit une panne GPU, et non
/// une source injoignable ou un délai dépassé — qu'un repli CPU ne
/// réglerait pas, et qui doublerait inutilement la charge d'un serveur déjà
/// occupé.
bool isGpuFailure(String? error) =>
    error != null && _gpuFailurePattern.hasMatch(error);

/// Mémorise une panne GPU récente pour que les sessions suivantes partent
/// directement sur le CPU, au lieu de payer chacune un échec NVENC avant
/// leur repli.
class GpuHealth {
  final Duration cooldown;
  final DateTime Function() _now;
  DateTime? _unavailableUntil;

  GpuHealth({
    this.cooldown = const Duration(minutes: 2),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  bool get available =>
      _unavailableUntil == null || !_now().isBefore(_unavailableUntil!);

  void markFailed() => _unavailableUntil = _now().add(cooldown);
}
