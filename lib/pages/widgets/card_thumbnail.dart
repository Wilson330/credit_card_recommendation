import 'package:flutter/cupertino.dart';

import '../../constants/card_art.dart';

/// Standard ID-1 card ratio (85.60mm x 53.98mm ≈ 1.586:1). Used anywhere a
/// small card visual is needed: My Cards, Add Card, Result page, and the
/// bigger preview at the top of each card's edit form.
class CardThumbnail extends StatelessWidget {
  final String cardId;
  final double width;

  const CardThumbnail({
    super.key,
    required this.cardId,
    this.width = 56,
  });

  double get _height => width / 1.586;

  @override
  Widget build(BuildContext context) {
    final asset = CardArt.frontImageFor(cardId);

    return ClipRRect(
      borderRadius: BorderRadius.circular(width * 0.1),
      child: SizedBox(
        width: width,
        height: _height,
        child: asset != null
            ? Image.asset(asset, fit: BoxFit.cover)
            : ColoredBox(
                color: CupertinoColors.systemGrey5.resolveFrom(context),
                child: Icon(
                  CupertinoIcons.creditcard,
                  size: _height * 0.5,
                  color: CupertinoColors.systemGrey.resolveFrom(context),
                ),
              ),
      ),
    );
  }
}
