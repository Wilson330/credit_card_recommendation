import 'card_profiles/cube_card_profile.dart';
import 'card_profiles/jiho_card_profile.dart';
import 'wallet_card.dart';

class UserCardBundle {
  final WalletCard walletCard;
  final CubeCardProfile? cubeProfile;
  final JihoCardProfile? jihoProfile;

  const UserCardBundle({
    required this.walletCard,
    this.cubeProfile,
    this.jihoProfile,
  });
}