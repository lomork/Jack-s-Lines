import 'dart:async';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnlineService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _myId;
  String? _gameId;
  String? _playerRole; // "host" or "guest"
  StreamSubscription? _gameSubscription;

  // Callbacks to update the UI
  Function(Map<String, dynamic>)? onGameStateChanged;
  Function(String)? onGameError;

  // 1. FIND OR CREATE A GAME
  Future<void> findMatch() async {
    final prefs = await SharedPreferences.getInstance();
    _myId = prefs.getString('unique_id') ?? "Player_${Random().nextInt(9999)}";
    String myHandle = prefs.getString('unique_handle') ?? "Player";

    // NEW: Get my Avatar ID
    String myAvatar = prefs.getString('selected_avatar_id') ?? "avatar_1";

    // Look for a waiting game
    final snapshot = await _db.child('games').orderByChild('status').equalTo('waiting').limitToFirst(1).get();

    if (snapshot.exists) {
      // JOIN EXISTING GAME
      Map<dynamic, dynamic> games = snapshot.value as Map;
      _gameId = games.keys.first;
      _playerRole = "guest";

      await _db.child('games/$_gameId').update({
        'status': 'playing',
        'guest': _myId,
        'guest_name': myHandle,
        'guest_avatar': myAvatar, // <--- UPLOAD AVATAR
      });
    } else {
      // CREATE NEW GAME
      _gameId = _db.child('games').push().key;
      _playerRole = "host";

      await _db.child('games/$_gameId').set({
        'status': 'waiting',
        'host': _myId,
        'host_name': myHandle,
        'host_avatar': myAvatar, // <--- UPLOAD AVATAR
        'turn': 'host', // Host goes first
        'board': List.filled(100, 0), // Empty board
        'last_move': null
      });
    }

    _listenToGame();
  }

  Future<void> saveUserProfile(Map<String, dynamic> data) async {
    User? user = _auth.currentUser;
    if (user == null) return;

    // Update the specific fields at the correct path: users/AUTH_UID
    await _db.child('users/${user.uid}').update(data);
  }

  Future<bool> purchaseChip(String chipId, int cost) async {
    final prefs = await SharedPreferences.getInstance();
    String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    DatabaseReference userRef = _db.child('users/$uid');

    // 1. Get current data from Cloud
    final snapshot = await userRef.get();
    if (snapshot.exists) {
      Map<String, dynamic> data = Map<String, dynamic>.from(snapshot.value as Map);

      int currentCoins = data['coins'] ?? 0;
      List<String> owned = [];
      if (data['owned_chips'] != null) {
        owned = List<String>.from(data['owned_chips']);
      }

      // 2. Validate Purchase
      if (currentCoins >= cost && !owned.contains(chipId)) {
        // 3. Apply Changes
        currentCoins -= cost;
        owned.add(chipId);

        // 4. Save to Cloud
        await userRef.update({
          'coins': currentCoins,
          'owned_chips': owned,
        });

        // 5. Sync Local (for immediate UI response)
        await prefs.setInt('user_coins', currentCoins);
        await prefs.setStringList('owned_chips', owned);

        return true; // Success
      }
    }
    return false; // Failed (Not enough coins or already owned)
  }

  Future<void> recordGameEnd({required bool won, required String opponentName}) async {
    final prefs = await SharedPreferences.getInstance();
    String? uid = FirebaseAuth.instance.currentUser?.uid; // Actual Auth UID

    if (uid == null) return; // Not logged in

    DatabaseReference userRef = _db.child('users/$uid');

    // 1. Get current stats
    final snapshot = await userRef.get();
    if (snapshot.exists) {
      Map<String, dynamic> data = Map<String, dynamic>.from(snapshot.value as Map);

      int currentCoins = data['coins'] ?? 0;
      int currentWins = data['matches_won'] ?? 0;
      int currentPlayed = data['matches_played'] ?? 0;
      int currentStreak = data['streak'] ?? 0;

      // 2. Calculate new stats
      int coinsEarned = won ? 100 : 20; // 100 for win, 20 for participation
      int newCoins = currentCoins + coinsEarned;
      int newPlayed = currentPlayed + 1;
      int newWins = won ? currentWins + 1 : currentWins;
      int newStreak = won ? currentStreak + 1 : 0; // Reset streak on loss

      // 3. Create Match History Entry
      Map<String, dynamic> matchEntry = {
        'date': DateTime.now().toIso8601String(),
        'opponent': opponentName,
        'result': won ? "WIN" : "LOSS",
        'coins_earned': coinsEarned
      };

      // 4. Update Database
      await userRef.update({
        'coins': newCoins,
        'matches_played': newPlayed,
        'matches_won': newWins,
        'streak': newStreak,
      });

      // Add to history list (push creates a unique key for the list item)
      await userRef.child('match_history').push().set(matchEntry);

      // 5. Update Local Storage (so UI updates instantly)
      await prefs.setInt('user_coins', newCoins);
    }
  }

  Future<bool> purchaseItem(String itemId, String type, int costOrReward) async {
    final prefs = await SharedPreferences.getInstance();
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    DatabaseReference userRef = _db.child('users/${user.uid}');
    final snapshot = await userRef.get();

    if (snapshot.exists) {
      Map<String, dynamic> data = Map<String, dynamic>.from(snapshot.value as Map);
      int currentCoins = data['coins'] ?? 0;
      int currentLives = data['lives'] ?? 0;

      // LOGIC SWITCH BASED ON TYPE
      if (type == 'coinPack') {
        currentCoins += costOrReward;
      }
      else if (type == 'lifeRefill') {
        if (itemId == 'lives_one') {
          if (currentCoins >= 200) {
            currentCoins -= 200;
            currentLives += 1;
          } else {
            return false; // Not enough coins
          }
        } else if (itemId == 'lives_full') {
          currentLives = 5;
        }
      }

      // SAVE TO DB
      await userRef.update({
        'coins': currentCoins,
        'lives': currentLives,
      });

      // SYNC LOCAL
      await prefs.setInt('user_coins', currentCoins);

      return true;
    }
    return false;
  }

  Future<Map<String, dynamic>?> getUserProfile() async {
    User? user = _auth.currentUser;
    if (user == null) return null;

    final snapshot = await _db.child('users/${user.uid}').get();

    if (snapshot.exists) {
      return Map<String, dynamic>.from(snapshot.value as Map);
    }
    return null;
  }

  void _listenToGame() {
    if (_gameId == null) return;

    _gameSubscription = _db.child('games/$_gameId').onValue.listen((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data != null && onGameStateChanged != null) {
        onGameStateChanged!(Map<String, dynamic>.from(data));
      }
    });
  }

  Future<void> joinGameTransaction(String gameId, String myId, String myName, String myAvatar) async {
    final gameRef = _db.child('games/$gameId');

    await gameRef.runTransaction((Object? post) {
      if (post == null) {
        return Transaction.abort();
      }
      Map<String, dynamic> data = Map<String, dynamic>.from(post as Map);

      // Only join if it is STILL waiting
      if (data['status'] == 'waiting') {
        data['status'] = 'playing';
        data['guest'] = myId;
        data['guest_name'] = myName;
        data['guest_avatar'] = myAvatar;
        return Transaction.success(data);
      }
      return Transaction.abort();
    });
  }

  Future<void> sendMove(int index, String card, int playerValue) async {
    if (_gameId == null) return;

    await _db.child('games/$_gameId').update({
      'board/$index': playerValue,
      'last_move': {'card': card, 'index': index, 'player': _playerRole},
      'turn': _playerRole == 'host' ? 'guest' : 'host', // Switch turn
    });
  }

  // 4. CLEANUP
  void leaveGame() {
    _gameSubscription?.cancel();
    if (_gameId != null) {
      // Just stop listening for MVP
    }
  }

  String get myRole => _playerRole ?? "spectator";

  Future<void> cancelSearch() async {
    _gameSubscription?.cancel();

    // If I am the Host and nobody joined yet, delete the room
    if (_gameId != null && _playerRole == 'host') {
      final snapshot = await _db.child('games/$_gameId/status').get();
      if (snapshot.value == 'waiting') {
        await _db.child('games/$_gameId').remove(); // Delete from Firebase
      }
    }

    _gameId = null;
    _playerRole = null;
  }
}