import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/user_cards_store.dart';
import 'pick_merchants_page.dart';
import 'widgets/card_thumbnail.dart';
import 'widgets/dialogs.dart';

/// 新增或編輯一張卡。畫面依後端給的選項(CardOption)產生,不針對個別卡片寫死:
/// CUBE 的等級、Unicard 的方案與挑店、各卡的開關都從 /api/cards 來。
class CardFormPage extends StatefulWidget {
  final CardOption option;
  final UserCard? existing;

  const CardFormPage({super.key, required this.option, this.existing});

  @override
  State<CardFormPage> createState() => _CardFormPageState();
}

class _CardFormPageState extends State<CardFormPage> {
  late final Map<String, dynamic> _config;
  bool _busy = false;

  CardOption get _option => widget.option;
  bool get _isEdit => widget.existing != null;
  String? get _selected => _option.rateBy == null ? null : _config[_option.rateBy] as String?;
  bool get _needsPicks => _option.needsMerchantPicks(_selected);
  List<int> get _picks => List<int>.from((_config['chosen_merchants'] as List?) ?? const []);

  @override
  void initState() {
    super.initState();
    _config = {..._option.defaultConfig(), ...?widget.existing?.config};
  }

  Future<void> _pickMerchants() async {
    final result = await Navigator.of(context).push<List<int>>(CupertinoPageRoute(
      builder: (_) => PickMerchantsPage(
        cardId: _option.cardId,
        maxCount: _option.maxChosenMerchants ?? 0,
        initial: _picks,
      ),
    ));
    if (result != null) setState(() => _config['chosen_merchants'] = result);
  }

  Map<String, dynamic> _configToSave() {
    final config = <String, dynamic>{
      if (_option.rateBy != null) _option.rateBy!: _selected,
      for (final t in _option.toggles) t.key: _config[t.key] == true,
    };
    if (_needsPicks) config['chosen_merchants'] = _picks;
    return config;
  }

  Future<void> _save() => _run('無法儲存', () async {
        await context.read<UserCardsStore>().save(_option.cardId, _configToSave());
        if (!mounted) return;
        Navigator.of(context).pop();
        if (!_isEdit) Navigator.of(context).pop();     // 新增時一併關掉「新增卡片」清單
      });

  Future<void> _remove() => _run('無法移除', () async {
        await context.read<UserCardsStore>().remove(_option.cardId);
        if (mounted) Navigator.of(context).pop();
      });

  /// 執行儲存或移除;失敗時先停掉按鈕上的轉圈,再顯示原因。
  /// 401 會自動登出回到登入畫面,不另外跳訊息。
  Future<void> _run(String errorTitle, Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (!e.isUnauthorized) await showMessageDialog(context, e.message, title: errorTitle);
      return;
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _rateBySelector() {
    return CupertinoFormRow(
      prefix: Text(_option.rateByLabel),
      child: CupertinoSlidingSegmentedControl<String>(
        groupValue: _selected,
        children: {
          for (final o in _option.options)
            o: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(o)),
        },
        onValueChanged: (value) {
          if (value != null) setState(() => _config[_option.rateBy!] = value);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final maxPicks = _option.maxChosenMerchants ?? 0;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text(_isEdit ? '編輯 ${_option.name}' : '新增 ${_option.name}')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            Center(child: CardThumbnail(cardId: _option.cardId, width: 240)),
            const SizedBox(height: 8),
            Text(_option.bank, textAlign: TextAlign.center, style: TextStyle(color: secondary)),
            const SizedBox(height: 16),
            if (_option.rateBy != null || _option.toggles.isNotEmpty)
              CupertinoFormSection.insetGrouped(
                children: [
                  if (_option.rateBy != null) _rateBySelector(),
                  for (final t in _option.toggles)
                    CupertinoFormRow(
                      prefix: Text(t.label),
                      child: CupertinoSwitch(
                        value: _config[t.key] == true,
                        onChanged: (value) => setState(() => _config[t.key] = value),
                      ),
                    ),
                ],
              ),
            if (_needsPicks)
              CupertinoListSection.insetGrouped(
                footer: Text('$_selected 只有挑選的店家享有加碼回饋,最多 $maxPicks 家',
                    style: TextStyle(color: secondary, fontSize: 13)),
                children: [
                  CupertinoListTile(
                    title: const Text('挑選店家'),
                    additionalInfo: Text('${_picks.length} / $maxPicks'),
                    trailing: const CupertinoListTileChevron(),
                    onTap: _pickMerchants,
                  ),
                ],
              ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CupertinoButton.filled(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                    : Text(_isEdit ? '儲存變更' : '加入我的卡片'),
              ),
            ),
            if (_isEdit)
              CupertinoButton(
                onPressed: _busy ? null : _remove,
                child: Text('移除這張卡', style: TextStyle(color: CupertinoColors.destructiveRed.resolveFrom(context))),
              ),
          ],
        ),
      ),
    );
  }
}
