import 'dart:async';
import 'dart:math';
import 'dart:ui';
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
  int? _lastProcessedSoundTime;

  // Callbacks to update the UI
  Function(Map<String, dynamic>)? onGameStateChanged;
  Function(String)? onGameError;
  Function(String)? onSoundReceived;

  VoidCallback? onMatchFound;

  String? get currentGameId => _gameId;

  // --- NEW: SERVER MAINTENANCE CHECK ---
  Future<bool> isMaintenanceActive() async {
    try {
      final snapshot = await _db.child('global_config/maintenance_active').get();
      if (snapshot.exists) {
        return snapshot.value as bool;
      }
    } catch (e) {
      // If path doesn't exist, assume servers are up
    }
    return false;
  }

  // 1. FIND OR CREATE A GAME
  Future<void> findMatch({String? chipId}) async {
    final prefs = await SharedPreferences.getInstance();

    User? user = _auth.currentUser;
    _myId = user?.uid ?? prefs.getString('unique_id') ?? "Player_${Random().nextInt(9999)}";

    String myHandle = prefs.getString('unique_handle') ?? user?.displayName ?? "Player";
    String myAvatar = prefs.getString('selected_avatar_id') ?? "avatar_1";

    final snapshot = await _db.child('games').orderByChild('status').equalTo('waiting').limitToFirst(1).get();

    if (snapshot.exists && snapshot.value is Map) {
      Map<dynamic, dynamic> games = snapshot.value as Map;
      _gameId = games.keys.first;
      _playerRole = "guest";

      await _db.child('games/$_gameId').update({
        'status': 'playing',
        'guest_id': _myId,
        'guest_name': myHandle,
        'guest_avatar': myAvatar,
        'guest_chip_id': chipId ?? "default_red",
        'match_start_time': ServerValue.timestamp,
      });
      await _db.child('lobby').child(_gameId!).remove();
      onMatchFound?.call();
    } else {
      // CREATE NEW GAME
      _gameId = _db.child('games').push().key;
      _playerRole = "host";

      await _db.child('games/$_gameId').set({
        'status': 'waiting',
        'host_id': _myId,
        'host_name': myHandle,
        'host_avatar': myAvatar,
        'host_chip_id': chipId ?? "default_blue",
        'turn': 'host',
        'board': List.filled(100, 0),
        'last_move': null,
        'last_sound': null,
      });
      await _db.child('lobby').child(_gameId!).set(_myId);
    }

    _listenToGame();
  }

  Future<void> sendSound(String soundName) async {
    if (_gameId == null) return;

    await _db.child('games/$_gameId').update({
      'last_sound': {
        'name': soundName,
        'sender': _myId,
        'time': ServerValue.timestamp,
      }
    });
  }

  Future<void> sendForfeit() async {
    if (_gameId == null) return;
    await _db.child('games/$_gameId').update({
      'status': 'forfeit',
      'loser': _myId,
    });
  }

  Future<void> sendChatMessage(String text) async {
    if (_gameId == null || text.trim().isEmpty) return;

    // Using push().set() is correct, the duplication happens in the UI listener
    await _db.child('games/$_gameId/chats').push().set({
      'sender': _myId,
      'text': text,
      'timestamp': ServerValue.timestamp,
    });
  }

  Future<void> saveUserProfile(Map<String, dynamic> data) async {
    User? user = _auth.currentUser;
    if (user == null) return;
    await _db.child('users/${user.uid}').update(data);
  }

  Future<bool> purchaseChip(String chipId, int cost) async {
    final prefs = await SharedPreferences.getInstance();
    String? uid = _auth.currentUser?.uid;
    if (uid == null) return false;

    DatabaseReference userRef = _db.child('users/$uid');
    final snapshot = await userRef.get();

    if (snapshot.exists) {
      Map<String, dynamic> data = Map<String, dynamic>.from(snapshot.value as Map);
      int currentCoins = data['coins'] ?? 0;
      List<String> owned = data['owned_chips'] != null
          ? List<String>.from(data['owned_chips'])
          : [];

      if (currentCoins >= cost && !owned.contains(chipId)) {
        currentCoins -= cost;
        owned.add(chipId);

        await userRef.update({
          'coins': currentCoins,
          'owned_chips': owned,
        });

        await prefs.setInt('user_coins', currentCoins);
        await prefs.setStringList('owned_chips', owned);
        return true;
      }
    }
    return false;
  }

  Future<void> recordGameEnd({required bool won, required String opponentName}) async {
    final prefs = await SharedPreferences.getInstance();
    String? uid = _auth.currentUser?.uid;
    if (uid == null) return;

    DatabaseReference userRef = _db.child('users/$uid');
    final snapshot = await userRef.get();

    if (snapshot.exists) {
      Map<String, dynamic> data = Map<String, dynamic>.from(snapshot.value as Map);
      int currentCoins = data['coins'] ?? 0;
      int currentWins = data['matches_won'] ?? 0;
      int currentPlayed = data['matches_played'] ?? 0;
      int currentStreak = data['streak'] ?? 0;

      int coinsEarned = won ? 100 : 20;
      int newCoins = currentCoins + coinsEarned;
      int newPlayed = currentPlayed + 1;
      int newWins = won ? currentWins + 1 : currentWins;
      int newStreak = won ? currentStreak + 1 : 0;

      Map<String, dynamic> matchEntry = {
        'date': DateTime.now().toIso8601String(),
        'opponent': opponentName,
        'result': won ? "WIN" : "LOSS",
        'coins_earned': coinsEarned,
        'mode': 'Online'
      };

      await userRef.update({
        'coins': newCoins,
        'matches_played': newPlayed,
        'matches_won': newWins,
        'streak': newStreak,
      });

      await userRef.child('match_history').push().set(matchEntry);
      await prefs.setInt('user_coins', newCoins);
    }
  }

  Future<bool> purchaseItem(String itemId, String type, int costOrReward) async {
    final prefs = await SharedPreferences.getInstance();
    User? user = _auth.currentUser;
    if (user == null) return false;

    DatabaseReference userRef = _db.child('users/${user.uid}');
    final snapshot = await userRef.get();

    if (snapshot.exists) {
      Map<String, dynamic> data = Map<String, dynamic>.from(snapshot.value as Map);
      int currentCoins = data['coins'] ?? 0;
      int currentLives = data['lives'] ?? 0;

      if (type == 'coinPack') {
        currentCoins += costOrReward;
      } else if (type == 'lifeRefill') {
        if (itemId == 'lives_one') {
          if (currentCoins >= 200) {
            currentCoins -= 200;
            currentLives += 1;
          } else {
            return false;
          }
        } else if (itemId == 'lives_full') {
          currentLives = 5;
        }
      }

      await userRef.update({'coins': currentCoins, 'lives': currentLives});
      await prefs.setInt('user_coins', currentCoins);
      return true;
    }
    return false;
  }

  Future<Map<String, dynamic>?> getUserProfile() async {
    User? user = _auth.currentUser;
    if (user == null) return null;
    final snapshot = await _db.child('users/${user.uid}').get();
    return snapshot.exists ? Map<String, dynamic>.from(snapshot.value as Map) : null;
  }

  void _listenToGame() {
    if (_gameId == null) return;
    _gameSubscription = _db.child('games/$_gameId').onValue.listen((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data != null && onGameStateChanged != null) {
        onGameStateChanged!(Map<String, dynamic>.from(data));

        if (data['last_sound'] != null) {
          final soundData = data['last_sound'];
          final int? soundTime = soundData['time'];

          if (soundData['sender'] != _myId &&
              soundTime != null &&
              soundTime != _lastProcessedSoundTime) {
            _lastProcessedSoundTime = soundTime;

            String soundName = soundData['name'];
            if (!soundName.contains('.')) {
              soundName = '$soundName.mp3';
            }
            onSoundReceived?.call(soundName);
          }
        }
      }
    });
  }

  Future<void> sendMove(int index, String card, int playerValue) async {
    if (_gameId == null) return;
    await _db.child('games/$_gameId').update({
      'board/$index': playerValue,
      'last_move': {'card': card, 'index': index, 'player': _playerRole},
      'turn': _playerRole == 'host' ? 'guest' : 'host',
    });
  }

  void leaveGame() {
    _gameSubscription?.cancel();
    _gameId = null;
    _playerRole = null;
  }

  String get myRole => _playerRole ?? "spectator";

  Future<void> cancelSearch() async {
    _gameSubscription?.cancel();
    if (_gameId != null && _playerRole == 'host') {
      final snapshot = await _db.child('games/$_gameId/status').get();
      if (snapshot.value == 'waiting') {
        await _db.child('games/$_gameId').remove();
      }
    }
    _gameId = null;
    _playerRole = null;
  }
}