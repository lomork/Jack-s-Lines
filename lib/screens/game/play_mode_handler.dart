import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/services.dart';

/// Base interface for different game modes (Online, Offline, Friends).
/// This keeps the [GameBoard] clean of mode-specific logic.
abstract class PlayModeHandler {
  void onMoveMade(int index, String card, int playerValue);
  void onCardBurned(String card);
  void onGameEnd(bool won, String opponentName);
  void dispose();

  // Helper for vibration - used by all modes
  static void triggerVibration() {
    HapticFeedback.mediumImpact();
  }
}