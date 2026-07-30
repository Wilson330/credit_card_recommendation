import 'merchant_matcher.dart';
import 'reward_rules_repository.dart';

/// Suggests known merchant names for the search bar's autocomplete, sourced
/// from the same rule data RuleMatcher evaluates against — so anything
/// suggested here is guaranteed to actually produce a result if picked.
/// is_synthetic_condition rows (jiho's pseudo-merchant condition labels,
/// see SCHEMA.md) are excluded since they aren't real merchant names.
class MerchantSuggestionIndex {
  MerchantSuggestionIndex({RewardRulesRepository? repository})
      : _repository = repository ?? RewardRulesRepository.instance;

  final RewardRulesRepository _repository;

  List<String> _allNames() {
    final names = <String>{
      for (final rule in _repository.allRules())
        if (rule.ruleType == 'merchant' && !rule.isSyntheticCondition)
          rule.matchValue,
    };
    return names.toList()..sort();
  }

  List<String> suggestionsFor(String query, {int limit = 8}) {
    final normalizedQuery = MerchantMatcher.normalize(query);
    if (normalizedQuery.isEmpty) return const [];

    return _allNames()
        .where((name) => MerchantMatcher.normalize(name).contains(normalizedQuery))
        .take(limit)
        .toList();
  }
}
