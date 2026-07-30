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
      normalizedQuery: '全家',
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
      normalizedQuery: '全家',
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
      normalizedQuery: 'ab',
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
      normalizedQuery: '某個沒人聽過的餐廳',
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
      normalizedQuery: '誠品生活',
      merchantTags: const [],
      currentLevel: 'level_1',
    );

    expect(result.ruleId, 'default');
  });
}
