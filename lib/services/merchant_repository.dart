import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/merchant.dart';

/// Loads lib/data/merchants.json (built by scripts/build_merchants.js)
/// once at app startup, mirroring RewardRulesRepository's pattern.
class MerchantRepository {
  MerchantRepository._();

  static final MerchantRepository instance = MerchantRepository._();

  List<Merchant> _merchants = const [];
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;

    final raw = await rootBundle.loadString('lib/data/merchants.json');
    final decoded = jsonDecode(raw) as List<dynamic>;
    _merchants = decoded
        .map((item) => Merchant.fromJson(item as Map<String, dynamic>))
        .toList();

    _loaded = true;
  }

  List<Merchant> all() => List.unmodifiable(_merchants);
}
