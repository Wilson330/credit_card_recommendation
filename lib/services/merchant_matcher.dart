import '../data/mock_merchants.dart';
import '../models/merchant_mapping.dart';

class MerchantMatcher {
  String normalize(String input) {
    return input.trim().toLowerCase().replaceAll(' ', '');
  }

  MerchantMapping? findMerchant(String keyword) {
    final normalizedKeyword = normalize(keyword);

    if (normalizedKeyword.isEmpty) {
      return null;
    }

    // 1. 先比 merchantKey 完全相等
    for (final merchant in mockMerchants) {
      final normalizedKey = normalize(merchant.merchantKey);
      if (normalizedKeyword == normalizedKey) {
        return merchant;
      }
    }

    // 2. 再比 aliases 完全相等
    for (final merchant in mockMerchants) {
      for (final alias in merchant.aliases) {
        final normalizedAlias = normalize(alias);
        if (normalizedKeyword == normalizedAlias) {
          return merchant;
        }
      }
    }

    // 3. 最後才做較保守的模糊比對
    for (final merchant in mockMerchants) {
      final normalizedKey = normalize(merchant.merchantKey);

      if (_isSafePartialMatch(normalizedKeyword, normalizedKey)) {
        return merchant;
      }

      for (final alias in merchant.aliases) {
        final normalizedAlias = normalize(alias);

        if (_isSafePartialMatch(normalizedKeyword, normalizedAlias)) {
          return merchant;
        }
      }
    }

    return null;
  }

  bool _isSafePartialMatch(String keyword, String target) {
    if (keyword.length < 3 || target.length < 3) {
      return false;
    }

    return keyword.contains(target) || target.contains(keyword);
  }
}