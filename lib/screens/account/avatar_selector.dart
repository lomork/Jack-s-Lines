import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/online_service.dart';
import 'data/avatar_data.dart';

class AvatarSelectorScreen extends StatefulWidget {
  const AvatarSelectorScreen({super.key});

  @override
  State<AvatarSelectorScreen> createState() => _AvatarSelectorScreenState();
}

class _AvatarSelectorScreenState extends State<AvatarSelectorScreen> {
  final OnlineService _onlineService = OnlineService();
  String _selectedId = "avatar_1";

  @override
  void initState() {
    super.initState();
    _loadCurrentAvatar();
  }

  Future<void> _loadCurrentAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedId = prefs.getString('selected_avatar_id') ?? "avatar_1";
    });
  }

  Future<void> _selectAvatar(String id) async {
    setState(() => _selectedId = id);

    // 1. Save Local
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_avatar_id', id);

    // 2. Save Cloud (So opponents see it)
    await _onlineService.saveUserProfile({'avatar_id': id});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        title: const Text("CHOOSE AVATAR", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(20),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 20,
          mainAxisSpacing: 20,
        ),
        itemCount: allAvatars.length,
        itemBuilder: (context, index) {
          final avatar = allAvatars[index];
          final isSelected = _selectedId == avatar.id;

          return GestureDetector(
            onTap: () => _selectAvatar(avatar.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: isSelected ? avatar.color.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? avatar.color : Colors.transparent,
                  width: 3,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: avatar.color,
                    child: Icon(avatar.icon, size: 40, color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    avatar.name,
                    style: TextStyle(
                      color: isSelected ? avatar.color : Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (isSelected)
                    const Padding(
                      padding: EdgeInsets.only(top: 5),
                      child: Icon(Icons.check_circle, color: Colors.green, size: 20),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}