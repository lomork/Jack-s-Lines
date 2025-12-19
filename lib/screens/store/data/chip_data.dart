import 'package:flutter/material.dart';

class GameChip {
  final String id;
  final String name;
  final IconData icon;
  final Color color;
  final int price; // Changed to int

  const GameChip({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.price,
  });
}

// THE MASTER LIST OF ALL CHIPS IN THE GAME
final List<GameChip> allGameChips = [
  // Default Chip (Everyone has this)
  const GameChip(
      id: "default_blue",
      name: "Classic Blue",
      price: 0,
      color: Colors.blue,
      icon: Icons.circle
  ),

  // Shop Chips - PRICES ARE NOW INTEGERS (No Quotes)
  const GameChip(
      id: "neon_blue",
      name: "Neon Blue",
      price: 300,
      color: Colors.cyanAccent,
      icon: Icons.bolt
  ),
  const GameChip(
      id: "ruby_red",
      name: "Ruby Red",
      price: 500,
      color: Colors.redAccent,
      icon: Icons.diamond
  ),
  const GameChip(
      id: "golden_king",
      name: "Golden King",
      price: 5000,
      color: Colors.amber,
      icon: Icons.emoji_events
  ),
  const GameChip(
      id: "dark_matter",
      name: "Dark Matter",
      price: 299, // Representing cents or coins
      color: Colors.deepPurple,
      icon: Icons.nights_stay
  ),
  const GameChip(
      id: "love_strike",
      name: "Love Strike",
      price: 1000,
      color: Colors.pinkAccent,
      icon: Icons.favorite
  ),
  const GameChip(
      id: "toxic_green",
      name: "Toxic Green",
      price: 2500,
      color: Colors.greenAccent,
      icon: Icons.science
  ),
];