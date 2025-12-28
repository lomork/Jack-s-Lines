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
  Timer? _searchDebounce;

  // Callbacks to update the UI
  Function(Map<String, dynamic>)? onGameStateChanged;
  Function(String)? onGameError;
  Function(String)? onSoundReceived;
  Function(String)? onBurnEffectReceived; // NEW: Callback for burn animation

  VoidCallback? onMatchFound;

  String? get currentGameId => _gameId;
  String get myRole => _playerRole ?? "spectator";

  // --- MAINTENANCE & CONFIG ---

  Future<bool> isMaintenanceActive() async {
    try {
      final snapshot = await _db.child('global_config/maintenance_active').get();
      if (snapshot.exists) {
        return snapshot.value as bool;
      }
    } catch (e) {
      print("Config error: $e");
    }
    return false;
  }

  // --- PROFILE & SEARCH ---

  List<String> _generateSearchIndex(String username) {
    List<String> index = [];
    String temp = "";
    for (int i = 0; i < username.length; i++) {
      temp += username[i].toLowerCase();
      index.add(temp);
    }
    return index;
  }

  Future<void> updateProfile({
    required String username,
    required String avatar,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final updates = <String, dynamic>{
        'public_profiles/${user.uid}': {
          'username': username,
          'username_lowercase': username.toLowerCase(),
          'avatar': avatar,
          'last_seen': ServerValue.timestamp,
          'search_index': _generateSearchIndex(username),
        },
        'users/${user.uid}/private_meta': {
          'last_login': ServerValue.timestamp,
          'version': '1.1.0',
        },
      };

      await _db.update(updates);
    } catch (e) {
      print("ERROR: Failed to update profile: $e");
    }
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.isEmpty) return [];

    try {
      final lowercaseQuery = query.toLowerCase();
      final snapshot = await _db
          .child('public_profiles')
          .orderByChild('username_lowercase')
          .startAt(lowercaseQuery)
          .endAt(lowercaseQuery + "\uf8ff")
          .limitToFirst(20)
          .get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        return data.entries.map((e) {
          final val = Map<String, dynamic>.from(e.value as Map);
          val['uid'] = e.key;
          return val;
        }).toList();
      }
    } catch (e) {
      print("CRITICAL: Search failed. Error: $e");
    }
    return [];
  }

  Future<void> saveUserProfile(Map<String, dynamic> data) async {
    User? user = _auth.currentUser;
    if (user == null) return;
    try {
      await _db.child('users/${user.uid}').update(data);
      if (data.containsKey('username')) {
        await updateProfile(
            username: data['username'],
            avatar: data['avatar'] ?? "avatar_1"
        );
      }
    } catch (e) {
      print("Save profile error: $e");
    }
  }

  Future<Map<String, dynamic>?> getUserProfile() async {
    User? user = _auth.currentUser;
    if (user == null) return null;
    try {
      final snapshot = await _db.child('users/${user.uid}').get();
      return snapshot.exists ? Map<String, dynamic>.from(snapshot.value as Map) : null;
    } catch (e) {
      print("Get profile error: $e");
      return null;
    }
  }

  // --- FRIENDS LOGIC ---

  Stream<DatabaseEvent> getFriendsStream() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();
    return _db.child('users/${user.uid}/friends').onValue;
  }

  Future<Map<String, dynamic>?> getFriendPublicData(String friendUid) async {
    try {
      final snapshot = await _db.child('public_profiles/$friendUid').get();
      if (snapshot.exists) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
    } catch (e) {
      print("Error fetching friend data: $e");
    }
    return null;
  }

  Future<void> addFriend(String friendUid) async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _db.child('users/${user.uid}/friends/$friendUid').set({
        'added_at': ServerValue.timestamp,
        'status': 'active',
      });
    } catch (e) {
      print("ERROR: Could not add friend: $e");
    }
  }

  // --- MATCHMAKING & GAMEPLAY ---

  Future<void> findMatch({String? chipId}) async {
    final prefs = await SharedPreferences.getInstance();

    User? user = _auth.currentUser;
    _myId = user?.uid ?? prefs.getString('unique_id') ?? "Player_${Random().nextInt(9999)}";

    String myHandle = prefs.getString('unique_handle') ?? user?.displayName ?? "Player";
    String myAvatar = prefs.getString('selected_avatar_id') ?? "avatar_1";

    try {
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
          'last_burn': null, // Tracking burn events
        });
        await _db.child('lobby').child(_gameId!).set(_myId);
      }
      _listenToGame();
    } catch (e) {
      onGameError?.call("Matchmaking error: $e");
    }
  }

  void _listenToGame() {
    if (_gameId == null) return;
    _gameSubscription = _db.child('games/$_gameId').onValue.listen((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data != null && onGameStateChanged != null) {
        onGameStateChanged!(Map<String, dynamic>.from(data));

        // Handle sounds
        if (data['last_sound'] != null) {
          final soundData = data['last_sound'];
          final int? soundTime = soundData['time'];
          if (soundData['sender'] != _myId && soundTime != null && soundTime != _lastProcessedSoundTime) {
            _lastProcessedSoundTime = soundTime;
            onSoundReceived?.call("${soundData['name']}.mp3");
          }
        }

        // NEW: Handle burn effects from opponent
        if (data['last_burn'] != null) {
          final burnData = data['last_burn'];
          if (burnData['sender'] != _myId) {
            onBurnEffectReceived?.call(burnData['card']);
          }
        }
      }
    });
  }

  Future<void> sendMove(int index, String card, int playerValue) async {
    if (_gameId == null) return;
    try {
      await _db.child('games/$_gameId').update({
        'board/$index': playerValue,
        'last_move': {'card': card, 'index': index, 'player': _playerRole},
        'turn': _playerRole == 'host' ? 'guest' : 'host',
      });
    } catch (e) {
      print("Move error: $e");
    }
  }

  // NEW: Notify opponent of a burned card
  Future<void> sendBurnAction(String card) async {
    if (_gameId == null) return;
    await _db.child('games/$_gameId/last_burn').set({
      'card': card,
      'sender': _myId,
      'time': ServerValue.timestamp,
    });
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

  Future<void> recordGameEnd({required bool won, required String opponentName}) async {
    final prefs = await SharedPreferences.getInstance();
    String? uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      DatabaseReference userRef = _db.child('users/$uid');
      final snapshot = await userRef.get();

      if (snapshot.exists) {
        Map<String, dynamic> data = Map<String, dynamic>.from(snapshot.value as Map);
        int currentCoins = data['coins'] ?? 0;
        int currentWins = data['matches_won'] ?? 0;
        int currentPlayed = data['matches_played'] ?? 0;

        int coinsEarned = won ? 100 : 20;
        int newCoins = currentCoins + coinsEarned;

        await userRef.update({
          'coins': newCoins,
          'matches_played': currentPlayed + 1,
          'matches_won': won ? currentWins + 1 : currentWins,
        });

        await userRef.child('match_history').push().set({
          'date': DateTime.now().toIso8601String(),
          'opponent': opponentName,
          'result': won ? "WIN" : "LOSS",
          'coins_earned': coinsEarned,
        });

        await prefs.setInt('user_coins', newCoins);
      }
    } catch (e) {
      print("Record game end error: $e");
    }
  }

  Future<void> sendChatMessage(String text) async {
    if (_gameId == null || text.trim().isEmpty) return;
    await _db.child('games/$_gameId/chats').push().set({
      'sender': _myId,
      'text': text,
      'timestamp': ServerValue.timestamp,
    });
  }

  // --- STORE & ECONOMY ---

  Future<bool> purchaseChip(String chipId, int cost) async {
    final prefs = await SharedPreferences.getInstance();
    String? uid = _auth.currentUser?.uid;
    if (uid == null) return false;

    try {
      DatabaseReference userRef = _db.child('users/$uid');
      final snapshot = await userRef.get();

      if (snapshot.exists) {
        Map<String, dynamic> data = Map<String, dynamic>.from(snapshot.value as Map);
        int currentCoins = data['coins'] ?? 0;
        List<String> owned = List<String>.from(data['owned_chips'] ?? []);

        if (currentCoins >= cost && !owned.contains(chipId)) {
          currentCoins -= cost;
          owned.add(chipId);

          await userRef.update({
            'coins': currentCoins,
            'owned_chips': owned,
          });

          await prefs.setInt('user_coins', currentCoins);
          return true;
        }
      }
    } catch (e) {
      print("Purchase chip error: $e");
    }
    return false;
  }

  Future<bool> purchaseItem(String itemId, String type, int costOrReward) async {
    final prefs = await SharedPreferences.getInstance();
    User? user = _auth.currentUser;
    if (user == null) return false;

    try {
      DatabaseReference userRef = _db.child('users/${user.uid}');
      final snapshot = await userRef.get();

      if (snapshot.exists) {
        Map<String, dynamic> data = Map<String, dynamic>.from(snapshot.value as Map);
        int currentCoins = data['coins'] ?? 0;
        int currentLives = data['lives'] ?? 0;

        if (type == 'coinPack') {
          currentCoins += costOrReward;
        } else if (type == 'lifeRefill') {
          if (itemId == 'lives_one' && currentCoins >= 200) {
            currentCoins -= 200;
            currentLives += 1;
          } else if (itemId == 'lives_full') {
            currentLives = 5;
          } else {
            return false;
          }
        }

        await userRef.update({'coins': currentCoins, 'lives': currentLives});
        await prefs.setInt('user_coins', currentCoins);
        return true;
      }
    } catch (e) {
      print("Item purchase error: $e");
    }
    return false;
  }

  // --- PRESENCE & CLEANUP ---

  void setupPresence() {
    final user = _auth.currentUser;
    if (user == null) return;

    final presenceRef = _db.child('presence/${user.uid}');
    final publicStatusRef = _db.child('public_profiles/${user.uid}/status');

    FirebaseDatabase.instance.ref('.info/connected').onValue.listen((event) {
      final connected = event.snapshot.value as bool? ?? false;
      if (connected) {
        presenceRef.set('online');
        publicStatusRef.set('online');

        presenceRef.onDisconnect().set('offline');
        publicStatusRef.onDisconnect().set('offline');
      }
    });
  }

  void leaveGame() {
    _gameSubscription?.cancel();
    _gameId = null;
    _playerRole = null;
  }

  Future<void> cancelSearch() async {
    _gameSubscription?.cancel();
    if (_gameId != null && _playerRole == 'host') {
      try {
        final snapshot = await _db.child('games/$_gameId/status').get();
        if (snapshot.value == 'waiting') {
          await _db.child('games/$_gameId').remove();
        }
      } catch (e) {
        print("Cancel error: $e");
      }
    }
    _gameId = null;
    _playerRole = null;
  }
}