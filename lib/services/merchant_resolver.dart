import '../models/merchant.dart';
import 'merchant_matcher.dart';
import 'merchant_repository.dart';

/// Resolves a user's typed merchant text to a canonical [Merchant], so its
/// `tags` can feed RuleMatcher's category-type rules — until this exists,
/// MerchantQueryContext.merchantTags is always empty and category rules
/// (see SCHEMA.md) can never fire. Same two-tier philosophy as RuleMatcher:
/// exact match wins outright when present (checked against canonicalName
/// AND every alias, so e.g. "KFC" resolves the same merchant as "肯德基"),
/// conservative substring match (>= 2 chars, either side contains the
/// other) is only a fallback.
class MerchantResolver {
  MerchantResolver({MerchantRepository? repository})
      : _repository = repository ?? MerchantRepository.instance;

  static const _minSafeMatchLength = 2;

  final MerchantRepository _repository;

  Iterable<String> _namesFor(Merchant merchant) sync* {
    yield merchant.canonicalName;
    yield* merchant.aliases;
  }

  Merchant? resolve(String query) {
    final normalizedQuery = MerchantMatcher.normalize(query);
    if (normalizedQuery.isEmpty) return null;

    final merchants = _repository.all().where((m) => m.active);

    for (final merchant in merchants) {
      for (final name in _namesFor(merchant)) {
        if (MerchantMatcher.normalize(name) == normalizedQuery) {
          return merchant;
        }
      }
    }

    if (normalizedQuery.length < _minSafeMatchLength) return null;

    for (final merchant in merchants) {
      for (final name in _namesFor(merchant)) {
        final normalizedName = MerchantMatcher.normalize(name);
        if (normalizedName.length < _minSafeMatchLength) continue;
        if (normalizedName.contains(normalizedQuery) ||
            normalizedQuery.contains(normalizedName)) {
          return merchant;
        }
      }
    }

    return null;
  }

  List<String> tagsFor(String query) => resolve(query)?.tags ?? const [];
}
