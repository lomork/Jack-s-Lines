import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../screens/store/data/chip_data.dart';
import '../account/data/avatar_data.dart';
import 'avatar_selector.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> with TickerProviderStateMixin {
  // User Data State
  String displayName = "";
  String uniqueHandle = "";
  String bio = "No status set.";
  String _avatarId = "avatar_1";

  static const String chipKey = 'selected_chip_id';
  static const String avatarKey = 'selected_avatar_id';

  String selectedChipId = "default_blue";
  List<String> ownedChipIds = ["default_blue"];
  String selectedCountry = "Canada";
  String selectedFlag = "🇨🇦";
  String selectedTheme = "default";

  int currentLevel = 1;
  int currentXp = 0;
  int totalWins = 0;
  int totalLosses = 0;
  int totalCoins = 0;
  int totalMatches = 0;
  int currentStreak = 0;
  int globalRank = 999;

  int redJackRemovals = 0;
  int doubleThreatWins = 0;

  // Real Match History
  List<Map<dynamic, dynamic>> matchHistory = [];

  late AnimationController _rotateController;
  late AnimationController _chipRotateController;
  late AnimationController _pulseController;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  StreamSubscription? _userDataSubscription;
  StreamSubscription? _matchHistorySubscription;

  @override
  void initState() {
    super.initState();
    _rotateController = AnimationController(vsync: this, duration: const Duration(seconds: 15))..repeat();
    _chipRotateController = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _loadLocalData();
    _setupRealtimeListener();
    _setupMatchHistoryListener();
  }

  @override
  void dispose() {
    _userDataSubscription?.cancel();
    _matchHistorySubscription?.cancel();
    _rotateController.dispose();
    _chipRotateController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      selectedChipId = prefs.getString(chipKey) ?? "default_blue";
      ownedChipIds = prefs.getStringList('owned_chip_ids') ?? ["default_blue"];
      selectedTheme = prefs.getString('selected_theme') ?? "default";
      _avatarId = prefs.getString(avatarKey) ?? "avatar_1";
      totalLosses = prefs.getInt('total_losses') ?? 0;
      totalCoins = prefs.getInt('total_coins') ?? 0;
    });
  }

  void _setupRealtimeListener() {
    final user = _auth.currentUser;
    if (user == null) return;

    _userDataSubscription = _db.child('users').child(user.uid).onValue.listen((event) async {
      final data = event.snapshot.value as Map?;
      if (data == null) return;
      if (!mounted) return;

      final prefs = await SharedPreferences.getInstance();

      setState(() {
        displayName = data['handle'] ?? "Player";
        uniqueHandle = data['handle'] ?? "";
        bio = data['bio'] ?? "No status set.";

        if (data[avatarKey] != null) _avatarId = data[avatarKey];
        if (data[chipKey] != null) selectedChipId = data[chipKey];

        selectedCountry = data['country'] ?? "Canada";
        selectedFlag = data['flag'] ?? "🇨🇦";
        totalWins = data['total_wins'] ?? 0;
        totalLosses = data['total_losses'] ?? 0;
        totalCoins = data['total_coins'] ?? 0;
        totalMatches = data['total_matches'] ?? 0;
        currentStreak = data['current_streak'] ?? 0;
        currentXp = data['xp'] ?? 0;
        redJackRemovals = data['red_jack_removals'] ?? 0;
        doubleThreatWins = data['double_threat_wins'] ?? 0;
        globalRank = data['rank'] ?? 999;

        currentLevel = (currentXp / 100).floor() + 1;

        if (data['owned_chips'] != null) {
          ownedChipIds = List<String>.from(data['owned_chips']);
        }
      });

      await prefs.setString(chipKey, selectedChipId);
      await prefs.setString(avatarKey, _avatarId);
      await prefs.setInt('total_losses', totalLosses);
      await prefs.setInt('total_coins', totalCoins);
    });
  }

  void _setupMatchHistoryListener() {
    final user = _auth.currentUser;
    if (user == null) return;

    // RULE 1: Strict Paths
    _matchHistorySubscription = _db.child('users').child(user.uid).child('matches').onValue.listen((event) {
      if (!mounted) return;
      final data = event.snapshot.value as Map?;
      if (data != null) {
        final List<Map<dynamic, dynamic>> temp = [];
        data.forEach((key, value) {
          temp.add(value as Map);
        });
        // Sort by timestamp descending
        temp.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
        setState(() => matchHistory = temp);
      }
    });
  }

  Future<void> _updateField(String field, dynamic value) async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _db.child('users').child(user.uid).update({field: value});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Sync Error: $e")));
    }
  }

  Color _getThemeColor() {
    switch (selectedTheme) {
      case 'carbon': return const Color(0xFF1A1A1A);
      case 'neon': return const Color(0xFF000B18);
      case 'velvet': return const Color(0xFF2A0000);
      default: return const Color(0xFF121212);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _getThemeColor(),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              background: _buildHeaderBackground(),
            ),
            actions: [
              IconButton(icon: const Icon(Icons.share, color: Colors.white), onPressed: _shareProfile),
              IconButton(icon: const Icon(Icons.palette, color: Colors.white), onPressed: _showThemePicker),
              IconButton(icon: const Icon(Icons.edit, color: Colors.white), onPressed: _editNameDialog),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _buildStatGrid(),
                  const SizedBox(height: 32),
                  _buildSectionTitle("IDENTITY"),
                  _buildIdentityCard(),
                  const SizedBox(height: 32),
                  _buildSectionTitle("ACHIEVEMENTS"),
                  _buildAchievementList(),
                  const SizedBox(height: 32),
                  _buildSectionTitle("CHIP COLLECTION"),
                  const SizedBox(height: 8),
                  _buildChipCollection(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildHeaderBackground() {
    AvatarItem avatar = getAvatarById(_avatarId);
    double progress = (currentXp % 100) / 100.0;

    return Stack(
      alignment: Alignment.center,
      children: [
        if (selectedTheme == 'neon')
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) => Container(
              width: 320, height: 320,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Colors.cyanAccent.withOpacity(0.05 * _pulseController.value), Colors.transparent],
                  )
              ),
            ),
          ),

        RotationTransition(
          turns: _rotateController,
          child: Container(
            width: 210, height: 210,
            decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(colors: [Colors.blue, Colors.purple, Colors.blue])
            ),
          ),
        ),

        SizedBox(
          width: 170, height: 170,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 6,
            backgroundColor: Colors.white10,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
          ),
        ),

        GestureDetector(
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const AvatarSelectorScreen()));
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (currentStreak >= 5)
                const Icon(Icons.local_fire_department, size: 165, color: Colors.orangeAccent),
              if (currentLevel >= 10)
                const Icon(Icons.shield, size: 165, color: Colors.amberAccent),

              CircleAvatar(
                radius: 75,
                backgroundColor: avatar.color,
                child: Icon(avatar.icon, size: 85, color: Colors.white),
              ),
              Positioned(
                bottom: 5, right: 5,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle),
                  child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                ),
              ),
            ],
          ),
        ),

        Positioned(
          bottom: 35,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.amber, width: 1)),
            child: Text("LVL $currentLevel", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 12)),
          ),
        )
      ],
    );
  }

  Widget _buildStatGrid() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildStatItem("WINS", totalWins.toString(), Colors.greenAccent, onTap: _showMatchHistory),
        _buildStatItem("LOSSES", totalLosses.toString(), Colors.redAccent, icon: Icons.close, onTap: _showMatchHistory),
        _buildStatItem("STREAK", currentStreak.toString(), Colors.orangeAccent),
        _buildStatItem("COINS", totalCoins.toString(), Colors.amber),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, Color color, {VoidCallback? onTap, IconData? icon}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) Icon(icon, color: color, size: 14),
              const SizedBox(width: 2),
              Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(title, style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, letterSpacing: 2.0, fontSize: 11)),
      ),
    );
  }

  Widget _buildIdentityCard() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: const Icon(Icons.alternate_email, color: Colors.white54, size: 20),
            title: const Text("Handle", style: TextStyle(color: Colors.grey, fontSize: 13)),
            trailing: Text("@$uniqueHandle", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: const Icon(Icons.chat_bubble_outline, color: Colors.white54, size: 20),
            title: const Text("Status", style: TextStyle(color: Colors.grey, fontSize: 13)),
            subtitle: Text(bio, style: const TextStyle(color: Colors.white70, fontSize: 11)),
            trailing: const Icon(Icons.edit, size: 14, color: Colors.white24),
            onTap: _editBioDialog,
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: const Icon(Icons.public, color: Colors.white54, size: 20),
            title: const Text("Region", style: TextStyle(color: Colors.grey, fontSize: 13)),
            trailing: Text("$selectedFlag $selectedCountry", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onTap: _showCountryPicker,
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementList() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildBadge("The Remover", Icons.gavel, redJackRemovals >= 50, "Removed 50 chips"),
          _buildBadge("Double Threat", Icons.bolt, doubleThreatWins >= 10, "Won with 2 lines"),
          _buildBadge("Centurion", Icons.military_tech, totalMatches >= 100, "Played 100 matches"),
        ],
      ),
    );
  }

  Widget _buildBadge(String name, IconData icon, bool unlocked, String desc) {
    return Tooltip(
      message: desc,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: unlocked ? Colors.blueAccent.withOpacity(0.2) : Colors.white10,
              border: Border.all(color: unlocked ? Colors.blueAccent : Colors.transparent),
            ),
            child: Icon(icon, color: unlocked ? Colors.blueAccent : Colors.white24, size: 24),
          ),
          const SizedBox(height: 6),
          Text(name, style: TextStyle(color: unlocked ? Colors.white : Colors.white24, fontSize: 9, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildChipCollection() {
    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: ownedChipIds.length,
        itemBuilder: (context, index) {
          GameChip chip = allGameChips.firstWhere((c) => c.id == ownedChipIds[index], orElse: () => allGameChips[0]);
          bool isSelected = chip.id == selectedChipId;

          return GestureDetector(
            onTap: () => _selectChip(chip.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 95,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: isSelected ? Colors.amber.withOpacity(0.08) : Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: isSelected ? Colors.amber : Colors.white10,
                    width: isSelected ? 2 : 1
                ),
                boxShadow: isSelected ? [BoxShadow(color: Colors.amber.withOpacity(0.2), blurRadius: 10)] : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  isSelected
                      ? RotationTransition(
                    turns: _chipRotateController,
                    child: _buildChipIcon(chip),
                  )
                      : _buildChipIcon(chip),
                  const SizedBox(height: 8),
                  Text(
                      chip.name.toUpperCase(),
                      style: TextStyle(
                          color: isSelected ? Colors.amber : Colors.white54,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5
                      ),
                      overflow: TextOverflow.ellipsis
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChipIcon(GameChip chip) {
    return Container(
      width: 45, height: 45,
      decoration: BoxDecoration(
          color: chip.color,
          shape: BoxShape.circle,
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(2, 2))]
      ),
      child: Icon(chip.icon, color: Colors.white, size: 24),
    );
  }

  void _shareProfile() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Profile link copied to clipboard!"), backgroundColor: Colors.blueAccent),
    );
  }

  void _showMatchHistory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              const Text("MATCH HISTORY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.5)),
              const SizedBox(height: 20),
              if (matchHistory.isEmpty)
                const Expanded(child: Center(child: Text("No matches played yet.", style: TextStyle(color: Colors.white24))))
              else
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    itemCount: matchHistory.length,
                    separatorBuilder: (context, index) => const Divider(color: Colors.white10),
                    itemBuilder: (context, index) {
                      final match = matchHistory[index];
                      bool won = match['result'] == 'win';
                      String mode = match['mode'] ?? 'Online';
                      int xp = match['xp_gain'] ?? 0;
                      int ts = match['timestamp'] ?? 0;
                      String timeStr = ts > 0 ? DateTime.fromMillisecondsSinceEpoch(ts).toString().substring(5, 16) : "Just now";

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                            backgroundColor: won ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                            child: Icon(won ? Icons.emoji_events : Icons.close, color: won ? Colors.green : Colors.red, size: 20)
                        ),
                        title: Text(won ? "Victory" : "Defeat", style: const TextStyle(color: Colors.white, fontSize: 14)),
                        subtitle: Text(mode, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(won ? "+$xp XP" : "-$xp XP", style: TextStyle(color: won ? Colors.greenAccent : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                            Text(timeStr, style: const TextStyle(color: Colors.white24, fontSize: 10)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showThemePicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: const Text("BACKGROUND THEMES", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _themeTile("default", "Standard Dark", Colors.grey),
            _themeTile("carbon", "Carbon Fiber", Colors.blueGrey),
            _themeTile("neon", "Neon Grid", Colors.cyanAccent),
            _themeTile("velvet", "Velvet Red", Colors.redAccent),
          ],
        ),
      ),
    );
  }

  Widget _themeTile(String id, String name, Color color) {
    return ListTile(
      leading: CircleAvatar(backgroundColor: color, radius: 8),
      title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 14)),
      onTap: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('selected_theme', id);
        setState(() => selectedTheme = id);
        Navigator.pop(context);
      },
    );
  }

  Future<void> _selectChip(String chipId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(chipKey, chipId);
    if (mounted) setState(() => selectedChipId = chipId);
    _updateField(chipKey, chipId);
    HapticFeedback.mediumImpact();
  }

  void _showCountryPicker() {
    final Map<String, String> countries = {"USA": "🇺🇸", "Canada": "🇨🇦", "UK": "🇬🇧", "Germany": "🇩🇪", "France": "🇫🇷", "Japan": "🇯🇵"};
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: const Text("Select Region", style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: countries.length,
            itemBuilder: (context, index) {
              String name = countries.keys.elementAt(index);
              String flag = countries.values.elementAt(index);
              return ListTile(
                leading: Text(flag, style: const TextStyle(fontSize: 24)),
                title: Text(name, style: const TextStyle(color: Colors.white)),
                onTap: () {
                  _updateField('country', name);
                  _updateField('flag', flag);
                  Navigator.pop(context);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _editNameDialog() {
    TextEditingController controller = TextEditingController(text: displayName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: const Text("Change Handle", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Enter new name",
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _updateField('handle', controller.text);
              Navigator.pop(context);
            },
            child: const Text("Save", style: TextStyle(color: Colors.blueAccent)),
          )
        ],
      ),
    );
  }

  void _editBioDialog() {
    TextEditingController controller = TextEditingController(text: bio);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: const Text("Update Status", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          maxLines: 2,
          maxLength: 60,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "What's on your mind?",
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _updateField('bio', controller.text);
              Navigator.pop(context);
            },
            child: const Text("Update", style: TextStyle(color: Colors.blueAccent)),
          )
        ],
      ),
    );
  }
}