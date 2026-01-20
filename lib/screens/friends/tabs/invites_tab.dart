import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../../database/online_service.dart';
import '../../account/data/avatar_data.dart';

class RequestsTab extends StatefulWidget {
  const RequestsTab({super.key});

  @override
  State<RequestsTab> createState() => _RequestsTabState();
}

class _RequestsTabState extends State<RequestsTab> {
  final OnlineService _onlineService = OnlineService();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionTitle("INCOMING REQUESTS"),
        _buildIncomingList(),
        const SizedBox(height: 20),
        _buildSectionTitle("OUTGOING REQUESTS"),
        _buildOutgoingList(),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
          title,
          style: const TextStyle(
              color: Colors.amber,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1
          )
      ),
    );
  }

  Widget _buildIncomingList() {
    return StreamBuilder<DatabaseEvent>(
      stream: _onlineService.getIncomingRequestsStream(),
      builder: (context, snapshot) {
        // DEBUGGING
        if (snapshot.hasError) debugPrint("Incoming Stream Error: ${snapshot.error}");
        if (snapshot.connectionState == ConnectionState.active) {
          debugPrint("Incoming Data Raw: ${snapshot.data?.snapshot.value}");
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.white10));
        }

        List<String> uids = [];
        if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
          try {
            final data = Map<dynamic, dynamic>.from(snapshot.data!.snapshot.value as Map);
            uids = data.keys.cast<String>().toList();
          } catch (e) {
            print("Error parsing incoming requests: $e");
          }
        }

        return ExpansionTile(
          key: const PageStorageKey('incoming_requests'),
          initiallyExpanded: true,
          collapsedBackgroundColor: Colors.white.withOpacity(0.05),
          backgroundColor: Colors.transparent,
          iconColor: Colors.white,
          collapsedIconColor: Colors.white,
          title: Text(
              "Received (${uids.length})",
              style: const TextStyle(color: Colors.white)
          ),
          children: uids.isEmpty
              ? [const Padding(padding: EdgeInsets.all(16), child: Text("No pending requests", style: TextStyle(color: Colors.white30)))]
              : uids.map((uid) => _buildUserTile(uid, isIncoming: true)).toList(),
        );
      },
    );
  }

  Widget _buildOutgoingList() {
    return StreamBuilder<DatabaseEvent>(
      stream: _onlineService.getOutgoingRequestsStream(),
      builder: (context, snapshot) {
        // DEBUGGING
        if (snapshot.connectionState == ConnectionState.active) {
          debugPrint("Outgoing Data Raw: ${snapshot.data?.snapshot.value}");
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.white10));
        }

        List<String> uids = [];
        if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
          try {
            final data = Map<dynamic, dynamic>.from(snapshot.data!.snapshot.value as Map);
            uids = data.keys.cast<String>().toList();
          } catch (e) {
            print("Error parsing outgoing requests: $e");
          }
        }

        return ExpansionTile(
          key: const PageStorageKey('outgoing_requests'),
          initiallyExpanded: true,
          collapsedBackgroundColor: Colors.white.withOpacity(0.05),
          backgroundColor: Colors.transparent,
          iconColor: Colors.white,
          collapsedIconColor: Colors.white,
          title: Text(
              "Sent (${uids.length})",
              style: const TextStyle(color: Colors.white)
          ),
          children: uids.isEmpty
              ? [const Padding(padding: EdgeInsets.all(16), child: Text("No sent requests", style: TextStyle(color: Colors.white30)))]
              : uids.map((uid) => _buildUserTile(uid, isIncoming: false)).toList(),
        );
      },
    );
  }

  Widget _buildUserTile(String uid, {required bool isIncoming}) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _onlineService.getFriendPublicData(uid),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const ListTile(
          leading: CircleAvatar(backgroundColor: Colors.white10),
          title: Text("Loading...", style: TextStyle(color: Colors.white54)),
        );

        var profile = snapshot.data!;
        String name = profile['username'] ?? "Unknown";
        String avatar = profile['avatars'] ?? "avatar_1";

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.grey[800],
            backgroundImage: AssetImage(getAvatarById(avatar).assetPath),
          ),
          title: Text(name, style: const TextStyle(color: Colors.white)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: isIncoming
                ? [
              IconButton(
                icon: const Icon(Icons.check_circle, color: Colors.greenAccent),
                onPressed: () async {
                  await _onlineService.acceptFriendRequest(uid);
                  if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("You and $name are now friends!")));
                },
              ),
              IconButton(
                icon: const Icon(Icons.cancel, color: Colors.redAccent),
                onPressed: () => _onlineService.rejectFriendRequest(uid),
              ),
            ]
                : [
              TextButton(
                onPressed: () => _onlineService.cancelFriendRequest(uid),
                child: const Text("CANCEL", style: TextStyle(color: Colors.redAccent, fontSize: 12)),
              )
            ],
          ),
        );
      },
    );
  }
}