import 'dart:async';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnlineService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

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
        'guest_name': prefs.getString('unique_handle') ?? "Guest"
      });
    } else {
      // CREATE NEW GAME
      _gameId = _db.child('games').push().key;
      _playerRole = "host";

      await _db.child('games/$_gameId').set({
        'status': 'waiting',
        'host': _myId,
        'host_name': prefs.getString('unique_handle') ?? "Host",
        'turn': 'host', // Host goes first
        'board': List.filled(100, 0), // Empty board
        'last_move': null
      });
    }

    _listenToGame();
  }

  Future<void> saveUserProfile(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    String myId = prefs.getString('unique_id') ?? "unknown_user";

    await _db.child('users/$myId').update(data);
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
    String? myId = prefs.getString('unique_id'); // This is the ID used in DB keys
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

  Future<Map<String, dynamic>?> getUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    String myId = prefs.getString('unique_id') ?? "unknown_user";

    final snapshot = await _db.child('users/$myId').get();

    if (snapshot.exists) {
      return Map<String, dynamic>.from(snapshot.value as Map);
    }
    return null; // No cloud data yet
  }

  // 2. LISTEN FOR UPDATES
  void _listenToGame() {
    if (_gameId == null) return;

    _gameSubscription = _db.child('games/$_gameId').onValue.listen((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data != null && onGameStateChanged != null) {
        // Convert to Map<String, dynamic> for easier use
        onGameStateChanged!(Map<String, dynamic>.from(data));
      }
    });
  }

  // 3. SEND MOVE
  Future<void> sendMove(int index, String card, int playerValue) async {
    if (_gameId == null) return;

    // Update the board at specific index
    // Note: In Firebase arrays are tricky, so we update specific keys if using a map,
    // or just upload the whole board state for simplicity in MVP.
    // For speed, let's just send the "last_move" and let the UI update the board locally,
    // then sync the board array periodically.

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
      // If waiting, delete. If playing, maybe mark as disconnected.
      // Simple version: just stop listening.
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