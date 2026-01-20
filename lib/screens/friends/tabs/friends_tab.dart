import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../../database/online_service.dart';
import '../../account/data/avatar_data.dart';

class FriendsTab extends StatefulWidget {
  const FriendsTab({super.key});

  @override
  State<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<FriendsTab> {
  final OnlineService _onlineService = OnlineService();

  void _showFriendStats(String uid, String name, String avatarId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return FutureBuilder<Map<String, dynamic>?>(
          future: _onlineService.getFriendStats(uid),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

            final data = snapshot.data!;
            final int won = data['matches_won'] ?? 0;
            final int played = data['matches_played'] ?? 0;
            final int lost = played - won;
            final String chip = data['selected_chip'] ?? "Unknown";

            return Container(
              padding: const EdgeInsets.all(24),
              height: 350,
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.amber,
                    child: ClipOval(
                      child: Image.asset(
                        getAvatarById(avatarId).assetPath,
                        width: 76, height: 76, fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const Divider(color: Colors.white24, height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStat("WON", "$won", Colors.green),
                      _buildStat("LOST", "$lost", Colors.redAccent),
                      _buildStat("CHIP", chip.split('_').last.toUpperCase(), Colors.blueAccent),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.withOpacity(0.2),
                            foregroundColor: Colors.red,
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            _onlineService.removeFriend(uid);
                          },
                          icon: const Icon(Icons.person_remove),
                          label: const Text("REMOVE"),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber,
                            foregroundColor: Colors.black,
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            _onlineService.sendGameInvite(uid, name); // Simplified invite
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Challenged $name!")));
                          },
                          icon: const Icon(Icons.sports_esports),
                          label: const Text("CHALLENGE"),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: _onlineService.getFriendsStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
          return _buildEmptyState("No friends yet. Go to Discover!");
        }

        Map<dynamic, dynamic> friendsMap = snapshot.data!.snapshot.value as Map;
        List<String> friendUids = friendsMap.keys.cast<String>().toList();

        return ListView.builder(
          itemCount: friendUids.length,
          itemBuilder: (context, index) {
            String uid = friendUids[index];
            return FutureBuilder<Map<String, dynamic>?>(
              future: _onlineService.getFriendPublicData(uid),
              builder: (context, profileSnap) {
                if (!profileSnap.hasData) return const SizedBox();
                var profile = profileSnap.data!;
                String name = profile['username'] ?? "Unknown";
                String avatarId = profile['avatars'] ?? "avatar_1";

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: GestureDetector(
                    onTap: () => _showFriendStats(uid, name, avatarId),
                    child: Stack(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.grey[800],
                          backgroundImage: AssetImage(getAvatarById(avatarId).assetPath),
                        ),
                        // ACTIVE LIGHT
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: StreamBuilder<DatabaseEvent>(
                            stream: _onlineService.getUserPresenceStream(uid),
                            builder: (context, presenceSnap) {
                              bool isOnline = false;
                              if (presenceSnap.hasData && presenceSnap.data!.snapshot.value == 'online') {
                                isOnline = true;
                              }
                              return Container(
                                width: 12, height: 12,
                                decoration: BoxDecoration(
                                  color: isOnline ? Colors.greenAccent : Colors.grey,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.black, width: 2),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      shape: const StadiumBorder(),
                    ),
                    onPressed: () {
                      _onlineService.sendGameInvite(uid, name);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Invite sent to $name")));
                    },
                    child: const Text("VS"),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(String msg) {
    return Center(child: Text(msg, style: const TextStyle(color: Colors.white54)));
  }
}