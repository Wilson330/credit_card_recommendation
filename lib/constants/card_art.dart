/// Single source of truth for card face artwork, keyed by cardId, so
/// no page hardcodes an image path per card. Adding a new card means
/// adding one entry here.
class CardArt {
  static const Map<String, String> _frontImageByCardId = {
    'cathay_cube': 'assets/card_faces/cube_front.png',
    'ubot_jiho': 'assets/card_faces/jiho_front.png',
  };

  static String? frontImageFor(String cardId) => _frontImageByCardId[cardId];
}
