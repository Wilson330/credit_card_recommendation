import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/card_reward_rule.dart';

/// Loads lib/data/{card}_reward_rules.json (converted from Allen's crawled
/// data via scripts/convert_allen_rewards.js) once at app startup and keeps
/// them in memory, keyed by card_id.
class RewardRulesRepository {
  RewardRulesRepository._();

  static final RewardRulesRepository instance = RewardRulesRepository._();

  final Map<String, List<CardRewardRule>> _rulesByCard = {};
  bool _loaded = false;

  static const _ruleFiles = [
    'lib/data/cube_reward_rules.json',
    'lib/data/jiho_reward_rules.json',
  ];

  Future<void> load() async {
    if (_loaded) return;

    for (final path in _ruleFiles) {
      final raw = await rootBundle.loadString(path);
      final decoded = jsonDecode(raw) as List<dynamic>;
      for (final item in decoded) {
        final rule = CardRewardRule.fromJson(item as Map<String, dynamic>);
        _rulesByCard.putIfAbsent(rule.cardId, () => []).add(rule);
      }
    }

    _loaded = true;
  }

  List<CardRewardRule> rulesFor(String cardId) =>
      List.unmodifiable(_rulesByCard[cardId] ?? const []);

  List<CardRewardRule> allRules() =>
      List.unmodifiable(_rulesByCard.values.expand((rules) => rules));
}
