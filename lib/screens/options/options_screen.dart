import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Import the storage package

class OptionsScreen extends StatefulWidget {
  const OptionsScreen({super.key});

  @override
  State<OptionsScreen> createState() => _OptionsScreenState();
}

class _OptionsScreenState extends State<OptionsScreen> {
  // Default values (used if no save file is found)
  double _soundVolume = 50;
  double _musicVolume = 50;
  bool _vibrationsEnabled = true;
  bool _chatEnabled = true;

  bool _isLoading = true; // To prevent showing wrong values while loading

  @override
  void initState() {
    super.initState();
    _loadSettings(); // Load saved data when screen starts
  }

  // --- 1. LOAD SETTINGS FROM STORAGE ---
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // Try to get the value. If it doesn't exist, use the default (after ??)
      _soundVolume = prefs.getDouble('sound_volume') ?? 50.0;
      _musicVolume = prefs.getDouble('music_volume') ?? 50.0;
      _vibrationsEnabled = prefs.getBool('vibrations_enabled') ?? true;
      _chatEnabled = prefs.getBool('chat_enabled') ?? true;

      _isLoading = false; // Done loading
    });
  }

  // --- 2. SAVE SETTINGS TO STORAGE ---
  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is double) {
      await prefs.setDouble(key, value);
    } else if (value is bool) {
      await prefs.setBool(key, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700)));
    }

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text(
              "SETTINGS",
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFFD700),
                letterSpacing: 2.0,
              ),
            ),
          ),
          const SizedBox(height: 40),

          // --- AUDIO ---
          const Text("AUDIO", style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),

          _buildVolumeSlider("Sound FX", _soundVolume, (value) {
            setState(() => _soundVolume = value);
            _saveSetting('sound_volume', value); // Save immediately
          }),

          _buildVolumeSlider("Music", _musicVolume, (value) {
            setState(() => _musicVolume = value);
            _saveSetting('music_volume', value); // Save immediately
          }),

          const SizedBox(height: 30),

          // --- GAMEPLAY ---
          const Text("GAMEPLAY", style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),

          _buildSwitchTile("Vibrations", Icons.vibration, _vibrationsEnabled, (val) {
            setState(() => _vibrationsEnabled = val);
            _saveSetting('vibrations_enabled', val); // Save immediately
          }),

          _buildSwitchTile("Enable Chat", Icons.chat, _chatEnabled, (val) {
            setState(() => _chatEnabled = val);
            _saveSetting('chat_enabled', val); // Save immediately
          }),

          const Spacer(),

          // --- ACCOUNT BUTTONS ---
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white54),
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {},
              child: const Text("Sign Out", style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent.withOpacity(0.2),
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Colors.redAccent),
                ),
              ),
              onPressed: () {},
              child: const Text("Delete Account", style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildVolumeSlider(String label, double currentValue, Function(double) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 18)),
            Text("${currentValue.toInt()}%", style: const TextStyle(color: Colors.grey)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: const Color(0xFFFFD700),
            inactiveTrackColor: Colors.grey[800],
            thumbColor: const Color(0xFFFFD700),
            overlayColor: const Color(0xFFFFD700).withOpacity(0.2),
          ),
          child: Slider(
            value: currentValue,
            min: 0,
            max: 100,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchTile(String label, IconData icon, bool value, Function(bool) onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SwitchListTile(
        title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 16)),
        secondary: Icon(icon, color: Colors.white70),
        value: value,
        activeColor: const Color(0xFFFFD700),
        activeTrackColor: const Color(0xFFFFD700).withOpacity(0.4),
        inactiveThumbColor: Colors.grey,
        inactiveTrackColor: Colors.black45,
        onChanged: onChanged,
      ),
    );
  }
}