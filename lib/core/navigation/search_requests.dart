import 'package:flutter/foundation.dart';

/// Bumped by the « Rechercher » item of the side rail. The Direct, Films and
/// Séries tabs listen to it and focus their search field when they are the
/// current tab.
final searchRequests = ValueNotifier<int>(0);
