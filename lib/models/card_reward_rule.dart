class CardRewardRule {
  final String ruleId;
  final String cardId;
  final String ruleType; // 'merchant' | 'category' | 'default'
  final String matchValue;
  final String? applicableLevel;
  final double rewardRate;
  final String benefitLabel;
  final String? requiredAction;
  final List<String> constraints;
  final bool isSyntheticCondition;
  final bool active;

  const CardRewardRule({
    required this.ruleId,
    required this.cardId,
    required this.ruleType,
    required this.matchValue,
    required this.applicableLevel,
    required this.rewardRate,
    required this.benefitLabel,
    required this.requiredAction,
    required this.constraints,
    required this.isSyntheticCondition,
    required this.active,
  });

  factory CardRewardRule.fromJson(Map<String, dynamic> json) {
    return CardRewardRule(
      ruleId: json['rule_id'] as String,
      cardId: json['card_id'] as String,
      ruleType: json['rule_type'] as String,
      matchValue: json['match_value'] as String,
      applicableLevel: json['applicable_level'] as String?,
      rewardRate: (json['reward_rate'] as num).toDouble(),
      benefitLabel: json['benefit_label'] as String,
      requiredAction: json['required_action'] as String?,
      constraints: (json['constraints'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(),
      isSyntheticCondition: json['is_synthetic_condition'] as bool? ?? false,
      active: json['active'] as bool? ?? true,
    );
  }
}
