import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/card_profiles/jiho_card_profile.dart';
import '../../models/user_card_bundle.dart';
import '../../models/wallet_card.dart';
import '../../state/user_cards_store.dart';

class JihoCardFormPage extends StatefulWidget {
  final UserCardBundle? existingCard;

  const JihoCardFormPage({
    super.key,
    this.existingCard,
  });

  @override
  State<JihoCardFormPage> createState() => _JihoCardFormPageState();
}

class _JihoCardFormPageState extends State<JihoCardFormPage> {
  late bool isNewCardHolder;
  late String selectedNetwork;

  bool get isEditMode => widget.existingCard != null;

  @override
  void initState() {
    super.initState();

    final existingProfile = widget.existingCard?.profile as JihoCardProfile?;
    final existingWalletCard = widget.existingCard?.walletCard;

    isNewCardHolder = existingProfile?.isNewCardHolder ?? false;
    selectedNetwork = existingWalletCard?.network ?? 'Mastercard';
  }

  void _handleSave() {
    final existingWalletCard = widget.existingCard?.walletCard;

    final userCard = UserCardBundle(
      walletCard: WalletCard(
        id: existingWalletCard?.id ??
            'wallet_jiho_${DateTime.now().millisecondsSinceEpoch}',
        cardId: 'ubot_jiho',
        bankName: '聯邦銀行',
        cardName: '吉鶴卡',
        network: selectedNetwork,
      ),
      profile: JihoCardProfile(
        isNewCardHolder: isNewCardHolder,
      ),
    );

    final store = context.read<UserCardsStore>();

    if (isEditMode) {
      store.updateCard(userCard);
      Navigator.of(context).pop();
    } else {
      store.addCard(userCard);
      Navigator.of(context).pop();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditMode ? '編輯吉鶴卡' : '新增吉鶴卡'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: selectedNetwork,
            decoration: const InputDecoration(
              labelText: '發卡組織',
            ),
            items: const [
              DropdownMenuItem(value: 'Visa', child: Text('Visa')),
              DropdownMenuItem(value: 'Mastercard', child: Text('Mastercard')),
              DropdownMenuItem(value: 'JCB', child: Text('JCB')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                selectedNetwork = value;
              });
            },
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('吉鶴新戶'),
            value: isNewCardHolder,
            onChanged: (value) {
              setState(() {
                isNewCardHolder = value;
              });
            },
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _handleSave,
            child: Text(isEditMode ? '儲存變更' : '加入我的卡片'),
          ),
        ],
      ),
    );
  }
}