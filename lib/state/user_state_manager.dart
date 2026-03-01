import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class UserStateManager {
  static final UserStateManager instance = UserStateManager._internal();
  UserStateManager._internal();

  int userCoins = 0;
  int lives = 0;
  int streak = 0;
  String avatarId = "avatar_1";
  String username = "Player";
  String selectedChipId = "default_blue";

  Future<void> loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    String? uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid != null) {
      final snapshot = await FirebaseDatabase.instance.ref('users/$uid').get();
      if (snapshot.exists) {
        final data = snapshot.value as Map;
        userCoins = data['coins'] ?? 0;
        lives = data['lives'] ?? 5;
        streak = data['streak'] ?? 0;
        avatarId = data['avatar_id'] ?? "avatar_1";
        username = data['handle'] ?? "Player";
        selectedChipId = data['selected_chip_id'] ?? "default_blue";

        // Save backups locally
        await prefs.setInt('user_coins', userCoins);
        await prefs.setInt('streak', streak);
        await prefs.setString('selected_avatar_id', avatarId);
      }
    } else {
      // Fallback to local if network fails
      userCoins = prefs.getInt('user_coins') ?? 0;
      streak = prefs.getInt('streak') ?? 0;
      avatarId = prefs.getString('selected_avatar_id') ?? "avatar_1";
    }
  }
}