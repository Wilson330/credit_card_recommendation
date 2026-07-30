import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/state/search_history_store.dart';

void main() {
  test('most recent search comes first', () {
    final store = SearchHistoryStore();
    store.recordSearch('全家');
    store.recordSearch('誠品生活');

    expect(store.history, ['誠品生活', '全家']);
  });

  test('re-searching an existing term moves it to the front instead of duplicating', () {
    final store = SearchHistoryStore();
    store.recordSearch('全家');
    store.recordSearch('誠品生活');
    store.recordSearch('全家');

    expect(store.history, ['全家', '誠品生活']);
  });

  test('caps history at 8 entries', () {
    final store = SearchHistoryStore();
    for (var i = 0; i < 10; i++) {
      store.recordSearch('商家$i');
    }

    expect(store.history.length, 8);
    expect(store.history.first, '商家9');
  });

  test('blank input is ignored', () {
    final store = SearchHistoryStore();
    store.recordSearch('   ');

    expect(store.history, isEmpty);
  });

  test('clear empties the history', () {
    final store = SearchHistoryStore();
    store.recordSearch('全家');
    store.clear();

    expect(store.history, isEmpty);
  });
}
