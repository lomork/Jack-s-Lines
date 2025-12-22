import 'package:flutter/material.dart';

enum ItemType { chip, coinPack, lifeRefill }

class StoreItem {
  final String id;
  final String name;
  final String description;
  final int rewardAmount; // How many coins/lives you get
  final double realMoneyPrice; // If 0, it costs coins
  final int coinPrice; // If 0, it costs real money
  final ItemType type;
  final IconData icon;
  final Color color;

  const StoreItem({
    required this.id,
    required this.name,
    required this.description,
    this.rewardAmount = 0,
    this.realMoneyPrice = 0.0,
    this.coinPrice = 0,
    required this.type,
    required this.icon,
    required this.color,
  });
}

// --- DATA DEFINITIONS ---

final List<StoreItem> coinItems = [
  const StoreItem(id: "coins_handful", name: "Handful", description: "500 Coins", rewardAmount: 500, realMoneyPrice: 0.99, type: ItemType.coinPack, icon: Icons.circle, color: Colors.amber),
  const StoreItem(id: "coins_sack", name: "Sack", description: "1200 Coins", rewardAmount: 1200, realMoneyPrice: 1.99, type: ItemType.coinPack, icon: Icons.shopping_bag, color: Colors.amber),
  const StoreItem(id: "coins_chest", name: "Chest", description: "5000 Coins", rewardAmount: 5000, realMoneyPrice: 4.99, type: ItemType.coinPack, icon: Icons.inventory_2, color: Colors.orangeAccent),
  const StoreItem(id: "coins_vault", name: "Vault", description: "15000 Coins", rewardAmount: 15000, realMoneyPrice: 9.99, type: ItemType.coinPack, icon: Icons.account_balance, color: Colors.deepOrange),
];

final List<StoreItem> lifeItems = [
  const StoreItem(id: "lives_one", name: "Refill (+1)", description: "Get 1 Life back", rewardAmount: 1, coinPrice: 200, type: ItemType.lifeRefill, icon: Icons.favorite, color: Colors.redAccent),
  const StoreItem(id: "lives_full", name: "Full Restore", description: "Max out Lives", rewardAmount: 5, realMoneyPrice: 0.99, type: ItemType.lifeRefill, icon: Icons.favorite_border, color: Colors.pinkAccent),
  const StoreItem(id: "lives_full", name: "Full Restore", description: "Max out Lives", rewardAmount: 5, coinPrice: 500, type: ItemType.lifeRefill, icon: Icons.favorite_border, color: Colors.pinkAccent),

];