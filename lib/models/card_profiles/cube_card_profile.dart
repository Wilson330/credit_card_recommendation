import 'card_profile.dart';

class CubeCardProfile extends CardProfile {
  final String selectedLevel;
  final bool isNewCardHolder;

  const CubeCardProfile({
    required this.selectedLevel,
    required this.isNewCardHolder,
  });
}
