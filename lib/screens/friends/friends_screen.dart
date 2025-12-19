// lib/screens/menu/friends_screen.dart
import 'package:flutter/material.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<Map<String, dynamic>> friends = [
    {"handle": "@Mike_J", "status": "Online", "avatar": Icons.face},
    {"handle": "@Sarah_C", "status": "Playing", "avatar": Icons.face_3},
    {"handle": "@Davey", "status": "Offline", "avatar": Icons.face_6},
  ];

  final List<Map<String, dynamic>> requests = [
    {"handle": "@Player_554", "avatar": Icons.person},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // HEADER
        Container(
          padding: const EdgeInsets.only(top: 20, bottom: 10),
          child: const Text(
            "FRIENDS",
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFFFFD700), letterSpacing: 3.0),
          ),
        ),

        // SEARCH BAR (Updated Hint)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              // NEW HINT TEXT
              hintText: "Find friend by @handle or ID...",
              hintStyle: const TextStyle(color: Colors.grey),
              prefixIcon: const Icon(Icons.search, color: Color(0xFFFFD700)),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),

        const SizedBox(height: 15),

        TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFFD700),
          labelColor: const Color(0xFFFFD700),
          unselectedLabelColor: Colors.grey,
          tabs: [
            const Tab(text: "MY FRIENDS"),
            Tab(text: "REQUESTS"),
          ],
        ),

        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildFriendsList(),
              _buildRequestsList(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFriendsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: friends.length,
      itemBuilder: (context, index) {
        final friend = friends[index];
        return Card(
          color: Colors.white.withOpacity(0.05),
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.white10,
              child: Icon(friend['avatar'], color: Colors.white),
            ),
            // ONLY HANDLE
            title: Text(friend['handle'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _getStatusColor(friend['status'])),
                ),
                const SizedBox(width: 5),
                Text(friend['status'], style: TextStyle(color: _getStatusColor(friend['status']), fontSize: 12)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRequestsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: requests.length,
      itemBuilder: (context, index) {
        final req = requests[index];
        return Card(
          color: Colors.white.withOpacity(0.05),
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: ListTile(
            leading: CircleAvatar(backgroundColor: Colors.white10, child: Icon(req['avatar'], color: Colors.white)),
            title: Text(req['handle'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: const Text("Wants to add you", style: TextStyle(color: Colors.grey, fontSize: 12)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  onPressed: () => setState(() => requests.removeAt(index)),
                ),
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.green),
                  onPressed: () {
                    setState(() {
                      friends.add({...req, "status": "Online"});
                      requests.removeAt(index);
                    });
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case "Online": return Colors.green;
      case "Playing": return Colors.amber;
      default: return Colors.grey;
    }
  }
}