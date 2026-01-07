import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import '../../../../database/online_service.dart';

class FriendsTab extends StatelessWidget {
  final List<String> friendUids;
  final Map<String, Map<String, dynamic>> friendProfiles;
  final List<Map<String, dynamic>> requests;
  final OnlineService onlineService;
  final Function(Map<String, dynamic>) onProfileTap;
  final Function(String) onAcceptRequest;

  // Search logic passed down
  final TextEditingController searchController;
  final bool isSearching;
  final List<Map<String, dynamic>> searchResults;
  final Function(String) onSearch;
  final Function(String) onSendRequest;

  const FriendsTab({
    super.key,
    required this.friendUids,
    required this.friendProfiles,
    required this.requests,
    required this.onlineService,
    required this.onProfileTap,
    required this.onAcceptRequest,
    required this.searchController,
    required this.isSearching,
    required this.searchResults,
    required this.onSearch,
    required this.onSendRequest,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 1. Friend Requests Header
        if (requests.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(10),
            color: Colors.orange.withOpacity(0.1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("FRIEND REQUESTS", style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
                ...requests.map((req) => ListTile(
                  leading: CircleAvatar(backgroundImage: AssetImage("assets/avatars/${req['avatar'] ?? 'avatar_1'}.png")),
                  title: Text(req['username'] ?? "Unknown", style: const TextStyle(color: Colors.white)),
                  trailing: IconButton(
                    icon: const Icon(Icons.check, color: Colors.green),
                    onPressed: () => onAcceptRequest(req['uid']),
                  ),
                  onTap: () => onProfileTap(req),
                )),
              ],
            ),
          ),

        // 2. Search Bar
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: searchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Search Username...",
              hintStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: Colors.white10,
              suffixIcon: IconButton(
                icon: const Icon(Icons.search, color: Colors.orange),
                onPressed: () => onSearch(searchController.text),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
            ),
            onSubmitted: onSearch,
          ),
        ),

        // 3. Main List (Search Results OR Friends)
        Expanded(
          child: isSearching
              ? (searchResults.isEmpty
              ? const Center(child: Text("No users found.", style: TextStyle(color: Colors.white54)))
              : ListView.builder(
            itemCount: searchResults.length,
            itemBuilder: (context, index) {
              var user = searchResults[index];
              return ListTile(
                leading: CircleAvatar(backgroundImage: AssetImage("assets/avatars/${user['avatar'] ?? 'avatar_1'}.png")),
                title: Text(user['username'] ?? "Unknown", style: const TextStyle(color: Colors.white)),
                trailing: IconButton(
                  icon: const Icon(Icons.person_add, color: Colors.orange),
                  onPressed: () => onSendRequest(user['uid']),
                ),
                onTap: () => onProfileTap(user),
              );
            },
          ))
              : (friendUids.isEmpty
              ? const Center(child: Text("No friends yet.", style: TextStyle(color: Colors.white54)))
              : ListView.builder(
            itemCount: friendUids.length,
            itemBuilder: (context, index) {
              String uid = friendUids[index];
              var profile = friendProfiles[uid] ?? {};
              profile['uid'] = uid;
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: AssetImage("assets/avatars/${profile['avatar'] ?? 'avatar_1'}.png"),
                ),
                title: Text(profile['username'] ?? "Loading...", style: const TextStyle(color: Colors.white)),
                subtitle: StreamBuilder<DatabaseEvent>(
                  stream: onlineService.getUserPresenceStream(uid),
                  builder: (context, snap) {
                    String status = (snap.hasData && snap.data!.snapshot.value == 'online') ? "Online" : "Offline";
                    return Text(status, style: TextStyle(color: status == "Online" ? Colors.green : Colors.grey));
                  },
                ),
                onTap: () => onProfileTap(profile),
              );
            },
          )),
        ),
      ],
    );
  }
}