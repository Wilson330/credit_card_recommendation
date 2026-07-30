import '../../models/card_profiles/cube_card_profile.dart';
import '../../models/merchant_query_context.dart';
import '../../models/reward_evaluation_result.dart';

class CubeRewardEvaluator {
  RewardEvaluationResult evaluate({
    required CubeCardProfile profile,
    required MerchantQueryContext merchantContext,
  }) {
    double rewardRate = 0.0;
    final matchedTags = <String>[];

    final merchantName = merchantContext.merchantName.toLowerCase();
    final selectedRights = profile.selectedRights;

    if (selectedRights == 'daily_select') {
      rewardRate = 3.0;
      matchedTags.add('天天精選權益');
    }

    if (merchantName.contains('uber eats') ||
        merchantName.contains('foodpanda')) {
      rewardRate += 2.0;
      matchedTags.add('外送通路加碼');
    }

    if (merchantName.contains('starbucks')) {
      rewardRate += 1.0;
      matchedTags.add('指定咖啡通路');
    }

    if (profile.isNewCardHolder) {
      matchedTags.add('新戶身份已套用');
    }

    return RewardEvaluationResult(
      cardId: 'cathay_cube',
      cardName: 'CUBE Card',
      rewardRate: rewardRate,
      matchedTags: matchedTags,
    );
  }
}