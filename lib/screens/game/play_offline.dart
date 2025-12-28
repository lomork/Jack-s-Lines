import 'dart:async';
import 'play_mode_handler.dart';

class PlayOfflineHandler implements PlayModeHandler {
  final String difficulty;
  final Function(int, String) onAiMove;

  PlayOfflineHandler({required this.difficulty, required this.onAiMove});

  @override
  void onMoveMade(int index, String card, int playerValue) {
    PlayModeHandler.triggerVibration();
    // Simulate AI thinking
    Future.delayed(const Duration(seconds: 2), () {
      onAiMove(0, "MockCard"); // Real logic would be here
    });
  }

  @override
  void onCardBurned(String card) {
    PlayModeHandler.triggerVibration();
  }

  @override
  void onGameEnd(bool won, String opponentName) {}

  @override
  void dispose() {}
}