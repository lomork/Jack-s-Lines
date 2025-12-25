import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../screens/store/data/chip_data.dart';
import '../account/data/avatar_data.dart';
import '../../notifications/notification_manager.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final NotificationManager _notifManager = NotificationManager();

  List<String> friendUids = [];
  Map<String, Map<String, dynamic>> friendProfiles = {};

  // Requests state
  List<Map<String, dynamic>> _incomingRequests = [];
  List<Map<String, dynamic>> _outgoingRequests = [];

  TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _recentOpponents = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this); // --- UPDATED: 3 Tabs ---
    _notifManager.init();
    _notifManager.onNotificationUpdate = () {
      if (mounted) setState(() {});
    };
    _listenToFriends();
    _fetchRecentOpponents();
    _listenToRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _listenToRequests() {
    final user = _auth.currentUser;
    if (user == null) return;

    // Listen for requests status in your own friends node
    _db.child('users/${user.uid}/friends').onValue.listen((event) {
      if (!mounted) return;
      List<Map<String, dynamic>> incoming = [];
      List<Map<String, dynamic>> outgoing = [];

      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map;
        data.forEach((uid, details) {
          if (details is Map) {
            if (details['status'] == 'pending') incoming.add({'uid': uid, ...details});
            if (details['status'] == 'requested') outgoing.add({'uid': uid, ...details});
          }
        });
      }
      setState(() {
        _incomingRequests = incoming;
        _outgoingRequests = outgoing;
      });
    });
  }

  void _listenToFriends() {
    final User? user = _auth.currentUser;
    if (user == null) return;

    _db.child('users/${user.uid}/friends').onValue.listen((event) {
      if (event.snapshot.exists) {
        final data = event.snapshot.value;
        List<String> newUids = [];

        if (data is Map) {
          data.forEach((key, value) {
            if (value is Map && value['status'] == 'active') {
              newUids.add(key.toString());
            } else if (value == true) {
              newUids.add(key.toString());
            }
          });
        }

        if (mounted) {
          setState(() => friendUids = newUids);
          _fetchFriendProfiles();
        }
      } else {
        if(mounted) setState(() => friendUids = []);
      }
    });
  }

  Future<void> _fetchFriendProfiles() async {
    for (String uid in friendUids) {
      final snapshot = await _db.child('users/$uid').get();
      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        if (mounted) setState(() => friendProfiles[uid] = data);
      }
    }
  }

  Future<void> _fetchRecentOpponents() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final snapshot = await _db.child('users/${user.uid}/matches').limitToLast(15).get();
      if (snapshot.exists) {
        final data = snapshot.value as Map;
        Map<String, Map<String, dynamic>> uniqueOpponents = {}; // --- deduplication ---

        data.forEach((key, value) {
          if (value['opponent_id'] != null) {
            uniqueOpponents[value['opponent_id']] = {
              'uid': value['opponent_id'],
              'handle': value['opponent_name'] ?? "Unknown",
              'avatar_id': value['opponent_avatar'] ?? "avatar_1",
            };
          }
        });

        if (mounted) {
          setState(() => _recentOpponents = uniqueOpponents.values.toList().reversed.toList());
        }
      }
    } catch (e) {
      debugPrint("Recent Opponents Error: $e");
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    if (query.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Query too short")));
      return;
    }

    setState(() { _isSearching = true; _searchResults = []; });

    try {
      final snapshot = await _db.child('users')
          .orderByChild('handle')
          .startAt(query)
          .endAt("$query\uf8ff")
          .limitToFirst(15)
          .get();

      List<Map<String, dynamic>> results = [];
      if (snapshot.exists) {
        final data = snapshot.value as Map;
        data.forEach((key, value) {
          if (key != _auth.currentUser?.uid) {
            var userMap = Map<String, dynamic>.from(value);
            userMap['uid'] = key;
            results.add(userMap);
          }
        });
      }

      if (mounted) setState(() => _searchResults = results);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Search failed."), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _addFriend(String targetUid) async {
    final User? user = _auth.currentUser;
    if (user == null) return;

    try {
      String myName = "Player"; // Fetch your real handle from a local var or pref
      final mySnap = await _db.child('users/${user.uid}/handle').get();
      if (mySnap.exists) myName = mySnap.value.toString();

      await _db.child('users/${user.uid}/friends/$targetUid').set({
        'added_at': ServerValue.timestamp,
        'status': 'requested' // Outgoing
      });

      await _db.child('users/$targetUid/friends/${user.uid}').set({
        'added_at': ServerValue.timestamp,
        'status': 'pending' // Incoming for them
      });

      // Send actual Notification
      await _notifManager.sendFriendRequest(targetUid, myName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Friend Request Sent!"), backgroundColor: Colors.blueAccent));
        setState(() => _searchResults = []);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Add failed."), backgroundColor: Colors.redAccent));
    }
  }

  Future<void> _acceptFriend(String targetUid) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _db.child('users/${user.uid}/friends/$targetUid/status').set('active');
    await _db.child('users/$targetUid/friends/${user.uid}/status').set('active');

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Friendship Accepted!"), backgroundColor: Colors.green));
  }

  Future<void> _removeFriend(String uid) async {
    final User? user = _auth.currentUser;
    if (user == null) return;

    await _db.child('users/${user.uid}/friends/$uid').remove();
    await _db.child('users/$uid/friends/${user.uid}').remove();
    if (mounted) {
      setState(() {
        friendUids.remove(uid);
        friendProfiles.remove(uid);
      });
      Navigator.pop(context);
    }
  }

  void _showFriendProfile(Map<String, dynamic> data, String uid, bool isFriend) {
    String avatarId = data['selected_avatar_id'] ?? data['avatar_id'] ?? "avatar_1";
    AvatarItem avatar = getAvatarById(avatarId);

    String chipId = data['selected_chip_id'] ?? "default_blue";
    GameChip chip = allGameChips.firstWhere((c) => c.id == chipId, orElse: () => allGameChips[0]);

    // CALCULATE ACTUAL INFO
    int wins = data['total_wins'] ?? 0;
    int losses = data['total_losses'] ?? 0;
    int streak = data['current_streak'] ?? 0;
    int level = (data['xp'] ?? 0) ~/ 100 + 1;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
            side: const BorderSide(color: Colors.white10)
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(radius: 45, backgroundColor: avatar.color, child: Icon(avatar.icon, size: 45, color: Colors.white)),
            const SizedBox(height: 15),
            Text(data['handle'] ?? "Player", style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            Text("LEVEL $level", style: const TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.w900)),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatColumn("Wins", "$wins", Colors.greenAccent),
                _buildStatColumn("Losses", "$losses", Colors.redAccent),
                _buildStatColumn("Streak", "$streak", Colors.orangeAccent),
              ],
            ),
            const SizedBox(height: 25),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(15)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Equipped: ", style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Icon(chip.icon, color: chip.color, size: 18),
                  const SizedBox(width: 8),
                  Text(chip.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
            ),

            const SizedBox(height: 25),

            if (isFriend)
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  color: Colors.redAccent.withOpacity(0.1),
                  onPressed: () => _removeFriend(uid),
                  child: const Text("UNFRIEND", style: TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  color: Colors.blueAccent,
                  onPressed: () {
                    _addFriend(uid);
                    Navigator.pop(context);
                  },
                  child: const Text("ADD FRIEND", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
        Text(label.toUpperCase(), style: const TextStyle(color: Colors.grey, fontSize: 9, letterSpacing: 1.0)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text("FRIENDS", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 3)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.blueAccent,
          indicatorWeight: 3,
          labelColor: Colors.blueAccent,
          unselectedLabelColor: Colors.white24,
          tabs: [
            const Tab(text: "MY LIST"),
            Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text("REQUESTS"),
              if (_incomingRequests.isNotEmpty) Container(margin: const EdgeInsets.only(left: 5), padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle), child: Text("${_incomingRequests.length}", style: const TextStyle(fontSize: 8, color: Colors.white)))
            ])),
            const Tab(text: "DISCOVER"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMyFriendsTab(),
          _buildRequestsTab(),
          _buildDiscoverTab(),
        ],
      ),
    );
  }

  Widget _buildMyFriendsTab() {
    if (friendUids.isEmpty) {
      return const Center(child: Text("Your friends list is empty.", style: TextStyle(color: Colors.white24)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: friendUids.length,
      itemBuilder: (context, index) {
        String uid = friendUids[index];
        Map<String, dynamic>? profile = friendProfiles[uid];
        if (profile == null) return const SizedBox();

        String avatarId = profile['selected_avatar_id'] ?? profile['avatar_id'] ?? "avatar_1";
        AvatarItem avatar = getAvatarById(avatarId);

        return Card(
          color: Colors.white.withOpacity(0.04),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(backgroundColor: avatar.color, child: Icon(avatar.icon, color: Colors.white, size: 20)),
            title: Text(profile['handle'] ?? "Player", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Text("Level ${(profile['xp'] ?? 0) ~/ 100 + 1}", style: const TextStyle(color: Colors.white38, fontSize: 11)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white12),
            onTap: () => _showFriendProfile(profile, uid, true),
          ),
        );
      },
    );
  }

  Widget _buildRequestsTab() {
    if (_incomingRequests.isEmpty && _outgoingRequests.isEmpty) {
      return const Center(child: Text("No pending requests.", style: TextStyle(color: Colors.white24)));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_incomingRequests.isNotEmpty) ...[
          const Text("INCOMING", style: TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          const SizedBox(height: 10),
          ..._incomingRequests.map((req) => _buildRequestTile(req, true)),
          const SizedBox(height: 20),
        ],
        if (_outgoingRequests.isNotEmpty) ...[
          const Text("OUTGOING", style: TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          const SizedBox(height: 10),
          ..._outgoingRequests.map((req) => _buildRequestTile(req, false)),
        ],
      ],
    );
  }

  Widget _buildRequestTile(Map<String, dynamic> req, bool isIncoming) {
    return FutureBuilder(
        future: _db.child('users/${req['uid']}').get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox();
          final profile = Map<String, dynamic>.from(snapshot.data!.value as Map);
          final avatar = getAvatarById(profile['selected_avatar_id'] ?? profile['avatar_id']);

          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(backgroundColor: avatar.color, child: Icon(avatar.icon, color: Colors.white, size: 16)),
            title: Text(profile['handle'] ?? "Player", style: const TextStyle(color: Colors.white, fontSize: 14)),
            trailing: isIncoming
                ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.check_circle, color: Colors.greenAccent), onPressed: () => _acceptFriend(req['uid'])),
                IconButton(icon: const Icon(Icons.cancel, color: Colors.redAccent), onPressed: () => _removeFriend(req['uid'])),
              ],
            )
                : const Text("PENDING", style: TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold)),
          );
        }
    );
  }

  Widget _buildDiscoverTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            cursorColor: Colors.blueAccent,
            decoration: InputDecoration(
              hintText: "Search handle...",
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
              prefixIcon: const Icon(Icons.search, color: Colors.white24),
              fillColor: Colors.white.withOpacity(0.05),
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              suffixIcon: IconButton(
                  icon: const Icon(Icons.send_rounded, color: Colors.blueAccent),
                  onPressed: () => _performSearch(_searchController.text)
              ),
            ),
            onSubmitted: _performSearch,
          ),
          const SizedBox(height: 30),

          if (_isSearching) const Center(child: CircularProgressIndicator(color: Colors.blueAccent)),

          Expanded(
            child: ListView(
              children: [
                if (!_isSearching && _searchResults.isNotEmpty) ...[
                  const Text("SEARCH RESULTS", style: TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  const SizedBox(height: 10),
                  ..._searchResults.map((user) => _buildUserListTile(user)),
                ],

                if (!_isSearching && _searchResults.isEmpty && _recentOpponents.isNotEmpty) ...[
                  const Text("RECENT OPPONENTS", style: TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  const SizedBox(height: 10),
                  ..._recentOpponents.map((user) => _buildUserListTile(user)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserListTile(Map<String, dynamic> user) {
    bool isAlreadyFriend = friendUids.contains(user['uid']);
    bool isPending = _incomingRequests.any((r) => r['uid'] == user['uid']) || _outgoingRequests.any((r) => r['uid'] == user['uid']);
    AvatarItem avatar = getAvatarById(user['selected_avatar_id'] ?? user['avatar_id']);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(backgroundColor: avatar.color, child: Icon(avatar.icon, color: Colors.white, size: 18)),
      title: Text(user['handle'] ?? "Player", style: const TextStyle(color: Colors.white, fontSize: 14)),
      trailing: isAlreadyFriend
          ? const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20)
          : isPending
          ? const Text("REQUESTED", style: TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.bold))
          : IconButton(icon: const Icon(Icons.person_add, color: Colors.blueAccent), onPressed: () => _addFriend(user['uid'])),
      onTap: () async {
        final snap = await _db.child('users/${user['uid']}').get();
        if (snap.exists && mounted) _showFriendProfile(Map<String, dynamic>.from(snap.value as Map), user['uid'], isAlreadyFriend);
      },
    );
  }
}