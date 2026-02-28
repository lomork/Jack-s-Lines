import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/game/play_online.dart';
import '../screens/game/game_board.dart';


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
  Function(String)? onBurnEffectReceived;

  VoidCallback? onMatchFound;

  String? get currentGameId => _gameId;
  String get myRole => _playerRole ?? "spectator";

  // --- Match Reconnection ---

  Future<void> _saveCurrentGameSession(String gameId, String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_game_id', gameId);
    await prefs.setString('last_player_role', role);
  }

  Future<void> _clearGameSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_game_id');
    await prefs.remove('last_player_role');
  }

  /// Attempts to rejoin an active game if the app crashed or disconnected
  Future<bool> tryReconnect() async {
    final prefs = await SharedPreferences.getInstance();
    final lastGameId = prefs.getString('last_game_id');
    final lastRole = prefs.getString('last_player_role');

    if (lastGameId == null || lastRole == null) return false;

    try {
      final snapshot = await _db.child('games/$lastGameId').get();
      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        // Only reconnect if the game is still active
        if (data['status'] == 'playing' || data['status'] == 'waiting') {
          _gameId = lastGameId;
          _playerRole = lastRole;
          _myId = _auth.currentUser?.uid;
          _listenToGame();
          return true;
        }
      }
    } catch (e) {
      print("Reconnection failed: $e");
    }
    await _clearGameSession();
    return false;
  }

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
          'avatars': avatar,
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
        final Object? value = snapshot.value;
        if (value is! Map) return [];

        final data = Map<dynamic, dynamic>.from(value);
        return data.entries.map((e) {
          final val = Map<String, dynamic>.from(e.value as Map);
          val['uid'] = e.key.toString();
          return val;
        }).toList();
      }
    } catch (e) {
      print("CRITICAL: Search failed. Error: $e");
    }
    return [];
  }

  Future<String?> sendGameInvite(String friendUid, String myName) async {
    if (_myId == null) return null;

    // 1. Create a private game lobby
    String gameId = _db.child('games').push().key!;

    // 2. Setup the game entry
    await _db.child('games/$gameId').set({
      'status': 'waiting',
      'host_id': _myId,
      'host_name': myName,
      'created_at': ServerValue.timestamp,
      'is_private': true,
      'invited_player': friendUid,
    });

    // 3. Send a notification to the friend
    await _db.child('notifications/$friendUid').push().set({
      'type': 'game_invite',
      'from_uid': _myId,
      'from_name': myName,
      'game_id': gameId,
      'timestamp': ServerValue.timestamp,
    });

    // 4. Join yourself and wait
    _gameId = gameId;
    _playerRole = "host";
    _listenToGame();

    return gameId;
  }

  Future<void> cancelGameInvite(String gameId, String friendUid) async {
    // 1. Remove the Game Lobby
    await _db.child('games/$gameId').remove();

    // 2. Clean up the notification (Optional but cleaner)
    // We query notifications for this user that match the gameId
    final notifRef = _db.child('notifications/$friendUid');
    final snapshot = await notifRef.orderByChild('game_id').equalTo(gameId).get();

    if (snapshot.exists) {
      for (var child in snapshot.children) {
        await child.ref.remove();
      }
    }

    _gameSubscription?.cancel();
    _gameId = null;
    _playerRole = null;
  }

  // --- NEW: Fetch Realtime Presence ---
  Stream<DatabaseEvent> getUserPresenceStream(String uid) {
    return _db.child('presence/$uid').onValue;
  }

  Stream<List<Map<String, dynamic>>> getGameInvitesStream() {
    // FIX: Get current UID directly
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();
    final myUid = user.uid;

    // Listen to notifications node for type 'game_invite'
    return _db.child('notifications/$myUid').onValue.map((event) {
      final List<Map<String, dynamic>> invites = [];
      if (event.snapshot.exists && event.snapshot.value is Map) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        data.forEach((key, value) {
          final val = Map<String, dynamic>.from(value);
          if (val['type'] == 'game_invite') {
            val['key'] = key; // Store the notification ID so we can delete it
            invites.add(val);
          }
        });
      }
      // Sort by newest first
      invites.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
      return invites;
    });
  }

  Future<void> acceptGameInvite(Map<String, dynamic> invite) async {
    final String gameId = invite['game_id'];
    final String notifKey = invite['key'];

    // Join the game
    await _db.child('games/$gameId').update({
      'status': 'playing',
      'guest_id': _myId,
      'guest_name': await getMyHandle(), // Helper method (see below)
      'guest_avatar': await _getMyAvatar(),
      'match_start_time': ServerValue.timestamp,
    });

    // Delete the invitation notification
    await _db.child('notifications/$_myId/$notifKey').remove();

    // Notify the host that we accepted (This triggers their "Come Back" notification)
    await _db.child('notifications/${invite['from_uid']}').push().set({
      'type': 'game_accept',
      'from_uid': _myId,
      'from_name': await getMyHandle(),
      'game_id': gameId,
      'timestamp': ServerValue.timestamp,
    });

    // Set local state
    _gameId = gameId;
    _playerRole = 'guest';
    _listenToGame();
  }

  Future<void> rejectGameInvite(String notifKey) async {
    if (_myId != null) {
      await _db.child('notifications/$_myId/$notifKey').remove();
    }
  }

  Future<List<Map<String, dynamic>>> getCompletedGames() async {
    if (_myId == null) return [];

    // fetch all games (Optimization: Create a specific 'user_games/$uid' node in the future)
    final snapshot = await _db.child('games').orderByChild('status').equalTo('finished').get();

    List<Map<String, dynamic>> myGames = [];
    if (snapshot.exists) {
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      data.forEach((key, value) {
        final g = Map<String, dynamic>.from(value);
        // Check if I was a player
        if (g['host_id'] == _myId || g['guest_id'] == _myId) {
          g['id'] = key;
          myGames.add(g);
        }
      });
    }
    // Sort by newest
    myGames.sort((a, b) => (b['match_start_time'] ?? 0).compareTo(a['match_start_time'] ?? 0));
    return myGames;
  }

  Future<String> getMyHandle() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('unique_handle') ?? "Player";
  }

  Future<String> _getMyAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('selected_avatar_id') ?? "avatar_1";
  }

  Future<void> saveUserProfile(Map<String, dynamic> data) async {
    User? user = _auth.currentUser;
    if (user == null) return;
    try {
      await _db.child('users/${user.uid}').update(data);
      if (data.containsKey('username')) {
        await updateProfile(
            username: data['username'],
            avatar: data['avatars'] ?? "avatar_1"
        );
      }
    } catch (e) {
      print("Save profile error: $e");
    }
  }

  Future<void> sendHover(int? index) async {
    if (_gameId == null) return;
    await _db.child('games/$_gameId/hovers/$_playerRole').set(index);
  }

  Future<void> fillWithBots(int targetPlayers) async {
    final personalities = ['aggressive', 'builder', 'balanced'];
    final random = Random();

    //if (_gameId == null) return;
    for (int i = 0; i < targetPlayers; i++) {
      String slot = "player_$i";
      final snap = await _db.child('games/$_gameId/players/$slot').get();
      if (!snap.exists) {
        await _db.child('games/$_gameId/players/$slot').set({
          'id': 'bot_$i',
          'name': "CPU ${i + 1}",
          'avatars': "avatar_3",
          'personality': personalities[random.nextInt(personalities.length)],
          'is_bot': true,
        });
      }
    }
    await _db.child('games/$_gameId').update({'status': 'playing'});
  }

  void setupDisconnectListener() {
    if (_gameId == null || _playerRole == null) return;
    _db.child('games/$_gameId/players/$_playerRole/status').onDisconnect().set('offline');
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

  // 1. Send a Friend Request (Outgoing)
  Future<void> sendFriendRequest(String targetUid) async {
    final user = _auth.currentUser;
    if (user == null) {
      print("ERROR: Cannot send request. User not logged in.");
      return;
    }
    final myUid = user.uid;

    // Write to my 'sent' list
    await _db.child('users/$myUid/friend_requests_sent/$targetUid').set(ServerValue.timestamp);

    // Write to target's 'received' list
    await _db.child('users/$targetUid/friend_requests_received/$myUid').set(ServerValue.timestamp);

    print("DEBUG: Request sent from $myUid to $targetUid");
  }

  // 2. Cancel a Friend Request (Outgoing)
  Future<void> cancelFriendRequest(String targetUid) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final myUid = user.uid;

    await _db.child('users/$myUid/friend_requests_sent/$targetUid').remove();
    await _db.child('users/$targetUid/friend_requests_received/$myUid').remove();
  }

  // 3. Accept a Friend Request (Incoming)
  Future<void> acceptFriendRequest(String requesterUid) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final myUid = user.uid;

    // Add to both friends lists
    await _db.child('users/$myUid/friends/$requesterUid').set({'status': 'active'});
    await _db.child('users/$requesterUid/friends/$myUid').set({'status': 'active'});

    // Remove the requests
    await _db.child('users/$myUid/friend_requests_received/$requesterUid').remove();
    await _db.child('users/$requesterUid/friend_requests_sent/$myUid').remove();
  }

  // 4. Reject/Delete a Friend Request
  Future<void> rejectFriendRequest(String requesterUid) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final myUid = user.uid;

    await _db.child('users/$myUid/friend_requests_received/$requesterUid').remove();
    await _db.child('users/$requesterUid/friend_requests_sent/$myUid').remove();
  }

  // 5. Remove a Friend
  Future<void> removeFriend(String friendUid) async {
    // FIX: Get current UID directly from Auth to ensure it is not null
    final user = _auth.currentUser;
    if (user == null) return;
    final myUid = user.uid;

    try {
      // Remove from my list
      await _db.child('users/$myUid/friends/$friendUid').remove();
      // Remove from their list
      await _db.child('users/$friendUid/friends/$myUid').remove();
    } catch (e) {
      print("Error removing friend: $e");
    }
  }

  // 6. Streams for the Lists
  Stream<DatabaseEvent> getIncomingRequestsStream() {
    final user = _auth.currentUser;
    if (user == null) {
      print("DEBUG: User is null. Cannot listen to incoming requests.");
      return const Stream.empty();
    }
    print("DEBUG: Listening for requests at 'users/${user.uid}/friend_requests_received'");
    return _db.child('users/${user.uid}/friend_requests_received').onValue;
  }

  Stream<DatabaseEvent> getOutgoingRequestsStream() {
    final user = _auth.currentUser;
    if (user == null) {
      print("DEBUG: User is null. Cannot listen to outgoing requests.");
      return const Stream.empty();
    }
    print("DEBUG: Listening for sent requests at 'users/${user.uid}/friend_requests_sent'");
    return _db.child('users/${user.uid}/friend_requests_sent').onValue;
  }

  // UPDATED: Get Public Data + Stats (for the Modal)
  Future<Map<String, dynamic>?> getFriendStats(String uid) async {
    try {
      // Try fetching from public profile first
      final publicSnap = await _db.child('public_profiles/$uid').get();
      Map<String, dynamic> data = {};

      if (publicSnap.exists) {
        data.addAll(Map<String, dynamic>.from(publicSnap.value as Map));
      }

      // Try fetching stats from the user node (if rules allow, or if we sync them)
      // Note: In a real app, you should sync 'wins' to public_profiles in recordGameEnd.
      // For now, we try to read the user node directly.
      final userSnap = await _db.child('users/$uid').get();
      if (userSnap.exists) {
        final userData = Map<String, dynamic>.from(userSnap.value as Map);
        data['matches_won'] = userData['matches_won'] ?? 0;
        data['matches_played'] = userData['matches_played'] ?? 0;
        data['selected_chip'] = userData['selected_chip_id'] ?? "default_chip";
      }
      return data;
    } catch (e) {
      print("Error fetching stats: $e");
      return null;
    }
  }

  // --- MATCHMAKING & GAMEPLAY ---

  Future<List<Map<String, dynamic>>> getUserMatchHistory() async {
    final user = _auth.currentUser;
    if (user == null) return [];

    try {
      // Limit to last 20 to save bandwidth
      final snapshot = await _db.child('users/${user.uid}/match_history') // Check specific path used in game_board
          .orderByKey()
          .limitToLast(20)
          .get();

      // NOTE: In game_board.dart you save to 'users/$uid/matches',
      // but in some previous code it might have been 'match_history'.
      // I will assume 'matches' based on your previous 'game_board.dart' upload.
      // If it returns empty, check the path in game_board.dart.

      final matchSnap = await _db.child('users/${user.uid}/matches').limitToLast(20).get();

      if (matchSnap.exists && matchSnap.value is Map) {
        Map<dynamic, dynamic> map = matchSnap.value as Map;
        List<Map<String, dynamic>> history = [];

        map.forEach((key, value) {
          final data = Map<String, dynamic>.from(value);
          data['id'] = key;
          history.add(data);
        });

        // Sort by timestamp descending (newest first)
        history.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
        return history;
      }
    } catch (e) {
      print("Error fetching history: $e");
    }
    return [];
  }

  Future<void> findMatch({String? chipId}) async {
    await findMultiplayerMatch(targetPlayers: 2, isTeam: false, chipId: chipId);
  }

  void _listenToGame() {
    if (_gameId == null) return;
    _gameSubscription = _db.child('games/$_gameId').onValue.listen((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data != null && onGameStateChanged != null) {
        if (data['status'] == 'playing') {
          _db.child('games/$_gameId').onDisconnect().cancel();
          _db.child('games/$_gameId/players/$_playerRole').onDisconnect().cancel();

          _db.child('games/$_gameId/players/$_playerRole/status').onDisconnect().set('offline');
        }
        onGameStateChanged!(Map<String, dynamic>.from(data));

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
    if (_gameId == null || _playerRole == null) return;

    final gameRef = _db.child('games/$_gameId');

    await gameRef.runTransaction((Object? game) {
      if (game == null) return Transaction.abort();
      Map<String, dynamic> g = Map<String, dynamic>.from(game as Map);

      if (g['turn'] != _playerRole || g['status'] != 'playing') {
        return Transaction.abort();
      }

      // Apply the move
      List<dynamic> board = List.from(g['board']);
      board[index] = playerValue;
      g['board'] = board;
      g['last_move'] = {'card': card, 'index': index, 'player': _playerRole};
      g['turn'] = (_playerRole == 'host') ? 'guest' : 'host';

      return Transaction.success(g);
    });
  }

  Future<void> sendBurnAction(String card) async {
    if (_gameId == null) return;
    await _db.child('games/$_gameId/last_burn').set({
      'card': card,
      'sender': _myId,
      'time': ServerValue.timestamp,
    });
  }

  Future<void> sendSound(String fileName) async {
    if (currentGameId == null) return;
    // We send a timestamp so the listener fires even if the same sound is played twice in a row
    await _db.child('games').child(currentGameId!).update({
      'sfx_event': {
        'file': fileName,
        'timestamp': ServerValue.timestamp,
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
    _myId = user.uid; // Ensure local ID is set

    final presenceRef = _db.child('presence/${user.uid}');
    final connectedRef = _db.child('.info/connected');

    connectedRef.onValue.listen((event) {
      final connected = event.snapshot.value as bool? ?? false;
      if (connected) {
        // Write simple string 'online' for easy checking
        presenceRef.set('online');
        presenceRef.onDisconnect().remove(); // Disappear when app closes
      }
    });
  }

  Future<void> leaveGame() async {
    await _clearGameSession();
    if (_gameId != null && _playerRole != null) {
      // Explicitly set offline if leaving normally
      await _db.child('games/$_gameId/players/$_playerRole/status').set('offline');
    }
    _gameSubscription?.cancel();
    _gameId = null;
    _playerRole = null;
  }

  Future<void> cancelSearch() async {
    _gameSubscription?.cancel();

    // UPDATED FIX: Properly check if we are the host (player_0) or a guest
    if (_gameId != null) {
      if (_playerRole == 'player_0' || _playerRole == 'host') {
        try {
          final snapshot = await _db.child('games/$_gameId/status').get();
          if (snapshot.value == 'waiting') {
            await _db.child('games/$_gameId').remove(); // Host cancels = delete lobby
          }
        } catch (e) {
          print("Cancel error: $e");
        }
      } else if (_playerRole != null) {
        // If I am a guest (player_1, etc) in a waiting lobby, just remove myself
        try {
          final snapshot = await _db.child('games/$_gameId/status').get();
          if (snapshot.value == 'waiting') {
            await _db.child('games/$_gameId/players/$_playerRole').remove();
          }
        } catch (e) { print("Guest cancel error: $e"); }
      }
    }
    _gameId = null;
    _playerRole = null;
  }

  Future<void> findMultiplayerMatch({required int targetPlayers, required bool isTeam, String? chipId}) async {
    final prefs = await SharedPreferences.getInstance();
    _myId = _auth.currentUser?.uid;
    String myName = prefs.getString('unique_handle') ?? "Player";
    String myAvatar = prefs.getString('selected_avatar_id') ?? "avatar_1";

    final String modeKey = "${targetPlayers}_players_${isTeam ? "team" : "solo"}";
    final now = DateTime.now().millisecondsSinceEpoch;
    final twoMinutesAgo = now - (2 * 60 * 1000);

    final snapshot = await _db.child('games')
        .orderByChild('config')
        .equalTo(modeKey)
        .get();

    if (snapshot.exists) {
      final gamesMap = Map<dynamic, dynamic>.from(snapshot.value as Map);

      // FIX 2: Sort games so everyone tries the oldest lobby first (minimizes split lobbies)
      var sortedKeys = gamesMap.keys.toList();
      sortedKeys.sort((a, b) {
        int timeA = gamesMap[a]['created_at'] ?? 0;
        int timeB = gamesMap[b]['created_at'] ?? 0;
        return timeA.compareTo(timeB); // Oldest first
      });

      for (var id in sortedKeys) {
        final g = gamesMap[id];
        final createdAt = g['created_at'] ?? 0;

        if (g['status'] == 'waiting' && createdAt < twoMinutesAgo) {
          _db.child('games/$id').remove();
          continue;
        }

        if (g['status'] == 'waiting') {

          final result = await _db.child('games/$id').runTransaction((Object? game) {
            if (game == null) return Transaction.abort();
            Map<String, dynamic> gData = Map<String, dynamic>.from(game as Map);

            Map players = gData['players'] ?? {};

            // FIX 1: Transaction Logic Update: Am I already in this lobby?
            // If yes, abort to prevent "Self-Matching" (Ghost Game)
            bool alreadyIn = false;
            players.forEach((k, v) {
              if (v['id'] == _myId) alreadyIn = true;
            });
            if (alreadyIn) return Transaction.abort();

            // Check if lobby is full
            if (players.length >= targetPlayers || gData['status'] != 'waiting') {
              return Transaction.abort();
            }

            int slotIndex = players.length;
            String role = "player_$slotIndex";
            players[role] = {
              'id': _myId,
              'name': myName,
              'avatars': myAvatar,
              'chip_id': chipId ?? "default_blue",
              'status': 'online',
            };

            gData['players'] = players;
            if (players.length == targetPlayers) {
              gData['status'] = 'playing';
            }

            return Transaction.success(gData);
          });

          if (result.committed) {
            _gameId = id;
            final updatedPlayers = (result.snapshot.value as Map)['players'] as Map;
            _playerRole = updatedPlayers.entries.firstWhere((e) => e.value['id'] == _myId).key;

            await _saveCurrentGameSession(_gameId!, _playerRole!);
            _listenToGame();
            return;
          }
        }
      }
    }

    // Create new multiplayer lobby if none found
    _gameId = _db.child('games').push().key;
    _playerRole = "player_0";

    await _db.child('games/$_gameId').set({
      'status': 'waiting',
      'created_at': ServerValue.timestamp,
      'config': modeKey,
      'player_count': targetPlayers,
      'is_team': isTeam,
      'turn_index': 0,
      'board': List.filled(100, 0),
      'players': {
        'player_0': {
          'id': _myId,
          'name': myName,
          'avatars': myAvatar,
          'chip_id': chipId ?? "default_red",
          'status': 'online',
        }
      }
    });

    _db.child('games/$_gameId').onDisconnect().remove();

    await _saveCurrentGameSession(_gameId!, _playerRole!);
    _listenToGame();
  }

  Future<void> sendMultiplayerMove(int index, String card, int playerValue, int nextTurn) async {
    if (_gameId == null || _playerRole == null) return;

    final gameRef = _db.child('games/$_gameId');
    int mySlotIndex = int.parse(_playerRole!.split('_').last);

    await gameRef.runTransaction((Object? game) {
      if (game == null) return Transaction.abort();
      Map<String, dynamic> g = Map<String, dynamic>.from(game as Map);

      // VALIDATION: Check the current turn_index against our slot
      if (g['turn_index'] != mySlotIndex || g['status'] != 'playing') {
        return Transaction.abort();
      }

      List<dynamic> board = List.from(g['board']);
      board[index] = playerValue;
      g['board'] = board;
      g['last_move'] = {'card': card, 'index': index, 'player': _playerRole};
      g['turn_index'] = nextTurn;

      return Transaction.success(g);
    });
  }

}