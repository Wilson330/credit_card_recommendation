import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/models.dart';

/// 使用者的卡片。後端是正本,手機上存一份副本(docs/DB_DESIGN.md 4.6):
///   - 登入後先顯示手機上的副本,再向後端拉最新的覆蓋
///   - 新增、修改、移除都先寫後端,成功了才更新副本;失敗時副本不動
class UserCardsStore extends ChangeNotifier {
  final ApiClient _api;

  List<CardOption> _options = const [];
  List<UserCard> _cards = const [];
  String? _loadedFor;
  bool _loading = false;
  String? _error;

  UserCardsStore(this._api);

  /// 後端支援的所有卡片,以及每張卡的設定選項。
  List<CardOption> get options => _options;
  List<UserCard> get userCards => _cards;
  bool get hasCards => _cards.isNotEmpty;
  bool get isLoading => _loading;

  /// 最近一次向後端同步失敗的原因;成功後清除。
  String? get error => _error;
  String? get loadedFor => _loadedFor;

  CardOption? optionFor(String cardId) {
    for (final o in _options) {
      if (o.cardId == cardId) return o;
    }
    return null;
  }

  UserCard? findByCardId(String cardId) {
    for (final c in _cards) {
      if (c.cardId == cardId) return c;
    }
    return null;
  }

  String _cacheKey(String email) => 'user_cards:$email';
  static const _optionsKey = 'card_options';

  /// 登入後呼叫:先載入手機上的副本,再向後端同步。
  Future<void> loadForUser(String email) async {
    _loadedFor = email;
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey(email));
    final cachedOptions = prefs.getString(_optionsKey);
    if (cached != null) {
      _cards = [for (final c in jsonDecode(cached) as List) UserCard.fromJson(c as Map<String, dynamic>)];
    }
    if (cachedOptions != null) {
      _options = [for (final o in jsonDecode(cachedOptions) as List) CardOption.fromJson(o as Map<String, dynamic>)];
    }
    notifyListeners();
    await refresh();
  }

  /// 向後端拉最新的卡片選項與使用者卡片,覆蓋手機上的副本。
  Future<void> refresh() async {
    final email = _loadedFor;
    if (email == null) return;
    _loading = true;
    notifyListeners();
    try {
      final rawOptions = await _api.cardOptions();
      final cards = await _api.myCards();
      _options = rawOptions;
      _cards = _sorted(cards);
      _error = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey(email), jsonEncode([for (final c in _cards) c.toJson()]));
      await prefs.setString(_optionsKey, jsonEncode([for (final o in rawOptions) _optionToJson(o)]));
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 新增或更新一張卡。失敗時丟出 ApiException,副本不變。
  Future<void> save(String cardId, Map<String, dynamic> config) async {
    final saved = await _api.saveCard(cardId, config);
    _cards = _sorted([..._cards.where((c) => c.cardId != cardId), saved]);
    await _persist();
    notifyListeners();
  }

  /// 移除一張卡。失敗時丟出 ApiException,副本不變。
  Future<void> remove(String cardId) async {
    await _api.deleteCard(cardId);
    _cards = _cards.where((c) => c.cardId != cardId).toList();
    await _persist();
    notifyListeners();
  }

  void clear() {
    _cards = const [];
    _loadedFor = null;
    _error = null;
    notifyListeners();
  }

  Future<void> _persist() async {
    final email = _loadedFor;
    if (email == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey(email), jsonEncode([for (final c in _cards) c.toJson()]));
  }

  /// 依後端卡片清單的順序排列。
  List<UserCard> _sorted(List<UserCard> cards) {
    final order = {for (var i = 0; i < _options.length; i++) _options[i].cardId: i};
    return [...cards]..sort((a, b) => (order[a.cardId] ?? 999).compareTo(order[b.cardId] ?? 999));
  }

  static Map<String, dynamic> _optionToJson(CardOption o) => {
        'card_id': o.cardId,
        'name': o.name,
        'bank': o.bank,
        'rate_by': o.rateBy,
        'options': o.options,
        'toggles': [for (final t in o.toggles) {'key': t.key, 'label': t.label}],
        'pick_merchants_when': o.pickMerchantsWhen,
        'max_chosen_merchants': o.maxChosenMerchants,
      };
}
