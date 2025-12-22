import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../screens/store/data/chip_data.dart';
import '../account/data/avatar_data.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  List<String> friendUids = [];
  Map<String, Map<String, dynamic>> friendProfiles = {};

  TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _listenToFriends();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // --- 1. LISTEN TO MY FRIENDS LIST ---
  void _listenToFriends() {
    final User? user = _auth.currentUser;
    if (user == null) return;

    _db.child('users/${user.uid}/friends').onValue.listen((event) {
      if (event.snapshot.exists) {
        final data = event.snapshot.value;
        List<String> newUids = [];

        // Handle both Map (if value is true) and List formats
        if (data is Map) {
          data.forEach((key, value) => newUids.add(key.toString()));
        } else if (data is List) {
          for (var item in data) { if(item != null) newUids.add(item.toString()); }
        }

        if (mounted) {
          setState(() {
            friendUids = newUids;
          });
          _fetchFriendProfiles();
        }
      } else {
        if(mounted) setState(() => friendUids = []);
      }
    });
  }

  // --- 2. FETCH PROFILES FOR FRIENDS ---
  Future<void> _fetchFriendProfiles() async {
    for (String uid in friendUids) {
      final snapshot = await _db.child('users/$uid').get();
      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        if (mounted) {
          setState(() {
            friendProfiles[uid] = data;
          });
        }
      }
    }
  }

  // --- 3. SEARCH FOR USERS ---
  Future<void> _performSearch(String query) async {
    if (query.length < 3) return;
    setState(() { _isSearching = true; _searchResults = []; });

    try {
      // Search by handle
      final snapshot = await _db.child('users').orderByChild('handle').startAt(query).endAt("$query\uf8ff").limitToFirst(10).get();

      List<Map<String, dynamic>> results = [];
      if (snapshot.exists) {
        final data = snapshot.value as Map;
        data.forEach((key, value) {
          if (key != _auth.currentUser?.uid) { // Don't show myself
            var userMap = Map<String, dynamic>.from(value);
            userMap['uid'] = key;
            results.add(userMap);
          }
        });
      }

      if (mounted) setState(() => _searchResults = results);
    } catch (e) {
      print("Search Error: $e");
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  // --- 4. ADD / REMOVE FRIEND LOGIC ---
  Future<void> _addFriend(String uid) async {
    final User? user = _auth.currentUser;
    if (user == null) return;

    // Add to my friends list (true as placeholder value)
    await _db.child('users/${user.uid}/friends/$uid').set(true);

    // Optional: Add to THEIR friends list too? (Mutual friendship)
    // await _db.child('users/$uid/friends/${user.uid}').set(true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Friend Added!")));
      _searchController.clear();
      setState(() => _searchResults = []);
    }
  }

  Future<void> _removeFriend(String uid) async {
    final User? user = _auth.currentUser;
    if (user == null) return;

    await _db.child('users/${user.uid}/friends/$uid').remove();
    setState(() {
      friendUids.remove(uid);
      friendProfiles.remove(uid);
    });
    if (mounted) Navigator.pop(context); // Close profile dialog
  }

  // --- UI: FRIEND PROFILE DIALOG ---
  void _showFriendProfile(Map<String, dynamic> data, String uid, bool isFriend) {
    String avatarId = data['avatar_id'] ?? "avatar_1";
    AvatarItem avatar = getAvatarById(avatarId);

    String chipId = data['selected_chip_id'] ?? "default_blue";
    GameChip chip = allGameChips.firstWhere((c) => c.id == chipId, orElse: () => allGameChips[0]);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(radius: 40, backgroundColor: avatar.color, child: Icon(avatar.icon, size: 40, color: Colors.white)),
            const SizedBox(height: 10),
            Text(data['name'] ?? "Unknown", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            Text(data['handle'] ?? "@unknown", style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 20),

            // STATS ROW
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatColumn("Wins", "${data['matches_won'] ?? 0}", Colors.green),
                _buildStatColumn("Losses", "${(data['matches_played'] ?? 0) - (data['matches_won'] ?? 0)}", Colors.red),
                _buildStatColumn("Streak", "${data['streak'] ?? 0}", Colors.purple),
              ],
            ),
            const SizedBox(height: 20),

            // SELECTED CHIP
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Favorite Chip: ", style: TextStyle(color: Colors.white70)),
                Icon(chip.icon, color: chip.color),
              ],
            ),

            const SizedBox(height: 20),

            if (isFriend)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent)),
                  onPressed: () => _removeFriend(uid),
                  child: const Text("Remove Friend", style: TextStyle(color: Colors.redAccent)),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  onPressed: () {
                    _addFriend(uid);
                    Navigator.pop(context);
                  },
                  child: const Text("Add Friend", style: TextStyle(color: Colors.white)),
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
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // HEADER & TABS
        Container(
          padding: const EdgeInsets.only(top: 20, bottom: 10),
          child: const Text("FRIENDS", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 2)),
        ),
        TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFFD700),
          labelColor: const Color(0xFFFFD700),
          unselectedLabelColor: Colors.grey,
          tabs: const [Tab(text: "My Friends"), Tab(text: "Add Friend")],
        ),

        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // TAB 1: MY FRIENDS LIST
              friendUids.isEmpty
                  ? const Center(child: Text("No friends yet.", style: TextStyle(color: Colors.white54)))
                  : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: friendUids.length,
                itemBuilder: (context, index) {
                  String uid = friendUids[index];
                  Map<String, dynamic>? profile = friendProfiles[uid];

                  if (profile == null) return const SizedBox(); // Loading...

                  String avatarId = profile['avatar_id'] ?? "avatar_1";
                  AvatarItem avatar = getAvatarById(avatarId);

                  return Card(
                    color: Colors.white.withOpacity(0.05),
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: avatar.color, child: Icon(avatar.icon, color: Colors.white)),
                      title: Text(profile['handle'] ?? "Unknown", style: const TextStyle(color: Colors.white)),
                      // Status is not strictly real-time here without presence system, using static fallback
                      subtitle: Text("Level ${(profile['matches_won'] ?? 0) ~/ 5 + 1}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      trailing: const Icon(Icons.info_outline, color: Colors.white54),
                      onTap: () => _showFriendProfile(profile, uid, true),
                    ),
                  );
                },
              ),

              // TAB 2: SEARCH / ADD
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Search by Handle (e.g. @Player)",
                        hintStyle: const TextStyle(color: Colors.white54),
                        prefixIcon: const Icon(Icons.search, color: Colors.white54),
                        fillColor: Colors.white10,
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward, color: Colors.blue), onPressed: () => _performSearch(_searchController.text)),
                      ),
                      onSubmitted: _performSearch,
                    ),
                    const SizedBox(height: 20),
                    if (_isSearching) const CircularProgressIndicator(),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final user = _searchResults[index];
                          String avatarId = user['avatar_id'] ?? "avatar_1";
                          AvatarItem avatar = getAvatarById(avatarId);
                          bool isAlreadyFriend = friendUids.contains(user['uid']);

                          return ListTile(
                            leading: CircleAvatar(backgroundColor: avatar.color, child: Icon(avatar.icon, color: Colors.white)),
                            title: Text(user['handle'], style: const TextStyle(color: Colors.white)),
                            trailing: isAlreadyFriend
                                ? const Icon(Icons.check, color: Colors.green)
                                : ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.symmetric(horizontal: 10)),
                              onPressed: () => _addFriend(user['uid']),
                              child: const Text("Add", style: TextStyle(fontSize: 12)),
                            ),
                            onTap: () => _showFriendProfile(user, user['uid'], isAlreadyFriend),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}