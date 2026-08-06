import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/services/merchant_repository.dart';
import 'package:my_first_app/services/merchant_suggestion_index.dart';
import 'package:my_first_app/services/reward_rules_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RewardRulesRepository.instance.load();
    await MerchantRepository.instance.load();
  });

  test('suggests real merchant names containing the query', () {
    final index = MerchantSuggestionIndex();
    final suggestions = index.suggestionsFor('誠品');

    expect(suggestions, contains('誠品生活'));
  });

  test(
    'suggests merchants that only exist in merchants.json, not in any card_reward_rules file',
    () {
      // Regression case: user typed "藏" expecting 藏壽司 and only got
      // 麵屋武藏 (a real jiho merchant containing "藏") — 藏壽司 has no
      // card_reward_rules entry at all (it was never named by Allen), it
      // only exists in merchants.json for the category-rule pathway, so
      // it was invisible to autocomplete until this fix.
      final index = MerchantSuggestionIndex();
      final suggestions = index.suggestionsFor('藏');

      expect(suggestions, contains('藏壽司'));
    },
  );

  test('suggests an alias from merchants.json (not just canonical names)', () {
    final index = MerchantSuggestionIndex();
    final suggestions = index.suggestionsFor('KFC');

    expect(suggestions, contains('KFC'));
  });

  test('excludes is_synthetic_condition rows (jiho pseudo-merchant labels)', () {
    final index = MerchantSuggestionIndex();
    // "新戶" only appears inside synthetic condition labels like
    // "新戶自動扣繳加碼(國內一般消費)" / "新戶日本實體消費" — none of those
    // are real merchants and shouldn't be suggested.
    final suggestions = index.suggestionsFor('新戶');

    expect(suggestions, isEmpty);
  });

  test('empty query returns no suggestions', () {
    final index = MerchantSuggestionIndex();
    expect(index.suggestionsFor(''), isEmpty);
  });

  test('respects the limit parameter', () {
    final index = MerchantSuggestionIndex();
    // "店" is broad enough to hit many real merchant names.
    final suggestions = index.suggestionsFor('店', limit: 2);

    expect(suggestions.length, lessThanOrEqualTo(2));
  });
}
