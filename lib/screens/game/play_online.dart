import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'game_board.dart';

class PlayOnlineScreen extends StatelessWidget {
  const PlayOnlineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("MULTIPLAYER LOBBY",
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildModeCard(context, "1 v 1", "Classic Duel (2 Sequences)",
                Colors.blueAccent, Icons.person, 2, false),
            const SizedBox(height: 20),
            _buildModeCard(context, "1 v 1 v 1", "Triple Threat (1 Sequence)",
                Colors.greenAccent, Icons.groups_3, 3, false),
            const SizedBox(height: 20),
            _buildModeCard(context, "2 v 2", "Team Battle (2 Sequences)",
                Colors.orangeAccent, Icons.group, 4, true),
          ],
        ),
      ),
    );
  }

  Widget _buildModeCard(BuildContext context, String title, String sub,
      Color color, IconData icon, int players, bool team) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => GameBoard(isOnline: true, playerCount: players, isTeamMode: team))),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color.withOpacity(0.5), width: 2),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 40),
            const SizedBox(width: 20),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
              Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ],
        ),
      ),
    );
  }
}