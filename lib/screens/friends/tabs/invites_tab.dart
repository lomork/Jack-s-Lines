import 'package:flutter/material.dart';
import '../../../database/online_service.dart';

class InvitesTab extends StatelessWidget {
  final List<Map<String, dynamic>> invites;
  final OnlineService onlineService;
  final Function(Map<String, dynamic>) onAccept;

  const InvitesTab({
    super.key,
    required this.invites,
    required this.onlineService,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    if (invites.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mark_email_unread, size: 60, color: Colors.white24),
            SizedBox(height: 10),
            Text("No active invites", style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: invites.length,
      itemBuilder: (context, index) {
        final invite = invites[index];

        // Calculate Time Left (120 seconds = 2 minutes)
        int timestamp = invite['timestamp'] ?? 0;
        int now = DateTime.now().millisecondsSinceEpoch;
        int diffSeconds = (now - timestamp) ~/ 1000;
        int timeLeft = 120 - diffSeconds;

        // If time is up, don't show it (or auto-reject)
        if (timeLeft <= 0) {
          onlineService.rejectGameInvite(invite['key']);
          return const SizedBox.shrink();
        }

        return Card(
          color: Colors.grey[900],
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.videogame_asset, color: Colors.orange, size: 30),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "${invite['from_name'] ?? 'Someone'} challenges you!",
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          const Text("1v1 Match", style: TextStyle(color: Colors.white54, fontSize: 12)),
                        ],
                      ),
                    ),
                    // Countdown Timer
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: timeLeft.toDouble(), end: 0),
                      duration: Duration(seconds: timeLeft),
                      onEnd: () {
                        // Auto-expire when timer hits 0
                        onlineService.rejectGameInvite(invite['key']);
                      },
                      builder: (context, value, child) {
                        return Text(
                          "${value.toInt()}s",
                          style: TextStyle(
                            color: value < 30 ? Colors.red : Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => onlineService.rejectGameInvite(invite['key']),
                      child: const Text("DECLINE", style: TextStyle(color: Colors.redAccent)),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      onPressed: () => onAccept(invite),
                      child: const Text("ACCEPT CHALLENGE", style: TextStyle(color: Colors.white)),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }
}