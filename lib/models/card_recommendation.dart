import 'wallet_card.dart';

class CardRecommendation {
  final WalletCard card;
  final double rewardRate;
  final String condition;
  final int matchedTagCount;
  final List<String> matchedTags;
  final String matchedScene;
  final String? selectedProgram;

  const CardRecommendation({
    required this.card,
    required this.rewardRate,
    required this.condition,
    required this.matchedTagCount,
    required this.matchedTags,
    required this.matchedScene,
    required this.selectedProgram,
  });
}