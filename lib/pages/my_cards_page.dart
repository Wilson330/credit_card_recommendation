import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/user_cards_store.dart';
import 'add_card_page.dart';
import 'card_form_page.dart';
import 'widgets/card_thumbnail.dart';
import 'widgets/dialogs.dart';

class MyCardsPage extends StatelessWidget {
  const MyCardsPage({super.key});

  void _openAddCardPage(BuildContext context) {
    Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const AddCardPage()));
  }

  void _openEditPage(BuildContext context, UserCard card, CardOption? option) {
    if (option == null) {
      showMessageDialog(context, '後端目前不支援這張卡的設定');
      return;
    }
    Navigator.of(context).push(CupertinoPageRoute(
      builder: (_) => CardFormPage(option: option, existing: card),
    ));
  }

  /// 先刪後端,成功才從畫面移除;失敗時維持原狀並顯示原因。
  Future<bool> _confirmRemove(BuildContext context, UserCard card) async {
    try {
      await context.read<UserCardsStore>().remove(card.cardId);
      return true;
    } on ApiException catch (e) {
      if (context.mounted && !e.isUnauthorized) await showMessageDialog(context, e.message, title: '無法移除');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<UserCardsStore>();
    final userCards = store.userCards;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('我的卡片'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => _openAddCardPage(context),
          child: const Icon(CupertinoIcons.add),
        ),
      ),
      child: SafeArea(
        child: userCards.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.creditcard, size: 48, color: CupertinoColors.systemGrey.resolveFrom(context)),
                      const SizedBox(height: 12),
                      Text('目前還沒有加入任何卡片',
                          style: TextStyle(color: CupertinoColors.secondaryLabel.resolveFrom(context))),
                      const SizedBox(height: 16),
                      CupertinoButton.filled(onPressed: () => _openAddCardPage(context), child: const Text('新增卡片')),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                children: [
                  CupertinoListSection.insetGrouped(
                    header: const Text('已加入的卡片,左滑可移除'),
                    children: [
                      for (final card in userCards)
                        Dismissible(
                          key: ValueKey(card.cardId),
                          direction: DismissDirection.endToStart,
                          confirmDismiss: (_) => _confirmRemove(context, card),
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            color: CupertinoColors.destructiveRed.resolveFrom(context),
                            child: const Icon(CupertinoIcons.delete, color: CupertinoColors.white),
                          ),
                          child: Builder(builder: (context) {
                            final option = store.optionFor(card.cardId);
                            final summary = card.summary(option);
                            final bank = option?.bank ?? '';
                            return CupertinoListTile(
                              leading: CardThumbnail(cardId: card.cardId),
                              title: Text(card.cardName),
                              subtitle: Text([bank, summary].where((s) => s.isNotEmpty).join(' · ')),
                              trailing: const CupertinoListTileChevron(),
                              onTap: () => _openEditPage(context, card, option),
                            );
                          }),
                        ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
