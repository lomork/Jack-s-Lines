import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../store/data/chip_data.dart';
import '../game/game_board.dart';
import '../options/options_screen.dart';
import '../account/account_screen.dart';
import '../store/store_screen.dart';
import '../friends/friends_screen.dart';
import '../account/data/avatar_data.dart';
import '../account/avatar_selector.dart'; 

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
  GameChip selectedChip = allGameChips[0];

  // NEW VARIABLES
  String _avatarId = "avatar_1";
  int _streak = 0;
  int _lives = 5;
  String _username = "Player";

  late AnimationController _rotateController;

  @override
  void initState() {
    super.initState();
    _rotateController = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
    _loadUserData();
    _listenForUpdates();
  }

  @override
  void dispose() {
    _rotateController.dispose();
    super.dispose();
  }

  void _listenForUpdates() {
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if(!mounted) {
        timer.cancel();
        return;
      }
      _loadUserData();
    });
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();

    // Fetch latest from Firebase
    String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final dbRef = FirebaseDatabase.instance.ref('users/$uid');
      final snapshot = await dbRef.get();
      if (snapshot.exists) {
        final data = snapshot.value as Map;
        await prefs.setInt('streak', data['streak'] ?? 0);
        await prefs.setInt('lives', data['lives'] ?? 5);
        if (data['avatar_id'] != null) {
          await prefs.setString('selected_avatar_id', data['avatar_id']);
        }
        if (data['selected_chip_id'] != null) {
          await prefs.setString('selected_chip_id', data['selected_chip_id']);
        }
      }
    }

    if (mounted) {
      setState(() {
        userCoins = prefs.getInt('user_coins') ?? 1000;
        selectedChipId = prefs.getString('selected_chip_id') ?? "default_blue";
        selectedChip = allGameChips.firstWhere((c) => c.id == selectedChipId, orElse: () => allGameChips[0]);
        _avatarId = prefs.getString('selected_avatar_id') ?? "avatar_1";
        _streak = prefs.getInt('streak') ?? 0;
        _lives = prefs.getInt('lives') ?? 5;
        _username = prefs.getString('unique_handle') ?? "Player";
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
    AvatarItem currentAvatar = allAvatars.firstWhere((a) => a.id == _avatarId, orElse: () => allAvatars[0]);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // --- NEW LAYOUT: COINS/LIVES | AVATAR | STREAK ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // LEFT COLUMN: COINS & LIVES
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TopStatBox(
                        color: const Color(0xFFFFD700),
                        text: "$userCoins",
                        iconWidget: PulseWidget(child: const Icon(Icons.circle, color: Color(0xFFFFD700), size: 20))
                    ),
                    const SizedBox(height: 8),
                    TopStatBox(
                        color: Colors.pinkAccent,
                        text: "$_lives",
                        iconWidget: const Icon(Icons.favorite, color: Colors.pinkAccent, size: 20)
                    ),
                  ],
                ),

                // CENTER COLUMN: AVATAR & USERNAME
                GestureDetector(
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const AvatarSelectorScreen()));
                  },
                  child: Column(
                    children: [
                      StreakFireEffect(
                        isEnabled: _streak >= 3,
                        child: CircleAvatar(
                          radius: 35, // Smaller size (was 50)
                          backgroundColor: Colors.white10,
                          child: CircleAvatar(
                            radius: 32,
                            backgroundColor: currentAvatar.color,
                            child: Icon(currentAvatar.icon, size: 30, color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _username,
                        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      const Text(
                        "EDIT",
                        style: TextStyle(color: Colors.grey, fontSize: 9),
                      ),
                    ],
                  ),
                ),

                // RIGHT COLUMN: STREAK
                Column(
                  children: [
                    TopStatBox(
                        color: Colors.redAccent,
                        text: "Streak: $_streak",
                        iconWidget: const BeatWidget(child: Icon(Icons.whatshot, color: Colors.redAccent, size: 20))
                    ),
                    // Spacer to align visually with the top of the left column if needed
                    const SizedBox(height: 40),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 30),

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

            const SizedBox(height: 50),

            // BUTTONS
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(child: BigGameButton(title: "Play Friends", icon: Icons.group_add, color: Colors.blueAccent, onTap: () {})),
                const SizedBox(width: 20),
                Expanded(child: BigGameButton(title: "Play Online", icon: Icons.public, color: Colors.green, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const GameBoard(isOnline: true))))),
              ],
            ),

            // OFFLINE BUTTON (Smaller Height)
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: BigGameButton(
                title: "Play Offline",
                icon: Icons.wifi_off,
                color: Colors.purpleAccent,
                onTap: _showDifficultyDialog,
                height: 100, // Reduced Height
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// --- WIDGET 1: TITLE ANIMATOR ---
class JacksLinesTitleAnimator extends StatefulWidget {
  const JacksLinesTitleAnimator({super.key});

  @override
  State<JacksLinesTitleAnimator> createState() => _JacksLinesTitleAnimatorState();
}
class _JacksLinesTitleAnimatorState extends State<JacksLinesTitleAnimator> with SingleTickerProviderStateMixin {
  late ConfettiController _confettiController;
  double _lineWidth = 0.0;
  bool _showChip = false;
  Color _glowColor = Colors.transparent;
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
    _loopTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if(mounted) _playRandomScenario();
    });
  }

  Future<void> _playRandomScenario() async {
    bool isWin = Random().nextBool();
    setState(() {
      _lineWidth = 0.0;
      _showChip = false;
      _glowColor = Colors.transparent;
    });

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    if (isWin) {
      setState(() => _lineWidth = 300.0);
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      setState(() => _glowColor = Colors.green.withOpacity(0.8));
      _confettiController.play();

    } else {
      setState(() => _lineWidth = 140.0);
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      setState(() {
        _showChip = true;
        _glowColor = Colors.red.withOpacity(0.8);
      });
    }

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
      height: 100,
      width: 300,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ConfettiWidget(
            confettiController: _confettiController,
            blastDirectionality: BlastDirectionality.explosive,
            shouldLoop: false,
            colors: const [Colors.green, Colors.blue, Colors.pink, Colors.orange, Colors.purple],
          ),
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
          const Text(
            "JACK'S LINES",
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.bold,
              color: Color(0xFFFFD700),
              letterSpacing: 2.0,
            ),
          ),
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
          if (_showChip)
            const Positioned(
              child: Icon(Icons.do_not_disturb_on, color: Colors.red, size: 50),
            ),
        ],
      ),
    );
  }
}

// --- ANIMATION HELPERS ---
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
    return FadeTransition(opacity: Tween(begin: 0.6, end: 1.0).animate(_controller), child: widget.child);
  }
}

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
  const TopStatBox({required this.iconWidget, required this.text, required this.color, super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          iconWidget,
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
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
  final double height;

  const BigGameButton({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
    this.height = 150,
    super.key
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color, width: 2),
          boxShadow: [BoxShadow(color: color.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 5))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 8),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// --- STREAK FLAIR EFFECT ---
class StreakFireEffect extends StatefulWidget {
  final Widget child;
  final bool isEnabled;
  const StreakFireEffect({required this.child, this.isEnabled = false, super.key});

  @override
  State<StreakFireEffect> createState() => _StreakFireEffectState();
}
class _StreakFireEffectState extends State<StreakFireEffect> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (!widget.isEnabled) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: Colors.orangeAccent.withOpacity(0.8), blurRadius: 10 + (_controller.value * 5), spreadRadius: 2),
              BoxShadow(color: Colors.red.withOpacity(0.6), blurRadius: 20 + (_controller.value * 10), spreadRadius: 5 + (_controller.value * 2)),
            ],
          ),
          child: widget.child,
        );
      },
    );
  }
}