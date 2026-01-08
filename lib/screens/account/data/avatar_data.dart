import 'package:flutter/material.dart';

class AvatarItem {
  final String id;
  final String name;
  final Color color; // Keep color for borders/glows
  final String assetPath; // CHANGED: Replaced IconData with assetPath

  const AvatarItem({
    required this.id,
    required this.name,
    required this.color,
    required this.assetPath,
  });
}

// --- THE LIST OF AVATARS ---
// Ensure you have these files in your assets/avatars/ folder
final List<AvatarItem> allAvatars = [
  const AvatarItem(
      id: "avatar_1",
      name: "Adventurer",
      color: Colors.blue,
      assetPath: "assets/avatars/avatar_1.png"
  ),
  const AvatarItem(
      id: "avatar_2",
      name: "Zombie",
      color: Colors.red,
      assetPath: "assets/avatars/avatar_2.png"
  ),
  const AvatarItem(
      id: "avatar_3",
      name: "Female",
      color: Colors.green,
      assetPath: "assets/avatars/avatar_3.png"
  ),
  const AvatarItem(
      id: "avatar_4",
      name: "Player",
      color: Colors.purple,
      assetPath: "assets/avatars/avatar_4.png"
  ),
  const AvatarItem(
      id: "avatar_5",
      name: "Soldier",
      color: Colors.black,
      assetPath: "assets/avatars/avatar_5.png"
  ),
  const AvatarItem(
      id: "avatar_6",
      name: "King",
      color: Colors.amber,
      assetPath: "assets/avatars/avatar_6.png"
  ),
];

// Helper to get avatars by ID
AvatarItem getAvatarById(String? id) {
  return allAvatars.firstWhere((a) => a.id == id, orElse: () => allAvatars[0]);
}