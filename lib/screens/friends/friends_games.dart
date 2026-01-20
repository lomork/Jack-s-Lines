import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Requires 'intl' package in pubspec.yaml
import '../../database/online_service.dart';
// import '../../screens/store/data/chip_data.dart'; // Unused for now, commented out

// RENAMED to match filename
class FriendsGamesScreen extends StatefulWidget {
  const FriendsGamesScreen({super.key});

  @override
  State<FriendsGamesScreen> createState() => _FriendsGamesScreenState();
}

class _FriendsGamesScreenState extends State<FriendsGamesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final OnlineService _onlineService = OnlineService();

  @override
  void initState() {
    super.initState();
    // Changed length to 3 to match the tabs below
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
        // Changed title as requested
        title: const Text("FRIENDS GAMES", style: TextStyle(color: Colors.white, letterSpacing: 1.5)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          labelColor: Colors.amber,
          unselectedLabelColor: Colors.grey,
          // Reduced font size slightly to fit 3 tabs comfortably
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
          tabs: const [
            Tab(text: "INVITES"), // Renamed from GAME INVITES for space
            Tab(text: "ACTIVE"),
            Tab(text: "HISTORY"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 1. GAME INVITES
          const _GameInvitesView(),

          // 2. ACTIVE MATCHES
          const _ActiveMatchesView(),

          // 3. MATCH HISTORY
          _MatchHistoryView(onlineService: _onlineService),
        ],
      ),
    );
  }
}

// --- SUB-WIDGETS ---

class _GameInvitesView extends StatelessWidget {
  const _GameInvitesView();

  @override
  Widget build(BuildContext context) {
    // TODO: Connect to _onlineService.getGameInvitesStream()
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.mail_outline, size: 48, color: Colors.grey[700]),
          const SizedBox(height: 16),
          const Text("No Pending Invites", style: TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }
}

class _ActiveMatchesView extends StatelessWidget {
  const _ActiveMatchesView();

  @override
  Widget build(BuildContext context) {
    // TODO: Implement 24h match fetching
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.access_time, size: 48, color: Colors.amber),
          const SizedBox(height: 16),
          const Text("Active Matches", style: TextStyle(color: Colors.white, fontSize: 18)),
          const SizedBox(height: 8),
          const Text("Long-term battles coming soon!", style: TextStyle(color: Colors.white38)),
        ],
      ),
    );
  }
}

class _MatchHistoryView extends StatelessWidget {
  final OnlineService onlineService;
  const _MatchHistoryView({required this.onlineService});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: onlineService.getUserMatchHistory(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.amber));
        }
        // Handle null or empty lists safely
        if (!snapshot.hasData || (snapshot.data as List).isEmpty) {
          return const Center(child: Text("No matches played yet.", style: TextStyle(color: Colors.white38)));
        }

        final matches = snapshot.data!;
        return ListView.builder(
          itemCount: matches.length,
          padding: const EdgeInsets.only(top: 8),
          itemBuilder: (context, index) {
            final match = matches[index];
            bool won = match['result'] == 'win';

            // Date Formatting using 'intl' package
            String dateStr = "Unknown Date";
            if (match['timestamp'] != null) {
              final date = DateTime.fromMillisecondsSinceEpoch(match['timestamp']);
              // Format: Oct 25, 2023 10:30 AM
              dateStr = DateFormat.yMMMd().add_jm().format(date);
            }

            return Card(
              color: Colors.white.withOpacity(0.05),
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: won ? Colors.amber.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    won ? Icons.emoji_events : Icons.close,
                    color: won ? Colors.amber : Colors.redAccent,
                    size: 20,
                  ),
                ),
                title: Text(
                  won ? "VICTORY" : "DEFEAT",
                  style: TextStyle(
                    color: won ? Colors.amber : Colors.redAccent,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    fontSize: 14,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    "vs ${match['opponent_name'] ?? 'Unknown'}\n$dateStr",
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.white30),
                onTap: () {
                  if (match['board_snapshot'] != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SnapshotScreen(matchData: match),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Snapshot data missing for this match."))
                    );
                  }
                },
              ),
            );
          },
        );
      },
    );
  }
}

class SnapshotScreen extends StatelessWidget {
  final Map<String, dynamic> matchData;
  const SnapshotScreen({super.key, required this.matchData});

  @override
  Widget build(BuildContext context) {
    List<int> board = List.filled(100, 0);
    Set<int> winningIndices = {};

    try {
      if (matchData['board_snapshot'] != null) {
        String snap = matchData['board_snapshot'].toString();
        if (snap.isNotEmpty) {
          board = snap.split(',').map((e) => int.tryParse(e) ?? 0).toList();
        }
      }
      if (matchData['winning_indices'] != null) {
        String winStr = matchData['winning_indices'].toString();
        if (winStr.isNotEmpty) {
          winningIndices = winStr.split(',').map((e) => int.tryParse(e) ?? -1).where((e) => e != -1).toSet();
        }
      }
    } catch (e) {
      print("Snapshot parse error: $e");
    }

    // Safety check for board size
    if (board.length < 100) {
      board = List.filled(100, 0);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "VS ${matchData['opponent_name'] ?? 'Opponent'}",
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const Text("Game Snapshot", style: TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      ),
      body: Center(
        child: AspectRatio(
          aspectRatio: 0.70, // Matches standard board aspect ratio
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 10,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
              childAspectRatio: 0.70,
            ),
            itemCount: 100,
            itemBuilder: (context, index) {
              // Safety check for index bounds
              int owner = (index < board.length) ? board[index] : 0;
              bool isWinningChip = winningIndices.contains(index);

              // Empty spot
              if (owner == 0) {
                return Container(
                    decoration: BoxDecoration(
                        border: Border.all(color: Colors.white10),
                        borderRadius: BorderRadius.circular(4)
                    )
                );
              }

              // Chip colors (Default Red/Blue logic)
              Color chipColor = Colors.grey;
              if (owner == 1) chipColor = Colors.redAccent;
              if (owner == 2) chipColor = Colors.blueAccent;

              return Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: chipColor,
                  // Gold Glow for winning chips
                  border: isWinningChip ? Border.all(color: Colors.amber, width: 2) : null,
                  boxShadow: isWinningChip ? [
                    BoxShadow(color: Colors.amber.withOpacity(0.6), blurRadius: 8, spreadRadius: 1)
                  ] : null,
                ),
                child: isWinningChip
                    ? const Icon(Icons.star, size: 14, color: Colors.white)
                    : null,
              );
            },
          ),
        ),
      ),
    );
  }
}