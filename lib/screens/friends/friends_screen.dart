import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../screens/friends/tabs/friends_tab.dart';
import '../../screens/friends/tabs/invites_tab.dart';
import '../../screens/friends/tabs/history_tab.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        automaticallyImplyLeading: false, // CHANGED: Removes the back button
        title: const Text("SOCIAL", style: TextStyle(color: Colors.white, letterSpacing: 1.5)),
        // Removed the 'leading' IconButton block entirely
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          labelColor: Colors.amber,
          unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: "FRIENDS"),
            Tab(text: "REQUESTS"),
            Tab(text: "DISCOVER"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          FriendsTab(),
          RequestsTab(),
          DiscoverTab(),
        ],
      ),
    );
  }
}