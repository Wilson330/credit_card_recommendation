import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/services/merchant_suggestion_index.dart';
import 'package:my_first_app/services/reward_rules_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RewardRulesRepository.instance.load();
  });

  test('suggests real merchant names containing the query', () {
    final index = MerchantSuggestionIndex();
    final suggestions = index.suggestionsFor('誠品');

    expect(suggestions, contains('誠品生活'));
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
