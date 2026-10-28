import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import 'widgets/dialogs.dart';

/// 挑店的結果:店家編號與行動支付名稱。
typedef PickResult = ({List<int> merchants, List<String> paymentMethods});

/// Unicard 任意選:從百大特店名單挑店,也可以挑行動支付(兩者合計最多 [maxCount] 家)。
/// 完成時回傳 [PickResult]。
class PickMerchantsPage extends StatefulWidget {
  final String cardId;
  final int maxCount;
  final List<int> initial;

  /// 可以挑的行動支付。
  final List<String> paymentMethods;

  /// 使用者有綁定的行動支付;挑了但沒綁定的不會計算,畫面上要提示。
  final List<String> boundPaymentMethods;
  final List<String> initialPaymentMethods;

  const PickMerchantsPage({
    super.key,
    required this.cardId,
    required this.maxCount,
    required this.initial,
    this.paymentMethods = const [],
    this.boundPaymentMethods = const [],
    this.initialPaymentMethods = const [],
  });

  @override
  State<PickMerchantsPage> createState() => _PickMerchantsPageState();
}

class _PickMerchantsPageState extends State<PickMerchantsPage> {
  late final Set<int> _selected = {...widget.initial};
  late final Set<String> _selectedPayments = {...widget.initialPaymentMethods};
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

  int get _count => _selected.length + _selectedPayments.length;

  bool _checkLimit(bool adding) {
    if (adding && _count >= widget.maxCount) {
      showMessageDialog(context, '最多只能挑 ${widget.maxCount} 家(行動支付也算在內),請先取消其他項目', title: '已達上限');
      return false;
    }
    return true;
  }

  void _toggle(int id) {
    if (!_checkLimit(!_selected.contains(id))) return;
    setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));
  }

  void _togglePayment(String name) {
    if (!_checkLimit(!_selectedPayments.contains(name))) return;
    setState(() => _selectedPayments.contains(name) ? _selectedPayments.remove(name) : _selectedPayments.add(name));
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
    final payments = [
      for (final p in widget.paymentMethods)
        if (keyword.isEmpty || p.toLowerCase().contains(keyword)) p,
    ];
    final check = Icon(CupertinoIcons.check_mark, color: CupertinoColors.systemBlue.resolveFrom(context));
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text('挑選店家 $_count / ${widget.maxCount}'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop<PickResult>((
            merchants: _selected.toList(),
            paymentMethods: [for (final p in widget.paymentMethods) if (_selectedPayments.contains(p)) p],
          )),
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
                      : ListView(
                          children: [
                            if (payments.isNotEmpty) ...[
                              _Header('行動支付', color: secondary),
                              for (final p in payments)
                                CupertinoListTile(
                                  title: Text(p),
                                  subtitle: widget.boundPaymentMethods.contains(p) ? null : const Text('尚未綁定,不會計算'),
                                  trailing: _selectedPayments.contains(p) ? check : null,
                                  onTap: () => _togglePayment(p),
                                ),
                              _Header('店家', color: secondary),
                            ],
                            for (final m in visible)
                              CupertinoListTile(
                                title: Text(m.name),
                                trailing: _selected.contains(m.merchantId) ? check : null,
                                onTap: () => _toggle(m.merchantId),
                              ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  final Color color;

  const _Header(this.text, {required this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(text, style: TextStyle(fontSize: 13, color: color)),
      );
}
