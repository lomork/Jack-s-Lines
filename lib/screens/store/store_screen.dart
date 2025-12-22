import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Added for local sync
import '../../database/online_service.dart';
import 'data/chip_data.dart';
import 'data/store_data.dart';

class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> with TickerProviderStateMixin {
  final OnlineService _onlineService = OnlineService();
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late TabController _tabController;
  int userCoins = 1000;
  List<String> ownedChipIds = ['default_blue'];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _listenToUserData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Real-time listener for Firebase
  void _listenToUserData() {
    final User? user = _auth.currentUser;
    if (user == null) return;

    _db.child('users/${user.uid}').onValue.listen((event) {
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map;
        if (mounted) {
          setState(() {
            userCoins = data['coins'] ?? 0;
            if (data['owned_chips'] != null) {
              ownedChipIds = List<String>.from(data['owned_chips']);
            }
          });
        }
      }
    });
  }

  Future<void> _buyChip(GameChip chip) async {
    if (ownedChipIds.contains(chip.id)) return;

    if (userCoins < chip.price) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Not enough coins!"), backgroundColor: Colors.red));
      return;
    }

    setState(() => isLoading = true);
    bool success = await _onlineService.purchaseChip(chip.id, chip.price);
    setState(() => isLoading = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Purchased ${chip.name}!"), backgroundColor: Colors.green));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Purchase Failed. Try again."), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: SafeArea(
        child: Column(
          children: [
            // --- HEADER (MATCHING MENU STYLE) ---
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white10)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("STORE", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFFFFD700), letterSpacing: 2.0)),

                  // COIN BOX (Visual match to Menu)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.5), width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PulseWidget(
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: const Color(0xFFFFD700).withOpacity(0.6), blurRadius: 10, spreadRadius: 2)],
                            ),
                            child: const Icon(Icons.circle, color: Color(0xFFFFD700), size: 24),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text("$userCoins", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // --- TABS ---
            TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFFFFD700),
              labelColor: const Color(0xFFFFD700),
              unselectedLabelColor: Colors.grey,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              tabs: const [Tab(text: "CHIPS"), Tab(text: "COINS"), Tab(text: "LIVES")],
            ),

            const SizedBox(height: 10),

            // --- GRIDS ---
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildChipsTab(),
                  _buildCoinsTab(),
                  _buildLivesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processPurchase(StoreItem item) async {
    setState(() => isLoading = true);
    bool success = false;

    if (item.type == ItemType.coinPack) {
      // SIMULATE REAL MONEY PAYMENT DELAY
      await Future.delayed(const Duration(seconds: 1));
      // In real app, check Stripe/GooglePay result here. We assume success:
      success = await _onlineService.purchaseItem(item.id, 'coinPack', item.rewardAmount);
    }
    else if (item.type == ItemType.lifeRefill) {
      if (item.realMoneyPrice > 0) {
        // Real money life refill
        await Future.delayed(const Duration(seconds: 1));
        success = await _onlineService.purchaseItem(item.id, 'lifeRefill', 0);
      } else {
        // Coin purchase life refill
        success = await _onlineService.purchaseItem(item.id, 'lifeRefill', item.coinPrice);
      }
    }

    setState(() => isLoading = false);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Purchased ${item.name}!"), backgroundColor: Colors.green));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Purchase Failed (Not enough coins?)"), backgroundColor: Colors.red));
      }
    }
  }

  // --- TAB 1: CHIPS GRID ---
  Widget _buildChipsTab() {
    if (isLoading) return const Center(child: CircularProgressIndicator());

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.8, // Taller tiles
        crossAxisSpacing: 15,
        mainAxisSpacing: 15,
      ),
      itemCount: allGameChips.length,
      itemBuilder: (context, index) {
        final chip = allGameChips[index];
        final isOwned = ownedChipIds.contains(chip.id);

        return Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: isOwned ? Colors.green.withOpacity(0.5) : Colors.white10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Rotating Icon
              Expanded(
                child: Center(
                  child: RotateWidget(
                    child: Container(
                      height: 70, width: 70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: chip.color,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [BoxShadow(color: chip.color.withOpacity(0.6), blurRadius: 15, spreadRadius: 2)],
                      ),
                      child: Icon(chip.icon, color: Colors.white, size: 35),
                    ),
                  ),
                ),
              ),

              Text(chip.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 10),

              // Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: SizedBox(
                  width: double.infinity,
                  child: isOwned
                      ? const Center(child: Icon(Icons.check_circle, color: Colors.green, size: 30))
                      : ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                    ),
                    onPressed: () => _buyChip(chip),
                    child: Text("${chip.price}", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCoinsTab() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, childAspectRatio: 0.85, crossAxisSpacing: 15, mainAxisSpacing: 15
      ),
      itemCount: coinItems.length,
      itemBuilder: (context, index) {
        final item = coinItems[index];
        return _buildStoreTile(item);
      },
    );
  }

  Widget _buildLivesTab() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, childAspectRatio: 0.85, crossAxisSpacing: 15, mainAxisSpacing: 15
      ),
      itemCount: lifeItems.length,
      itemBuilder: (context, index) {
        final item = lifeItems[index];
        return _buildStoreTile(item);
      },
    );
  }

  Widget _buildStoreTile(StoreItem item) {
    String priceLabel = item.realMoneyPrice > 0 ? "\$${item.realMoneyPrice}" : "${item.coinPrice} Coins";

    return Container(
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white10)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(child: Center(child: PulseWidget(child: Icon(item.icon, size: 60, color: item.color)))),
          Text(item.description, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          Text(item.name, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                onPressed: () => _processPurchase(item),
                child: Text(priceLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- ANIMATIONS (Copied here so Store is self-contained) ---

class RotateWidget extends StatefulWidget { final Widget child; const RotateWidget({required this.child, super.key}); @override State<RotateWidget> createState() => _RotateWidgetState(); }
class _RotateWidgetState extends State<RotateWidget> with SingleTickerProviderStateMixin { late AnimationController _c; @override void initState() { super.initState(); _c = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat(); } @override void dispose() {_c.dispose(); super.dispose();} @override Widget build(BuildContext context) { return RotationTransition(turns: _c, child: widget.child); } }

class PulseWidget extends StatefulWidget { final Widget child; const PulseWidget({required this.child, super.key}); @override State<PulseWidget> createState() => _PulseWidgetState(); }
class _PulseWidgetState extends State<PulseWidget> with SingleTickerProviderStateMixin { late AnimationController _c; @override void initState() { super.initState(); _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true); } @override void dispose() {_c.dispose(); super.dispose();} @override Widget build(BuildContext context) { return FadeTransition(opacity: Tween(begin: 0.6, end: 1.0).animate(_c), child: widget.child); } }