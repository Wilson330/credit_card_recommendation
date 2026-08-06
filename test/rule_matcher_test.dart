import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/models/card_reward_rule.dart';
import 'package:my_first_app/services/rule_matcher.dart';

CardRewardRule _rule({
  required String ruleId,
  required String ruleType,
  required String matchValue,
  required double rewardRate,
  String? applicableLevel,
}) {
  return CardRewardRule(
    ruleId: ruleId,
    cardId: 'test_card',
    ruleType: ruleType,
    matchValue: matchValue,
    applicableLevel: applicableLevel,
    rewardRate: rewardRate,
    benefitLabel: ruleId,
    requiredAction: null,
    constraints: const [],
    isSyntheticCondition: false,
    active: true,
  );
}

void main() {
  test('a second candidate query (e.g. a resolved canonical name) can find an exact match the first candidate alone cannot', () {
    final rules = [
      _rule(ruleId: 'kfc', ruleType: 'merchant', matchValue: '肯德基', rewardRate: 5.0),
      _rule(ruleId: 'default', ruleType: 'default', matchValue: '*', rewardRate: 0.3),
    ];

    // "KFC" (an alias) doesn't equal or substring-match "肯德基" (the raw
    // match_value) — only passing the resolved canonical name as a second
    // candidate lets this find the real rule instead of default.
    final result = RuleMatcher.selectBestRule(
      rules: rules,
      normalizedQueries: ['kfc', '肯德基'],
      merchantTags: const [],
    );

    expect(result.ruleId, 'kfc');
    expect(result.rewardRate, 5.0);
  });

  test('exact match is never displaced by a higher-rate substring match', () {
    final rules = [
      _rule(ruleId: 'exact', ruleType: 'merchant', matchValue: '全家', rewardRate: 1.0),
      _rule(
        ruleId: 'substring_but_wrong_merchant',
        ruleType: 'merchant',
        matchValue: '全家福超市', // a different, unrelated store that happens to contain "全家"
        rewardRate: 10.0,
      ),
    ];

    final result = RuleMatcher.selectBestRule(
      rules: rules,
      normalizedQueries: ['全家'],
      merchantTags: const [],
    );

    expect(result.ruleId, 'exact');
    expect(result.rewardRate, 1.0);
  });

  test('falls back to substring match only when no exact match exists', () {
    final rules = [
      _rule(ruleId: 'full_name', ruleType: 'merchant', matchValue: '全家便利商店 實體門市', rewardRate: 2.0),
    ];

    final result = RuleMatcher.selectBestRule(
      rules: rules,
      normalizedQueries: ['全家'],
      merchantTags: const [],
    );

    expect(result.ruleId, 'full_name');
  });

  test('does not substring-match strings shorter than the safety minimum', () {
    final rules = [
      _rule(ruleId: 'short', ruleType: 'merchant', matchValue: 'A', rewardRate: 5.0),
      _rule(ruleId: 'default', ruleType: 'default', matchValue: '*', rewardRate: 0.1),
    ];

    // "A" is a substring of "AB", but both are below the 2-char safety
    // floor, so this must NOT match — otherwise a single-letter rule
    // would swallow almost every query containing that letter.
    final result = RuleMatcher.selectBestRule(
      rules: rules,
      normalizedQueries: ['ab'],
      merchantTags: const [],
    );

    expect(result.ruleId, 'default');
  });

  test('category rule matches via merchantTags, not matchValue text', () {
    final rules = [
      _rule(ruleId: 'dining_category', ruleType: 'category', matchValue: 'dining', rewardRate: 3.0),
      _rule(ruleId: 'default', ruleType: 'default', matchValue: '*', rewardRate: 0.1),
    ];

    final result = RuleMatcher.selectBestRule(
      rules: rules,
      normalizedQueries: ['某個沒人聽過的餐廳'],
      merchantTags: const ['dining'],
    );

    expect(result.ruleId, 'dining_category');
  });

  test('applicable_level filters out rules for a different level', () {
    final rules = [
      _rule(
        ruleId: 'level_2_only',
        ruleType: 'merchant',
        matchValue: '誠品生活',
        rewardRate: 3.0,
        applicableLevel: 'level_2',
      ),
      _rule(ruleId: 'default', ruleType: 'default', matchValue: '*', rewardRate: 0.3),
    ];

    final result = RuleMatcher.selectBestRule(
      rules: rules,
      normalizedQueries: ['誠品生活'],
      merchantTags: const [],
      currentLevel: 'level_1',
    );

    expect(result.ruleId, 'default');
  });
}
