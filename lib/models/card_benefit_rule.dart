import 'rule_condition.dart';

class CardBenefitRule {
  final String id;
  final String title;
  final String scene;
  final DateTime startDate;
  final DateTime endDate;
  final double baseRewardRate;
  final double bonusRewardRate;
  final String rewardText;
  final double? maxRewardAmount;
  final List<String> eligibleTags;
  final RuleCondition condition;
  final String notes;

  const CardBenefitRule({
    required this.id,
    required this.title,
    required this.scene,
    required this.startDate,
    required this.endDate,
    required this.baseRewardRate,
    required this.bonusRewardRate,
    required this.rewardText,
    required this.maxRewardAmount,
    required this.eligibleTags,
    required this.condition,
    required this.notes,
  });

  double get totalRewardRate => baseRewardRate + bonusRewardRate;
}