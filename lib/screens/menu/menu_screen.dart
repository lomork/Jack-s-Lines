import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../store/data/chip_data.dart';

import '../game/game_board.dart';
import '../options/options_screen.dart';
import '../account/account_screen.dart';
import '../store/store_screen.dart';
import '../friends/friends_screen.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  int _selectedIndex = 2;
  Widget _getCurrentScreen() {
    switch (_selectedIndex) {
      case 0: return const AccountScreen();
      case 1: return const FriendsScreen();
      case 2: return const HomeTab();
      case 3: return const StoreScreen();
      case 4: return const OptionsScreen();
      default: return const HomeTab();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: SafeArea(child: _getCurrentScreen()),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white10, width: 1)),
        ),
        child: BottomNavigationBar(
          items: <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: const Icon(Icons.person_outline),
              activeIcon: _buildGlowIcon(Icons.person),
              label: 'Account',
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.people_outlined),
              activeIcon: _buildGlowIcon(Icons.people),
              label: 'Friends',
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.home_outlined),
              activeIcon: _buildGlowIcon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.shopping_cart_outlined),
              activeIcon: _buildGlowIcon(Icons.shopping_cart),
              label: 'Store',
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.settings_outlined),
              activeIcon: _buildGlowIcon(Icons.settings),
              label: 'Options',
            ),
          ],
          currentIndex: _selectedIndex,
          selectedItemColor: const Color(0xFFFFD700),
          unselectedItemColor: Colors.grey,
          backgroundColor: const Color(0xFF252525),
          type: BottomNavigationBarType.fixed,
          onTap: (index) => setState(() => _selectedIndex = index),
          showUnselectedLabels: false,
        ),
      ),
    );
  }

  Widget _buildGlowIcon(IconData icon) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(color: const Color(0xFFFFD700).withOpacity(0.6), blurRadius: 15.0),
        ],
      ),
      child: Icon(icon, size: 30),
    );
  }
}

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with SingleTickerProviderStateMixin {
  int userCoins = 1000;
  String selectedChipId = "default_blue";
  late AnimationController _rotateController;

  @override
  void initState() {
    super.initState();
    // Setup rotation for the Big Chip
    _rotateController = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
    _loadUserData();
  }

  @override
  void dispose() {
    _rotateController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        userCoins = prefs.getInt('user_coins') ?? 1000;
        selectedChipId = prefs.getString('selected_chip_id') ?? "default_blue";
      });
    }
  }

  void _showDifficultyDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2C2C2C),
          title: const Text("Select Difficulty", style: TextStyle(color: Color(0xFFFFD700))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDiffButton("Easy", Colors.green, "Random moves"),
              const SizedBox(height: 10),
              _buildDiffButton("Medium", Colors.orange, "Thinking occasionally"),
              const SizedBox(height: 10),
              _buildDiffButton("Hard", Colors.red, "Strategic Master"),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDiffButton(String label, Color color, String sub) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.2),
          side: BorderSide(color: color),
          padding: const EdgeInsets.symmetric(vertical: 15),
        ),
        onPressed: () {
          Navigator.pop(context); // Close dialog
          // Go to Game Board with Difficulty
          Navigator.push(context, MaterialPageRoute(builder: (context) => GameBoard(difficulty: label)));
        },
        child: Column(
          children: [
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
            Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    GameChip currentChip = allGameChips.firstWhere((c) => c.id == selectedChipId, orElse: () => allGameChips[0]);

    // FIX: Added SingleChildScrollView to prevent overflow on small screens
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // STATS ROW
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TopStatBox(color: const Color(0xFFFFD700), text: "$userCoins", iconWidget: PulseWidget(child: Container(decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFFFFD700).withOpacity(0.6), blurRadius: 10, spreadRadius: 2)]), child: const Icon(Icons.circle, color: Color(0xFFFFD700), size: 24)))),
                TopStatBox(color: Colors.redAccent, text: "5/5", iconWidget: const BeatWidget(child: Icon(Icons.favorite, color: Colors.redAccent, size: 24))),
              ],
            ),

            const SizedBox(height: 40), // Spacer

            // ROTATING CHIP
            RotationTransition(
              turns: _rotateController,
              child: Container(
                height: 80, width: 80,
                decoration: BoxDecoration(shape: BoxShape.circle, color: currentChip.color, border: Border.all(color: Colors.white, width: 3), boxShadow: [BoxShadow(color: currentChip.color.withOpacity(0.8), blurRadius: 30, spreadRadius: 5)]),
                child: Icon(currentChip.icon, size: 40, color: Colors.white),
              ),
            ),
            const SizedBox(height: 20),

            const JacksLinesTitleAnimator(),

            const SizedBox(height: 60),

            // BUTTONS
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(child: BigGameButton(title: "Play Friends", icon: Icons.group_add, color: Colors.blueAccent, onTap: () {})),
                const SizedBox(width: 20),
                Expanded(child: BigGameButton(title: "Play Online", icon: Icons.public, color: Colors.green, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const GameBoard(isOnline: true))))),
              ],
            ),

            // OFFLINE BUTTON
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: BigGameButton(
                title: "Play Offline",
                icon: Icons.wifi_off,
                color: Colors.purpleAccent,
                onTap: _showDifficultyDialog,
              ),
            ),

            const SizedBox(height: 20), // Extra space at bottom for scrolling
          ],
        ),
      ),
    );
  }
}

