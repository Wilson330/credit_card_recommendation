import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../state/user_cards_store.dart';
import 'card_form_page.dart';
import 'widgets/card_thumbnail.dart';

/// 列出後端支援的所有卡片(來自 cards.yaml)。後端新增卡片時,這裡不用改程式就會出現。
class AddCardPage extends StatelessWidget {
  const AddCardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<UserCardsStore>();
    final options = store.options;

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('新增卡片')),
      child: SafeArea(
        child: options.isEmpty
            ? Center(
                child: store.isLoading
                    ? const CupertinoActivityIndicator()
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(store.error ?? '目前沒有可以新增的卡片', textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            CupertinoButton(onPressed: store.refresh, child: const Text('重新載入')),
                          ],
                        ),
                      ),
              )
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                children: [
                  CupertinoListSection.insetGrouped(
                    children: [
                      for (final option in options)
                        Builder(builder: (context) {
                          final existing = store.findByCardId(option.cardId);
                          final isAdded = existing != null;
                          return CupertinoListTile(
                            leading: CardThumbnail(cardId: option.cardId),
                            title: Text(option.name),
                            subtitle: Text(isAdded ? '${option.bank} · 已加入,點擊編輯' : '${option.bank} · 點擊新增'),
                            trailing: Text(
                              isAdded ? '編輯' : '新增',
                              style: TextStyle(
                                color: (isAdded ? CupertinoColors.systemOrange : CupertinoColors.systemBlue)
                                    .resolveFrom(context),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onTap: () => Navigator.of(context).push(CupertinoPageRoute(
                              builder: (_) => CardFormPage(option: option, existing: existing),
                            )),
                          );
                        }),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
