import 'package:flutter/material.dart';
import '../../../database/online_service.dart';
import '../../account/data/avatar_data.dart';

// REPURPOSED AS DISCOVER TAB
class DiscoverTab extends StatefulWidget {
  const DiscoverTab({super.key});

  @override
  State<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends State<DiscoverTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  final OnlineService _onlineService = OnlineService();
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;

  void _doSearch() async {
    if (_searchCtrl.text.isEmpty) return;
    setState(() => _searching = true);

    // Note: The backend search uses lowercase indexing, but we display the results
    // which match the handle.
    List<Map<String, dynamic>> res = await _onlineService.searchUsers(_searchCtrl.text);

    if (mounted) {
      setState(() {
        _results = res;
        _searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Enter Handle (Case Sensitive)", // User Request
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search, color: Colors.amber),
                onPressed: _doSearch,
              ),
            ),
            onSubmitted: (_) => _doSearch(),
          ),
        ),
        if (_searching)
          const CircularProgressIndicator(color: Colors.amber)
        else
          Expanded(
            child: ListView.separated(
              itemCount: _results.length,
              separatorBuilder: (c, i) => const Divider(color: Colors.white10),
              itemBuilder: (context, index) {
                final user = _results[index];
                final uid = user['uid'];

                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: AssetImage(getAvatarById(user['avatars']).assetPath),
                  ),
                  title: Text(user['username'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  trailing: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white10,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      _onlineService.sendFriendRequest(uid);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Request Sent!")));
                    },
                    icon: const Icon(Icons.person_add, size: 16),
                    label: const Text("ADD"),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}