import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HistoryTab extends StatelessWidget {
  final List<Map<String, dynamic>> games;
  final bool isLoading;

  const HistoryTab({super.key, required this.games, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.orange));
    }

    if (games.isEmpty) {
      return const Center(
        child: Text("No completed games yet.", style: TextStyle(color: Colors.white54)),
      );
    }

    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return ListView.builder(
      itemCount: games.length,
      itemBuilder: (context, index) {
        var game = games[index];
        String result = "DRAW";
        Color color = Colors.grey;

        // Determine Winner
        if (game['winner_id'] == myUid) {
          result = "VICTORY";
          color = Colors.green;
        } else if (game['winner_id'] != null) {
          result = "DEFEAT";
          color = Colors.red;
        }

        // Determine Opponent Name
        String opponent = (game['host_id'] == myUid)
            ? (game['guest_name'] ?? "Guest")
            : (game['host_name'] ?? "Host");

        return ListTile(
          leading: Icon(Icons.history, color: color),
          title: Text("vs $opponent", style: const TextStyle(color: Colors.white)),
          subtitle: Text(result, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          trailing: Text(
            DateTime.fromMillisecondsSinceEpoch(game['match_start_time'] ?? 0)
                .toString().split(' ')[0], // Shows YYYY-MM-DD
            style: const TextStyle(color: Colors.white24, fontSize: 12),
          ),
        );
      },
    );
  }
}