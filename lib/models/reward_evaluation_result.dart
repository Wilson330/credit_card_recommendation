class RewardEvaluationResult {
  final String cardId;
  final String cardName;
  final double rewardRate;
  final List<String> matchedTags;

  const RewardEvaluationResult({
    required this.cardId,
    required this.cardName,
    required this.rewardRate,
    required this.matchedTags,
  });
}