import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import 'widgets/dialogs.dart';

/// Unicard 任意選:從百大特店名單挑店。完成時回傳挑選的店家編號。
class PickMerchantsPage extends StatefulWidget {
  final String cardId;
  final int maxCount;
  final List<int> initial;

  const PickMerchantsPage({super.key, required this.cardId, required this.maxCount, required this.initial});

  @override
  State<PickMerchantsPage> createState() => _PickMerchantsPageState();
}

class _PickMerchantsPageState extends State<PickMerchantsPage> {
  late final Set<int> _selected = {...widget.initial};
  final _filter = TextEditingController();
  List<MerchantSuggestion>? _merchants;
  String? _error;

  @override
  void initState() {
    super.initState();
    _filter.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final merchants = await context.read<ApiClient>().pickableMerchants(widget.cardId);
      if (mounted) setState(() => _merchants = merchants);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _toggle(int id) {
    if (!_selected.contains(id) && _selected.length >= widget.maxCount) {
      showMessageDialog(context, '最多只能挑 ${widget.maxCount} 家,請先取消其他店家', title: '已達上限');
      return;
    }
    setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final merchants = _merchants;
    final keyword = _filter.text.trim().toLowerCase();
    // 注意不能用 const []:下面要 sort,const 清單不能修改(資料還沒載入時會當掉)
    final visible = <MerchantSuggestion>[
      for (final m in merchants ?? const <MerchantSuggestion>[])
        if (keyword.isEmpty || m.name.toLowerCase().contains(keyword)) m,
    ];
    // 已挑的排前面,方便確認
    visible.sort((a, b) {
      final pa = _selected.contains(a.merchantId) ? 0 : 1;
      final pb = _selected.contains(b.merchantId) ? 0 : 1;
      return pa != pb ? pa - pb : a.name.compareTo(b.name);
    });

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text('挑選店家 ${_selected.length} / ${widget.maxCount}'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(_selected.toList()),
          child: const Text('完成'),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: CupertinoSearchTextField(controller: _filter, placeholder: '搜尋店家'),
            ),
            Expanded(
              child: _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!),
                          CupertinoButton(onPressed: _load, child: const Text('重試')),
                        ],
                      ),
                    )
                  : merchants == null
                      ? const Center(child: CupertinoActivityIndicator())
                      : ListView.builder(
                          itemCount: visible.length,
                          itemBuilder: (context, i) {
                            final m = visible[i];
                            final picked = _selected.contains(m.merchantId);
                            return CupertinoListTile(
                              title: Text(m.name),
                              trailing: picked
                                  ? Icon(CupertinoIcons.check_mark, color: CupertinoColors.systemBlue.resolveFrom(context))
                                  : null,
                              onTap: () => _toggle(m.merchantId),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
