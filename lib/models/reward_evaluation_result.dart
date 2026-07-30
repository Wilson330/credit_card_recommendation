class RewardEvaluationResult {
  final String cardId;
  final String cardName;
  final double rewardRate;
  final List<String> matchedTags;
  final String? requiredAction;
  final List<String> constraints;

  const RewardEvaluationResult({
    required this.cardId,
    required this.cardName,
    required this.rewardRate,
    required this.matchedTags,
    this.requiredAction,
    this.constraints = const [],
  });
}
