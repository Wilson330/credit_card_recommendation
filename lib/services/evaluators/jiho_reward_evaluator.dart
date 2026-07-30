import '../../models/card_profiles/jiho_card_profile.dart';
import '../../models/merchant_query_context.dart';
import '../../models/reward_evaluation_result.dart';

class JihoRewardEvaluator {
  RewardEvaluationResult evaluate({
    required JihoCardProfile profile,
    required MerchantQueryContext merchantContext,
  }) {
    double rewardRate = 1.0;
    final matchedTags = <String>[];

    final merchantName = merchantContext.merchantName.toLowerCase();

    matchedTags.add('吉鶴卡基本回饋');

    if (merchantName.contains('japan') ||
        merchantName.contains('日本') ||
        merchantName.contains('tokyo')) {
      rewardRate += 2.0;
      matchedTags.add('日本消費加碼');
    }

    if (merchantName.contains('travel') ||
        merchantName.contains('trip') ||
        merchantName.contains('agoda')) {
      rewardRate += 1.5;
      matchedTags.add('旅遊相關通路');
    }

    if (profile.isNewCardHolder) {
      rewardRate += 0.5;
      matchedTags.add('新戶身份加成');
    }

    return RewardEvaluationResult(
      cardId: 'ubot_jiho',
      cardName: '吉鶴卡',
      rewardRate: rewardRate,
      matchedTags: matchedTags,
    );
  }
}