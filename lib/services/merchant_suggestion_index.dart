import 'merchant_matcher.dart';
import 'merchant_repository.dart';
import 'reward_rules_repository.dart';

/// Suggests known merchant names for the search bar's autocomplete.
///
/// Two sources, merged: (1) card_reward_rules merchant-type match_values
/// (real Allen-sourced names — is_synthetic_condition rows excluded,
/// those are jiho's pseudo-merchant condition labels, not real merchant
/// names) and (2) merchants.json canonical_name + aliases. Source (2) is
/// required — without it, none of the merchants added purely to make
/// category rules useful (藏壽司, the seed dining/hotel chains, etc.)
/// would ever be suggested, even though searching their exact name
/// still works via MerchantResolver. Found 2026-08-06 when the user
/// typed "藏" expecting to see 藏壽司 and only got 麵屋武藏 (a real
/// jiho merchant that happens to contain "藏").
class MerchantSuggestionIndex {
  MerchantSuggestionIndex({
    RewardRulesRepository? rewardRulesRepository,
    MerchantRepository? merchantRepository,
  })  : _rewardRulesRepository = rewardRulesRepository ?? RewardRulesRepository.instance,
        _merchantRepository = merchantRepository ?? MerchantRepository.instance;

  final RewardRulesRepository _rewardRulesRepository;
  final MerchantRepository _merchantRepository;

  List<String> _allNames() {
    final names = <String>{
      for (final rule in _rewardRulesRepository.allRules())
        if (rule.ruleType == 'merchant' && !rule.isSyntheticCondition) rule.matchValue,
      for (final merchant in _merchantRepository.all())
        if (merchant.active) ...[
          merchant.canonicalName,
          ...merchant.aliases,
        ],
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
