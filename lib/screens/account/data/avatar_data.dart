import 'package:flutter/material.dart';

class AvatarItem {
  final String id;
  final String name;
  final Color color;
  final IconData icon; // Replace with 'String assetPath' if using images

  const AvatarItem({
    required this.id,
    required this.name,
    required this.color,
    required this.icon,
  });
}

// --- THE LIST OF AVATARS ---
final List<AvatarItem> allAvatars = [
  const AvatarItem(id: "avatar_1", name: "Rookie", color: Colors.blue, icon: Icons.face),
  const AvatarItem(id: "avatar_2", name: "Speedster", color: Colors.red, icon: Icons.directions_run),
  const AvatarItem(id: "avatar_3", name: "Tank", color: Colors.green, icon: Icons.shield),
  const AvatarItem(id: "avatar_4", name: "Mage", color: Colors.purple, icon: Icons.auto_fix_high),
  const AvatarItem(id: "avatar_5", name: "Ninja", color: Colors.black, icon: Icons.visibility_off),
  const AvatarItem(id: "avatar_6", name: "King", color: Colors.amber, icon: Icons.emoji_events),
];

// Helper to get avatar by ID
AvatarItem getAvatarById(String? id) {
  return allAvatars.firstWhere((a) => a.id == id, orElse: () => allAvatars[0]);
}