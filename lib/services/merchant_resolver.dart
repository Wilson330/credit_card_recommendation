import '../models/merchant.dart';
import 'merchant_matcher.dart';
import 'merchant_repository.dart';

/// Resolves a user's typed merchant text to a canonical [Merchant], so its
/// `tags` can feed RuleMatcher's category-type rules — until this exists,
/// MerchantQueryContext.merchantTags is always empty and category rules
/// (see SCHEMA.md) can never fire. Same two-tier philosophy as RuleMatcher:
/// exact match wins outright when present, conservative substring match
/// (>= 2 chars, either side contains the other) is only a fallback.
class MerchantResolver {
  MerchantResolver({MerchantRepository? repository})
      : _repository = repository ?? MerchantRepository.instance;

  static const _minSafeMatchLength = 2;

  final MerchantRepository _repository;

  Merchant? resolve(String query) {
    final normalizedQuery = MerchantMatcher.normalize(query);
    if (normalizedQuery.isEmpty) return null;

    final merchants = _repository.all().where((m) => m.active);

    for (final merchant in merchants) {
      if (MerchantMatcher.normalize(merchant.canonicalName) == normalizedQuery) {
        return merchant;
      }
    }

    if (normalizedQuery.length < _minSafeMatchLength) return null;

    for (final merchant in merchants) {
      final normalizedName = MerchantMatcher.normalize(merchant.canonicalName);
      if (normalizedName.length < _minSafeMatchLength) continue;
      if (normalizedName.contains(normalizedQuery) ||
          normalizedQuery.contains(normalizedName)) {
        return merchant;
      }
    }

    return null;
  }

  List<String> tagsFor(String query) => resolve(query)?.tags ?? const [];
}
