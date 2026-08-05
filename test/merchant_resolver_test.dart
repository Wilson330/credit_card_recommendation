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

  test('resolves via conservative substring match', () {
    final resolver = MerchantResolver();
    final tags = resolver.tagsFor('路易莎');

    expect(tags, contains('coffee'));
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
