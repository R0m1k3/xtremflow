import 'package:flutter/foundation.dart';

/// Bumped by the « Rechercher » item of the side rail. The Direct, Films and
/// Séries tabs listen to it and focus their search field when they are the
/// current tab ([activeTab]).
final searchRequests = ValueNotifier<int>(0);

/// Index of the dashboard tab on screen: 0 Direct, 1 Films, 2 Séries,
/// 3 Enregistrements, 4 Réglages. Set by the dashboard.
final activeTab = ValueNotifier<int>(0);
