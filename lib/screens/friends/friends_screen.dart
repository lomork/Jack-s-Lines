import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../database/online_service.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final OnlineService _onlineService = OnlineService();

  // Data Lists
  List<String> friendUids = [];
  Map<String, Map<String, dynamic>> friendProfiles = {};
  List<Map<String, dynamic>> _incomingFriendRequests = [];
  List<Map<String, dynamic>> _gameInvites = [];
  List<Map<String, dynamic>> _completedGames = [];
  bool _isLoadingHistory = false;

  // Search
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  // Listeners
  StreamSubscription? _friendsSubscription;
  StreamSubscription? _invitesSubscription;

  @override
  void initState() {
    super.initState();
    _setupListeners();
    _refreshHistory();
  }

  @override
  void dispose() {
    _friendsSubscription?.cancel();
    _invitesSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // --- 1. LISTENERS & DATA FETCHING ---
  void _setupListeners() {
    final user = _auth.currentUser;
    if (user == null) return;

    // Listen to Friends & Friend Requests
    _friendsSubscription = _db.child('users/${user.uid}/friends').onValue.listen((event) {
      if (event.snapshot.exists) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        List<String> active = [];
        List<Map<String, dynamic>> pending = [];

        data.forEach((key, value) {
          if (value['status'] == 'active') {
            active.add(key);
          } else if (value['status'] == 'pending') {
            pending.add({'uid': key});
          }
        });

        if (mounted) {
          setState(() => friendUids = active);
          _fetchFriendProfiles(active);
          _fetchPendingProfiles(pending);
        }
      } else {
        if (mounted) {
          setState(() {
            friendUids = [];
            _incomingFriendRequests = [];
          });
        }
      }
    });

    // Listen to Game Invites
    _invitesSubscription = _onlineService.getGameInvitesStream().listen((invites) {
      if (mounted) setState(() => _gameInvites = invites);
    });
  }

  Future<void> _fetchFriendProfiles(List<String> uids) async {
    for (String uid in uids) {
      if (friendProfiles.containsKey(uid)) continue;
      final snap = await _db.child('public_profiles/$uid').get();
      if (snap.exists) {
        if (mounted) {
          setState(() {
            friendProfiles[uid] = Map<String, dynamic>.from(snap.value as Map);
          });
        }
      }
    }
  }

  Future<void> _fetchPendingProfiles(List<Map<String, dynamic>> pending) async {
    List<Map<String, dynamic>> loaded = [];
    for (var p in pending) {
      final snap = await _db.child('public_profiles/${p['uid']}').get();
      if (snap.exists) {
        var data = Map<String, dynamic>.from(snap.value as Map);
        data['uid'] = p['uid'];
        loaded.add(data);
      }
    }
    if (mounted) setState(() => _incomingFriendRequests = loaded);
  }

  Future<void> _refreshHistory() async {
    setState(() => _isLoadingHistory = true);
    var history = await _onlineService.getCompletedGames();
    if (mounted) {
      setState(() {
        _completedGames = history;
        _isLoadingHistory = false;
      });
    }
  }

  // --- 2. ACTIONS ---

  Future<void> _sendFriendRequest(String targetUid) async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _db.child('users/$targetUid/friends/${user.uid}').set({
        'status': 'pending',
        'timestamp': ServerValue.timestamp,
      });
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Request Sent!")));
    } catch (e) {
      // Ignore
    }
  }

  Future<void> _acceptFriendRequest(String targetUid) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _db.child('users/${user.uid}/friends/$targetUid').update({'status': 'active'});
    await _db.child('users/$targetUid/friends/${user.uid}').update({'status': 'active'});
  }

  Future<void> _removeFriend(String targetUid) async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _db.child('users/${user.uid}/friends/$targetUid').remove();
      await _db.child('users/$targetUid/friends/${user.uid}').remove();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Friend removed.")));
    } catch (e) {
      // Ignore
    }
  }

  Future<void> _performSearch(String query) async {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return;
    setState(() => _isSearching = true);

    final results = await _onlineService.searchUsers(trimmed);
    if (mounted) {
      setState(() {
        _searchResults = results.where((u) => u['uid'] != _auth.currentUser?.uid).toList();
        _isSearching = false;
      });
    }
  }

  void _acceptGameInvite(Map<String, dynamic> invite) async {
    await _onlineService.acceptGameInvite(invite);
    if (!mounted) return;
    _showVersusDialog("You", invite['from_name'] ?? "Opponent");
  }

  // --- 3. UI BUILDERS (MODALS & TILES) ---

  void _showVersusDialog(String myName, String opponentName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.black87,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("MATCH ACCEPTED", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, letterSpacing: 2)),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(children: [
                      const CircleAvatar(radius: 30, backgroundColor: Colors.blue),
                      const SizedBox(height: 10),
                      Text(myName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ]),
                    const Text("VS", style: TextStyle(color: Colors.red, fontSize: 30, fontStyle: FontStyle.italic)),
                    Column(children: [
                      const CircleAvatar(radius: 30, backgroundColor: Colors.red),
                      const SizedBox(height: 10),
                      Text(opponentName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ]),
                  ],
                ),
                const SizedBox(height: 30),
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 10),
                const Text("Connecting...", style: TextStyle(color: Colors.white54)),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showUserProfile(Map<String, dynamic> profile) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildProfileModal(profile),
    );
  }

  Widget _buildProfileModal(Map<String, dynamic> profile) {
    String uid = profile['uid'] ?? "";
    String name = profile['username'] ?? "Player";
    String avatarPath = "assets/avatars/${profile['avatar'] ?? 'avatar_1'}.png";
    int wins = profile['matches_won'] ?? 0;
    int played = profile['matches_played'] ?? 0;
    int losses = played - wins;
    if (losses < 0) losses = 0;
    String chip = profile['selected_chip'] ?? "default_blue";
    String chipName = chip.replaceAll("default_", "").toUpperCase();
    bool isFriend = friendUids.contains(uid);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: Colors.orange, width: 2)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: Colors.grey[800],
                backgroundImage: AssetImage(avatarPath),
                onBackgroundImageError: (_, __) {},
              ),
              Positioned(
                right: 0, bottom: 0,
                child: StreamBuilder<DatabaseEvent>(
                  stream: _onlineService.getUserPresenceStream(uid),
                  builder: (context, snapshot) {
                    bool isOnline = snapshot.hasData && snapshot.data!.snapshot.value == 'online';
                    return Container(
                      width: 16, height: 16,
                      decoration: BoxDecoration(
                        color: isOnline ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(name, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatItem("Wins", "$wins", Colors.greenAccent),
              _buildStatItem("Losses", "$losses", Colors.redAccent),
              _buildStatItem("Chip", chipName, Colors.blueAccent),
            ],
          ),
          const SizedBox(height: 30),
          if (isFriend) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.gamepad),
                label: const Text("CHALLENGE TO 1v1"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _onlineService.sendGameInvite(uid, "My Name");
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invite Sent!")));
                },
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                icon: const Icon(Icons.person_remove, color: Colors.red),
                label: const Text("REMOVE FRIEND", style: TextStyle(color: Colors.red)),
                onPressed: () => _removeFriend(uid),
              ),
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.person_add),
                label: const Text("SEND FRIEND REQUEST"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _sendFriendRequest(uid);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );
  }

  Widget _buildExpansionTile({
    required String title,
    required IconData icon,
    required List<Widget> children,
    int? count,
    bool initiallyExpanded = false
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      child: Card(
        color: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: Colors.white.withOpacity(0.1))
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            leading: Icon(icon, color: Colors.orange),
            title: Row(
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                if (count != null && count > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: Text("$count", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ]
              ],
            ),
            iconColor: Colors.orange,
            collapsedIconColor: Colors.white54,
            childrenPadding: const EdgeInsets.fromLTRB(0, 0, 0, 10),
            children: children,
          ),
        ),
      ),
    );
  }

  // --- 4. MAIN BUILD ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, // Assumes a background is behind this
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("SOCIAL HUB", style: TextStyle(color: Colors.white)),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white54),
            onPressed: _refreshHistory,
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 10),
        children: [
          // 1. GAME INVITES
          if (_gameInvites.isNotEmpty)
            _buildExpansionTile(
              title: "GAME INVITES",
              icon: Icons.videogame_asset_outlined,
              count: _gameInvites.length,
              initiallyExpanded: true,
              children: _gameInvites.map((invite) {
                // Calculate Time Left
                int timestamp = invite['timestamp'] ?? 0;
                int now = DateTime.now().millisecondsSinceEpoch;
                int diffSeconds = (now - timestamp) ~/ 1000;
                int timeLeft = 120 - diffSeconds;

                if (timeLeft <= 0) {
                  _onlineService.rejectGameInvite(invite['key']);
                  return const SizedBox.shrink();
                }

                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.withOpacity(0.3))
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.sports_esports, color: Colors.orange),
                          const SizedBox(width: 10),
                          Expanded(child: Text("${invite['from_name']} challenges you!", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: timeLeft.toDouble(), end: 0),
                            duration: Duration(seconds: timeLeft),
                            builder: (context, value, child) => Text(
                                "${value.toInt()}s",
                                style: TextStyle(color: value < 30 ? Colors.red : Colors.greenAccent, fontWeight: FontWeight.bold)
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => _onlineService.rejectGameInvite(invite['key']),
                              child: const Text("DECLINE", style: TextStyle(color: Colors.redAccent)),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                              onPressed: () => _acceptGameInvite(invite),
                              child: const Text("ACCEPT"),
                            ),
                          ]
                      )
                    ],
                  ),
                );
              }).toList(),
            ),

          // 2. FRIEND REQUESTS
          if (_incomingFriendRequests.isNotEmpty)
            _buildExpansionTile(
              title: "FRIEND REQUESTS",
              icon: Icons.person_add_alt_1_outlined,
              count: _incomingFriendRequests.length,
              initiallyExpanded: true,
              children: _incomingFriendRequests.map((req) {
                return ListTile(
                  leading: CircleAvatar(backgroundImage: AssetImage("assets/avatars/${req['avatar'] ?? 'avatar_1'}.png")),
                  title: Text(req['username'] ?? "Unknown", style: const TextStyle(color: Colors.white)),
                  trailing: IconButton(
                    icon: const Icon(Icons.check_circle, color: Colors.green, size: 30),
                    onPressed: () => _acceptFriendRequest(req['uid']),
                  ),
                  onTap: () => _showUserProfile(req),
                );
              }).toList(),
            ),

          // 3. MY FRIENDS
          _buildExpansionTile(
            title: "MY FRIENDS",
            icon: Icons.people_alt_outlined,
            count: friendUids.length,
            children: [
              if (friendUids.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text("No friends yet. Try discovering some!", style: TextStyle(color: Colors.white54)),
                )
              else
                ...friendUids.map((uid) {
                  var profile = friendProfiles[uid] ?? {};
                  profile['uid'] = uid;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: AssetImage("assets/avatars/${profile['avatar'] ?? 'avatar_1'}.png"),
                    ),
                    title: Text(profile['username'] ?? "Loading...", style: const TextStyle(color: Colors.white)),
                    subtitle: StreamBuilder<DatabaseEvent>(
                      stream: _onlineService.getUserPresenceStream(uid),
                      builder: (context, snap) {
                        bool isOnline = snap.hasData && snap.data!.snapshot.value == 'online';
                        return Text(isOnline ? "Online" : "Offline", style: TextStyle(color: isOnline ? Colors.green : Colors.grey));
                      },
                    ),
                    onTap: () => _showUserProfile(profile),
                  );
                }).toList(),
            ],
          ),

          // 4. DISCOVER
          _buildExpansionTile(
            title: "DISCOVER PLAYERS",
            icon: Icons.search_outlined,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Search Username...",
                    hintStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Colors.white10,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search, color: Colors.orange),
                      onPressed: () => _performSearch(_searchController.text),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  onSubmitted: _performSearch,
                ),
              ),
              if (_isSearching)
                const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Colors.orange))
              else if (_searchResults.isNotEmpty)
                ..._searchResults.map((user) {
                  return ListTile(
                    leading: CircleAvatar(backgroundImage: AssetImage("assets/avatars/${user['avatar'] ?? 'avatar_1'}.png")),
                    title: Text(user['username'] ?? "Unknown", style: const TextStyle(color: Colors.white)),
                    trailing: IconButton(
                      icon: const Icon(Icons.person_add, color: Colors.orange),
                      onPressed: () => _sendFriendRequest(user['uid']),
                    ),
                    onTap: () => _showUserProfile(user),
                  );
                }).toList()
              else if (_searchController.text.isNotEmpty)
                  const Padding(padding: EdgeInsets.all(16.0), child: Text("No players found.", style: TextStyle(color: Colors.white54))),
            ],
          ),

          // 5. GAME HISTORY
          _buildExpansionTile(
            title: "GAME HISTORY",
            icon: Icons.history_outlined,
            children: [
              if (_isLoadingHistory)
                const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Colors.orange))
              else if (_completedGames.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text("No completed games yet.", style: TextStyle(color: Colors.white54)),
                )
              else
                ..._completedGames.map((game) {
                  final myUid = _auth.currentUser?.uid;
                  String result = "DRAW";
                  Color color = Colors.grey;
                  if (game['winner_id'] == myUid) {
                    result = "VICTORY";
                    color = Colors.green;
                  } else if (game['winner_id'] != null) {
                    result = "DEFEAT";
                    color = Colors.red;
                  }
                  String opponent = (game['host_id'] == myUid)
                      ? (game['guest_name'] ?? "Guest")
                      : (game['host_name'] ?? "Host");
                  return ListTile(
                    leading: Icon(Icons.circle, color: color, size: 16),
                    title: Text("vs $opponent", style: const TextStyle(color: Colors.white)),
                    subtitle: Text(result, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                    trailing: Text(
                      DateTime.fromMillisecondsSinceEpoch(game['match_start_time'] ?? 0).toString().split(' ')[0],
                      style: const TextStyle(color: Colors.white24, fontSize: 12),
                    ),
                  );
                }).toList(),
            ],
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}