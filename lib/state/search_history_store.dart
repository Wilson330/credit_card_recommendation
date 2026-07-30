import 'package:flutter/foundation.dart';

/// v1 simplification: in-memory only, cleared on app restart. Real
/// persistence (e.g. shared_preferences) is a follow-up, not done here.
class SearchHistoryStore extends ChangeNotifier {
  static const _maxEntries = 8;

  final List<String> _history = [];

  List<String> get history => List.unmodifiable(_history);

  void recordSearch(String merchantName) {
    final trimmed = merchantName.trim();
    if (trimmed.isEmpty) return;

    _history.removeWhere((entry) => entry == trimmed);
    _history.insert(0, trimmed);
    if (_history.length > _maxEntries) {
      _history.removeRange(_maxEntries, _history.length);
    }

    notifyListeners();
  }

  void clear() {
    _history.clear();
    notifyListeners();
  }
}
