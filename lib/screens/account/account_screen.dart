import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../screens/store/data/chip_data.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> with SingleTickerProviderStateMixin{
  // User Data State
  String displayName = "Loading...";
  String uniqueHandle = "@loading";

  String selectedChipId = "default_blue";
  List<String> ownedChipIds = ["default_blue"];
  String selectedCountry = "Canada";
  String selectedFlag = "🇨🇦";

  int currentLevel = 1;
  int totalWins = 0;
  int totalCoins = 0;
  int totalMatches = 0;
  int currentStreak = 0;

  // Animation
  late AnimationController _rotateController;

  // Firebase
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  StreamSubscription? _userDataSubscription;

  @override
  void initState() {
    super.initState();
    _rotateController = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
    _setupRealtimeListener();
  }

  @override
  void dispose() {
    _rotateController.dispose();
    _userDataSubscription?.cancel(); // Stop listening when we leave
    super.dispose();
  }

  // --- THE NEW LOGIC: LISTEN TO FIREBASE ---
  void _setupRealtimeListener() {
    final User? user = _auth.currentUser;
    if (user == null) return; // Not logged in

    // Listen to changes at 'users/{uid}'
    _userDataSubscription = _db.child('users/${user.uid}').onValue.listen((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;

      if (data != null && mounted) {
        setState(() {
          // Update UI with Cloud Data
          displayName = data['handle'] ?? "Player"; // Using handle as display name for now
          uniqueHandle = data['unique_id'] ?? "#0000"; // Showing the unique ID

          totalCoins = data['coins'] ?? 0;
          totalWins = data['matches_won'] ?? 0;
          totalMatches = data['matches_played'] ?? 0;
          currentStreak = data['streak'] ?? 0;

          selectedChipId = data['selected_chip'] ?? "default_blue";

          if (data['owned_chips'] != null) {
            ownedChipIds = List<String>.from(data['owned_chips']);
          }

          if (data['country'] != null) selectedCountry = data['country'];
          if (data['flag'] != null) selectedFlag = data['flag'];

          // Calculate Level based on Wins (Example Logic)
          currentLevel = 1 + (totalWins ~/ 5); // Level up every 5 wins
        });
      }
    });
  }

  // --- ACTIONS (SAVE TO CLOUD) ---
  Future<void> _updateField(String key, dynamic value) async {
    final User? user = _auth.currentUser;
    if (user == null) return;
    await _db.child('users/${user.uid}').update({key: value});
  }

  Future<void> _selectChip(String id) async {
    setState(() => selectedChipId = id); // Instant local update
    await _updateField('selected_chip', id); // Save to cloud
  }

  // --- HELPER METHODS ---
  Color getRankColor() {
    if (currentLevel < 5) return Colors.brown; // Bronze
    if (currentLevel < 10) return Colors.grey; // Silver
    if (currentLevel < 20) return const Color(0xFFFFD700); // Gold
    return const Color(0xFF00FFFF); // Diamond
  }

  final Map<String, String> countries = { "Canada": "🇨🇦", "USA": "🇺🇸", "UK": "🇬🇧", "India": "🇮🇳", "Germany": "🇩🇪", "France": "🇫🇷", "Japan": "🇯🇵", "Brazil": "🇧🇷", "Australia": "🇦🇺" };
  final List<IconData> avatarOptions = [ Icons.face, Icons.face_3, Icons.face_6, Icons.sentiment_very_satisfied, Icons.pets, Icons.rocket_launch ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // HEADER PROFILE PIC
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                GestureDetector(
                  onTap: _showAvatarPicker,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: getRankColor(), width: 3),
                      boxShadow: [BoxShadow(color: getRankColor().withOpacity(0.4), blurRadius: 20)],
                    ),
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.white10,
                      child: const Icon(Icons.face, size: 60, color: Colors.white),
                    ),
                  ),
                ),
                Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle), child: const Icon(Icons.edit, color: Colors.white, size: 16)),
              ],
            ),
            const SizedBox(height: 15),

            // NAMES
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(displayName, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(width: 8),
                GestureDetector(onTap: _showCountryPicker, child: Text(selectedFlag, style: const TextStyle(fontSize: 20))),
                const SizedBox(width: 8),
                GestureDetector(
                    onTap: () => _editNameDialog(),
                    child: const Icon(Icons.edit, color: Colors.grey, size: 16)
                ),
              ],
            ),
            Text("ID: $uniqueHandle", style: const TextStyle(fontSize: 16, color: Colors.blueAccent)),

            // STATS GRID
            const SizedBox(height: 30),
            GridView.count(
              crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: 2.5, mainAxisSpacing: 10, crossAxisSpacing: 10,
              children: [
                _buildStatBox("Total Wins", "$totalWins", Icons.emoji_events, Colors.orange),
                _buildStatBox("Level", "$currentLevel", Icons.military_tech, getRankColor()),
                _buildStatBox("Streak", "$currentStreak", Icons.local_fire_department, Colors.redAccent),
                _buildStatBox("Coins", "$totalCoins", Icons.monetization_on, Colors.green),
              ],
            ),

            const SizedBox(height: 30),

            // SIGNATURE CHIP SELECTOR
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white10)),
              child: Column(
                children: [
                  const Text("Signature Chip Style", style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 15),
                  SizedBox(
                    height: 60,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: ownedChipIds.length,
                      itemBuilder: (context, index) {
                        String id = ownedChipIds[index];
                        GameChip chipData = allGameChips.firstWhere((c) => c.id == id, orElse: () => allGameChips[0]);
                        return _buildChipOption(chipData);
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // LOGOUT BUTTON
            TextButton(
                onPressed: () async {
                  await _auth.signOut();
                  // Note: You'll need to handle navigation back to LoginScreen in main.dart listener
                },
                child: const Text("Log Out", style: TextStyle(color: Colors.red))
            ),
          ],
        ),
      ),
    );
  }

  // --- WIDGET BUILDERS ---

  Widget _buildChipOption(GameChip chip) {
    bool isSelected = selectedChipId == chip.id;
    Widget chipVisual = Container(
      width: 40, height: 40, margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: chip.color, shape: BoxShape.circle, border: isSelected ? Border.all(color: Colors.white, width: 2) : null, boxShadow: [if(isSelected) BoxShadow(color: chip.color.withOpacity(0.8), blurRadius: 10, spreadRadius: 2)]),
      child: Icon(chip.icon, size: 20, color: isSelected ? Colors.white : Colors.white.withOpacity(0.5)),
    );
    return GestureDetector(onTap: () => _selectChip(chip.id), child: isSelected ? RotationTransition(turns: _rotateController, child: chipVisual) : chipVisual);
  }

  Widget _buildStatBox(String label, String value, IconData icon, Color color) {
    return Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF2C2C2C), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.05))), child: Row(children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle), child: Icon(icon, color: color, size: 20)), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)), Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12), overflow: TextOverflow.ellipsis)]))]));
  }

  void _showAvatarPicker() { showModalBottomSheet(context: context, backgroundColor: const Color(0xFF2C2C2C), builder: (context) { return SizedBox(height: 200, child: Column(children: [const SizedBox(height: 20), const Text("Choose Avatar", style: TextStyle(color: Colors.white, fontSize: 18)), const SizedBox(height: 20), Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: avatarOptions.map((icon) => IconButton(onPressed: () { Navigator.pop(context); }, icon: Icon(icon, color: Colors.white, size: 40))).toList())],),);},); }

  void _showCountryPicker() { showDialog(context: context, builder: (context) => AlertDialog(backgroundColor: const Color(0xFF2C2C2C), title: const Text("Select Country", style: TextStyle(color: Colors.white)), content: SizedBox(width: double.maxFinite, child: ListView.builder(shrinkWrap: true, itemCount: countries.length, itemBuilder: (context, index) { String name = countries.keys.elementAt(index); String flag = countries.values.elementAt(index); return ListTile(leading: Text(flag, style: const TextStyle(fontSize: 24)), title: Text(name, style: const TextStyle(color: Colors.white)), onTap: () { _updateField('country', name); _updateField('flag', flag); Navigator.pop(context); },); },),),),); }

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
          decoration: const InputDecoration(hintText: "Enter new name", hintStyle: TextStyle(color: Colors.grey), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blue))),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _updateField('handle', controller.text); // Save to cloud
              Navigator.pop(context);
            },
            child: const Text("Save", style: TextStyle(color: Colors.blueAccent)),
          )
        ],
      ),
    );
  }
}