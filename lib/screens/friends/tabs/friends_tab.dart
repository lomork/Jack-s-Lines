import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../../database/online_service.dart';
import '../../account/data/avatar_data.dart';
import '../../game/game_board.dart';

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

  void _showWaitingDialog(String gameId, String friendUid, String friendName, String myName) {
    showDialog(
      context: context,
      barrierDismissible: false, // User must use Cancel button
      builder: (context) {
        return _InviteWaitingDialog(
          gameId: gameId,
          friendUid: friendUid,
          friendName: friendName,
          myName: myName,
          onlineService: _onlineService,
        );
      },
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
                    onPressed: () async {
                      // 1. Send Invite and Get ID
                      String? gameId = await _onlineService.sendGameInvite(uid, await _onlineService.getMyHandle()); // Helper needed or pass name

                      // For simplicity, we can fetch my name from cache or just pass "Player" temporarily
                      // if getMyHandle isn't public. Assuming logic from OnlineService:
                      String myName = "Me"; // You might want to fetch actual name

                      if (gameId != null && mounted) {
                        // 2. Show Waiting Dialog
                        _showWaitingDialog(gameId, uid, name, myName);
                      }
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

class _InviteWaitingDialog extends StatefulWidget {
  final String gameId;
  final String friendUid;
  final String friendName;
  final String myName;
  final OnlineService onlineService;

  const _InviteWaitingDialog({
    required this.gameId,
    required this.friendUid,
    required this.friendName,
    required this.myName,
    required this.onlineService,
  });

  @override
  State<_InviteWaitingDialog> createState() => _InviteWaitingDialogState();
}

class _InviteWaitingDialogState extends State<_InviteWaitingDialog> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  Timer? _timer;
  int _countdown = 60;

  @override
  void initState() {
    super.initState();

    // 1. Setup Pulsing Animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    // 2. Start Countdown
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_countdown > 0) {
            _countdown--;
          } else {
            _handleTimeout();
          }
        });
      }
    });

    // 3. Listen for Game Start (Friend Joined)
    widget.onlineService.onGameStateChanged = (data) {
      if (!mounted) return;
      if (data['status'] == 'playing') {
        _handleGameStart();
      }
    };
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _timer?.cancel();
    // Do not dispose onlineService here as it belongs to parent
    super.dispose();
  }

  void _handleGameStart() {
    Navigator.pop(context); // Close dialog
    // Navigate to Game
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const GameBoard(
          difficulty: "Online",
          isOnline: true,
          playerCount: 2,
        ),
      ),
    );
  }

  void _handleTimeout() {
    _timer?.cancel();
    Navigator.pop(context); // Close waiting dialog
    widget.onlineService.cancelGameInvite(widget.gameId, widget.friendUid);

    // Show Timeout Alert
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: const Text("NO RESPONSE", style: TextStyle(color: Colors.white)),
        content: Text("${widget.friendName} did not join.", style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK", style: TextStyle(color: Colors.amber)),
          )
        ],
      ),
    );
  }

  void _handleCancel() {
    _timer?.cancel();
    widget.onlineService.cancelGameInvite(widget.gameId, widget.friendUid);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF2C2C2C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "CHALLENGE SENT",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 30),

            // VS ROW
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Me (Green Glow)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.greenAccent.withOpacity(0.6), blurRadius: 15, spreadRadius: 2)
                    ],
                    border: Border.all(color: Colors.greenAccent, width: 2),
                  ),
                  child: const CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.grey,
                    child: Icon(Icons.person, color: Colors.white), // Could pass avatar here
                  ),
                ),

                const Text(
                  "VS",
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                  ),
                ),

                // Opponent (Pulsing)
                FadeTransition(
                  opacity: Tween<double>(begin: 0.4, end: 1.0).animate(_pulseController),
                  child: Column(
                    children: [
                      const CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.white10,
                        child: Icon(Icons.person_outline, color: Colors.white54),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Joining...",
                        style: TextStyle(color: Colors.amber.withOpacity(0.8), fontSize: 10),
                      )
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Handles Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(widget.myName, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                Text(widget.friendName, style: const TextStyle(color: Colors.white54)),
              ],
            ),

            const SizedBox(height: 30),

            // Timer
            Text(
              "$_countdown",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.w300,
              ),
            ),
            const Text(
              "seconds remaining",
              style: TextStyle(color: Colors.white30, fontSize: 12),
            ),

            const SizedBox(height: 20),

            // Cancel Button
            TextButton(
              onPressed: _handleCancel,
              style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent,
              ),
              child: const Text("CANCEL INVITE"),
            ),
          ],
        ),
      ),
    );
  }
}