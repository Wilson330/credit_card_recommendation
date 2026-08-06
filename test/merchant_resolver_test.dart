import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/services/merchant_repository.dart';
import 'package:my_first_app/services/merchant_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await MerchantRepository.instance.load();
  });

  test('resolves an exact canonical name to its tags', () {
    final resolver = MerchantResolver();
    final tags = resolver.tagsFor('藏壽司');

    expect(tags, contains('restaurant'));
  });

  test('resolves via conservative substring match on canonical_name', () {
    final resolver = MerchantResolver();
    // "小北" is a substring of the canonical name "小北百貨", and isn't
    // registered as an alias, so this exercises tier 2, not tier 1.
    final tags = resolver.tagsFor('小北');

    expect(tags, contains('general_retail'));
  });

  test('resolves an English alias to the same merchant as its Chinese canonical name', () {
    final resolver = MerchantResolver();

    final viaAlias = resolver.resolve('KFC');
    final viaCanonical = resolver.resolve('肯德基');

    expect(viaAlias, isNotNull);
    expect(viaAlias!.merchantId, viaCanonical!.merchantId);
    expect(viaAlias.tags, contains('fast_food'));
  });

  test('resolves a common Chinese short form alias (7-11 -> 7-ELEVEN 實體門市)', () {
    final resolver = MerchantResolver();
    final tags = resolver.tagsFor('7-11');

    expect(tags, contains('chain_store'));
  });

  test('resolves the official corporate name alias (統一超商 -> 7-ELEVEN 實體門市)', () {
    // User-reported gap: typed "統一超商" (7-11 Taiwan's operating
    // company name) expecting the same result as "7-11", got default
    // instead — the alias itself was just missing from the list.
    final resolver = MerchantResolver();

    final viaAlias = resolver.resolve('統一超商');
    final viaShortForm = resolver.resolve('7-11');

    expect(viaAlias, isNotNull);
    expect(viaAlias!.merchantId, viaShortForm!.merchantId);
  });

  test('returns no tags for a merchant not in the directory', () {
    final resolver = MerchantResolver();
    final tags = resolver.tagsFor('完全沒聽過的店家名稱');

    expect(tags, isEmpty);
  });

  test('empty query returns no tags', () {
    final resolver = MerchantResolver();
    expect(resolver.tagsFor(''), isEmpty);
  });
}