// --- WIDGET 1: THE ANIMATED TITLE (The Complex Part) ---
class JacksLinesTitleAnimator extends StatefulWidget {
  const JacksLinesTitleAnimator({super.key});

  @override
  State<JacksLinesTitleAnimator> createState() => _JacksLinesTitleAnimatorState();
}
class _JacksLinesTitleAnimatorState extends State<JacksLinesTitleAnimator> with SingleTickerProviderStateMixin {
  late ConfettiController _confettiController;

  // Animation State Variables
  double _lineWidth = 0.0; // 0.0 to 300.0
  bool _showChip = false;
  Color _glowColor = Colors.transparent; // Changes to Green or Red

  Timer? _loopTimer;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 1));
    _startAnimationLoop();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _loopTimer?.cancel();
    super.dispose();
  }

  void _startAnimationLoop() {
    // Run an animation every 5 seconds
    _loopTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _playRandomScenario();
    });
  }

  Future<void> _playRandomScenario() async {
    // Randomly choose Win (true) or Block (false)
    bool isWin = Random().nextBool();

    // 1. Reset
    setState(() {
      _lineWidth = 0.0;
      _showChip = false;
      _glowColor = Colors.transparent;
    });

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    if (isWin) {
      // SCENARIO: WIN (Line crosses all the way)
      setState(() => _lineWidth = 300.0); // Full width

      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      setState(() => _glowColor = Colors.green.withOpacity(0.8));
      _confettiController.play();

    } else {
      // SCENARIO: BLOCK (Line stops halfway, Chip appears)
      setState(() => _lineWidth = 140.0); // Half width

      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;

      // Block!
      setState(() {
        _showChip = true;
        _glowColor = Colors.red.withOpacity(0.8);
      });
    }

    // Fade out after 2 seconds
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() {
      _glowColor = Colors.transparent;
      _lineWidth = 0.0;
      _showChip = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100, // Fixed height for animation area
      width: 300,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. Confetti Blaster (Behind everything)
          ConfettiWidget(
            confettiController: _confettiController,
            blastDirectionality: BlastDirectionality.explosive,
            shouldLoop: false,
            colors: const [Colors.green, Colors.blue, Colors.pink, Colors.orange, Colors.purple],
          ),

          // 2. The Glowing Backdrop
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            height: 80,
            width: 300,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: _glowColor, blurRadius: 40, spreadRadius: 5),
              ],
            ),
          ),

          // 3. The Text
          const Text(
            "JACK'S LINES",
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.bold,
              color: Color(0xFFFFD700),
              letterSpacing: 2.0,
            ),
          ),

          // 4. The "Line" (Animated Container)
          Positioned(
            left: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeInOut,
              height: 6,
              width: _lineWidth,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(3),
                boxShadow: const [BoxShadow(color: Colors.black45, offset: Offset(2,2))],
              ),
            ),
          ),

          // 5. The "Blocker Chip"
          if (_showChip)
            const Positioned(
              child: Icon(Icons.do_not_disturb_on, color: Colors.red, size: 50),
            ),
        ],
      ),
    );
  }
}

// --- WIDGET 2: PULSE ANIMATION (For Coin) ---
class PulseWidget extends StatefulWidget {
  final Widget child;
  const PulseWidget({required this.child, super.key});
  @override
  State<PulseWidget> createState() => _PulseWidgetState();
}
class _PulseWidgetState extends State<PulseWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.6, end: 1.0).animate(_controller),
      child: widget.child,
    );
  }
}

// --- WIDGET 3: BEAT ANIMATION (For Heart) ---
class BeatWidget extends StatefulWidget {
  final Widget child;
  const BeatWidget({required this.child, super.key});
  @override
  State<BeatWidget> createState() => _BeatWidgetState();
}
class _BeatWidgetState extends State<BeatWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(begin: 1.0, end: 1.15).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}

// --- UI HELPER WIDGETS ---
class TopStatBox extends StatelessWidget {
  final Widget iconWidget;
  final String text;
  final Color color;

  const TopStatBox({
    required this.iconWidget,
    required this.text,
    required this.color,
    super.key
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: color.withOpacity(0.5), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min, // Shrinks to fit content
        children: [
          iconWidget, // The animated icon goes here
          const SizedBox(width: 10),
          Text(
              text,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18
              )
          ),
        ],
      ),
    );
  }
}
class BigGameButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const BigGameButton({required this.title, required this.icon, required this.color, required this.onTap, super.key});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 150,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color, width: 2),
          boxShadow: [BoxShadow(color: color.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 5))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 50, color: color),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}