import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../screens/store/data/chip_data.dart';
import '../account/data/avatar_data.dart';
import '../../notifications/notification_manager.dart';
import '../../database/online_service.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final NotificationManager _notifManager = NotificationManager();
  final OnlineService _onlineService = OnlineService();

  List<String> friendUids = [];
  Map<String, Map<String, dynamic>> friendProfiles = {};

  List<Map<String, dynamic>> _incomingRequests = [];
  List<Map<String, dynamic>> _outgoingRequests = [];

  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _recentOpponents = [];
  bool _isSearching = false;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _notifManager.init();
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

    _db.child('users/${user.uid}/friends').onValue.listen((event) {
      if (!mounted) return;
      List<Map<String, dynamic>> incoming = [];
      List<Map<String, dynamic>> outgoing = [];

      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map;
        data.forEach((uid, details) {
          if (details is Map) {
            if (details['status'] == 'pending')
              incoming.add({'uid': uid, ...details});
            if (details['status'] == 'requested')
              outgoing.add({'uid': uid, ...details});
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
        if (mounted) setState(() => friendUids = []);
      }
    });
  }

  Future<void> _fetchFriendProfiles() async {
    for (String uid in friendUids) {
      final profile = await _onlineService.getFriendPublicData(uid);
      if (profile != null && mounted) {
        setState(() => friendProfiles[uid] = profile);
      }
    }
  }

  Future<void> _fetchRecentOpponents() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final snapshot = await _db
          .child('users/${user.uid}/match_history')
          .limitToLast(15)
          .get();
      if (snapshot.exists) {
        final data = snapshot.value as Map;
        Map<String, Map<String, dynamic>> uniqueOpponents = {};

        data.forEach((key, value) {
          if (value['opponent_id'] != null) {
            uniqueOpponents[value['opponent_id']] = {
              'uid': value['opponent_id'],
              'username': value['opponent_name'] ?? "Unknown",
              'avatar': value['opponent_avatar'] ?? "avatar_1",
            };
          }
        });

        if (mounted) {
          setState(
            () => _recentOpponents = uniqueOpponents.values
                .toList()
                .reversed
                .toList(),
          );
        }
      }
    } catch (e) {
      debugPrint("Recent Opponents Error: $e");
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isSearching = true;
      _hasSearched = true;
    });

    try {
      final results = await _onlineService.searchUsers(query.trim());
      if (mounted) {
        setState(() {
          _searchResults = results
              .where((u) => u['uid'] != _auth.currentUser?.uid)
              .toList();
        });
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Search failed.")));
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _addFriend(String targetUid) async {
    final User? user = _auth.currentUser;
    if (user == null) return;

    try {
      String myName = "Player";
      final myProfile = await _onlineService.getUserProfile();
      if (myProfile != null) myName = myProfile['username'] ?? "Player";

      await _db.child('users/${user.uid}/friends/$targetUid').set({
        'added_at': ServerValue.timestamp,
        'status': 'requested',
      });

      await _db.child('users/$targetUid/friends/${user.uid}').set({
        'added_at': ServerValue.timestamp,
        'status': 'pending',
      });

      await _notifManager.sendFriendRequest(targetUid, myName);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Friend Request Sent!")));
      }
    } catch (e) {
      debugPrint("Add friend error: $e");
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Action failed.")));
    }
  }

  Future<void> _acceptFriend(String targetUid) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _db
        .child('users/${user.uid}/friends/$targetUid/status')
        .set('active');
    await _db
        .child('users/$targetUid/friends/${user.uid}/status')
        .set('active');

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Friendship Accepted!"),
        backgroundColor: Colors.green,
      ),
    );
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

  void _showFriendProfile(
    Map<String, dynamic> data,
    String uid,
    bool isFriend,
  ) {
    String avatarId = data['avatar'] ?? "avatar_1";
    AvatarItem avatar = getAvatarById(avatarId);
    String username = data['username'] ?? "Player";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(25),
          side: const BorderSide(color: Colors.white10),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 45,
              backgroundColor: avatar.color,
              child: Icon(avatar.icon, size: 45, color: Colors.white),
            ),
            const SizedBox(height: 15),
            Text(
              username,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 25),
            if (isFriend)
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  color: Colors.redAccent.withOpacity(0.1),
                  onPressed: () => _removeFriend(uid),
                  child: const Text(
                    "UNFRIEND",
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
                  child: const Text(
                    "ADD FRIEND",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
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
        title: const Text(
          "FRIENDS",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 3,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.blueAccent,
          tabs: [
            const Tab(text: "MY LIST"),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("REQUESTS"),
                  if (_incomingRequests.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(left: 5),
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        "${_incomingRequests.length}",
                        style: const TextStyle(
                          fontSize: 8,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
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
    if (friendUids.isEmpty)
      return const Center(
        child: Text("Empty list.", style: TextStyle(color: Colors.white24)),
      );
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: friendUids.length,
      itemBuilder: (context, index) {
        String uid = friendUids[index];
        Map<String, dynamic>? profile = friendProfiles[uid];
        if (profile == null) return const SizedBox();
        AvatarItem avatar = getAvatarById(profile['avatar'] ?? "avatar_1");

        return Card(
          color: Colors.white.withOpacity(0.04),
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: avatar.color,
              child: Icon(avatar.icon, color: Colors.white, size: 20),
            ),
            title: Text(
              profile['username'] ?? "Player",
              style: const TextStyle(color: Colors.white),
            ),
            onTap: () => _showFriendProfile(profile, uid, true),
          ),
        );
      },
    );
  }

  Widget _buildRequestsTab() {
    if (_incomingRequests.isEmpty && _outgoingRequests.isEmpty)
      return const Center(
        child: Text("No requests.", style: TextStyle(color: Colors.white24)),
      );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_incomingRequests.isNotEmpty) ...[
          const Text(
            "INCOMING",
            style: TextStyle(
              color: Colors.blueAccent,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          ..._incomingRequests.map((req) => _buildRequestTile(req, true)),
        ],
        if (_outgoingRequests.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text(
            "OUTGOING",
            style: TextStyle(
              color: Colors.orangeAccent,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          ..._outgoingRequests.map((req) => _buildRequestTile(req, false)),
        ],
      ],
    );
  }

  Widget _buildRequestTile(Map<String, dynamic> req, bool isIncoming) {
    return FutureBuilder(
      future: _onlineService.getFriendPublicData(req['uid']),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        final profile = snapshot.data!;
        final avatar = getAvatarById(profile['avatar'] ?? "avatar_1");

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: avatar.color,
            child: Icon(avatar.icon, color: Colors.white, size: 16),
          ),
          title: Text(
            profile['username'] ?? "Player",
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          trailing: isIncoming
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.check_circle,
                        color: Colors.greenAccent,
                      ),
                      onPressed: () => _acceptFriend(req['uid']),
                    ),
                    IconButton(
                      icon: const Icon(Icons.cancel, color: Colors.redAccent),
                      onPressed: () => _removeFriend(req['uid']),
                    ),
                  ],
                )
              : const Text(
                  "PENDING",
                  style: TextStyle(color: Colors.white24, fontSize: 10),
                ),
        );
      },
    );
  }

  Widget _buildDiscoverTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Search username...",
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => _performSearch(_searchController.text),
              ),
            ),
            onSubmitted: _performSearch,
          ),
          if (_isSearching)
            const Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: Colors.blueAccent),
            ),
          Expanded(
            child: _hasSearched && _searchResults.isEmpty && !_isSearching
                ? const Center(
                    child: Text(
                      "No users found.",
                      style: TextStyle(color: Colors.white24),
                    ),
                  )
                : ListView(
                    children: [
                      if (_searchResults.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text(
                          "RESULTS",
                          style: TextStyle(
                            color: Colors.blueAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        ..._searchResults.map(
                          (user) => _buildUserListTile(user),
                        ),
                      ],
                      // Show recent opponents if no search has been performed yet
                      if (!_hasSearched && _recentOpponents.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text(
                          "RECENT OPPONENTS",
                          style: TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        ..._recentOpponents.map(
                          (user) => _buildUserListTile(user),
                        ),
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
    bool isPending =
        _incomingRequests.any((r) => r['uid'] == user['uid']) ||
        _outgoingRequests.any((r) => r['uid'] == user['uid']);
    AvatarItem avatar = getAvatarById(user['avatar'] ?? "avatar_1");

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: avatar.color,
        child: Icon(avatar.icon, color: Colors.white, size: 18),
      ),
      title: Text(
        user['username'] ?? "Player",
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      trailing: isAlreadyFriend
          ? const Icon(Icons.check_circle, color: Colors.greenAccent)
          : isPending
          ? const Text(
              "REQUESTED",
              style: TextStyle(color: Colors.white24, fontSize: 9),
            )
          : IconButton(
              icon: const Icon(Icons.person_add, color: Colors.blueAccent),
              onPressed: () => _addFriend(user['uid']),
            ),
      onTap: () => _showFriendProfile(user, user['uid'], isAlreadyFriend),
    );
  }
}
