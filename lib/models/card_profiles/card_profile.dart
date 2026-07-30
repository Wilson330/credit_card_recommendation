/// Marker base type so [UserCardBundle] can hold one profile field instead
/// of one nullable field per card (cubeProfile, jihoProfile, ...), and so
/// [CardRewardEvaluator] can have a single non-generic interface that a
/// registry can dispatch on by cardId.
abstract class CardProfile {
  const CardProfile();
}
