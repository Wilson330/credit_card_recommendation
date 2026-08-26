import 'card_profile.dart';

class CubeCardProfile extends CardProfile {
  final String selectedLevel;
  final bool isNewCardHolder;

  /// Gates the 童樂匯 benefit scheme (see RuleMatcher's requiredConditions
  /// design and SCHEMA.md). Optional with a false default so existing
  /// construction sites don't need updating just to add this flag — the
  /// Flutter UI doesn't expose a toggle for it yet (deliberately out of
  /// scope for this pass; the underlying model/logic needed to be correct
  /// for the Swift port regardless of whether this app's own UI surfaces it).
  final bool hasKidsClub;

  const CubeCardProfile({
    required this.selectedLevel,
    required this.isNewCardHolder,
    this.hasKidsClub = false,
  });
}
