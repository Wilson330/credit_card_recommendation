import '../models/card_profiles/cube_card_profile.dart';
import '../models/card_profiles/jiho_card_profile.dart';
import '../models/user_card_bundle.dart';
import '../models/wallet_card.dart';

final mockUserCards = <UserCardBundle>[
  UserCardBundle(
    walletCard: const WalletCard(
      id: 'wallet_1',
      cardId: 'cathay_cube',
      bankName: '國泰世華',
      cardName: 'CUBE Card',
      network: 'Visa',
    ),
    cubeProfile: const CubeCardProfile(
      selectedLevel: 'level_3',
      selectedRights: 'daily_select',
      isNewCardHolder: false,
    ),
  ),
  UserCardBundle(
    walletCard: const WalletCard(
      id: 'wallet_2',
      cardId: 'ubot_jiho',
      bankName: '聯邦銀行',
      cardName: '吉鶴卡',
      network: 'Mastercard',
    ),
    jihoProfile: const JihoCardProfile(
      isNewCardHolder: true,
    ),
  ),
];