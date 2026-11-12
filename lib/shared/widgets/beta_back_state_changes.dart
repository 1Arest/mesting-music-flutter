import 'package:flutter/foundation.dart';

/// Local history can change without a Router match changing. Consumers always
/// re-read their own visible navigator; this signal carries no stale pop flag.
class BetaBackStateChanges extends ChangeNotifier {
  static final shared = BetaBackStateChanges();
  void refresh() => notifyListeners();
}
