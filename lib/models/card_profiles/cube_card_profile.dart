import 'card_profile.dart';

class CubeCardProfile extends CardProfile {
  final String selectedLevel;
  final String selectedRights;
  final bool isNewCardHolder;

  const CubeCardProfile({
    required this.selectedLevel,
    required this.selectedRights,
    required this.isNewCardHolder,
  });
}
