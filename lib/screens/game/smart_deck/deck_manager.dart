import 'dart:math';

class DeckManager {
  // Builds a standard 2-deck set
  static List<String> buildDeck() {
    List<String> deck = [];
    List<String> suits = ["S", "C", "H", "D"];
    List<String> ranks = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"];

    for (int i = 0; i < 2; i++) {
      for (var s in suits) {
        for (var r in ranks) { deck.add("$r$s"); }
      }
    }
    deck.shuffle();
    return deck;
  }

  // Draw a card, but "peek" to ensure it's not a Dead Card (card for a full spot)
  // In Hard Mode, it tries to give a card near existing chips
  static String drawSmartCard(
      List<String> deck,
      List<int> boardState,
      List<String> boardLayout,
      String difficulty,
      int playerId // 1 for Player, 2 for AI
      ) {
    if (deck.isEmpty) return "BACK";

    // 1. Easy/Medium: Just ensure it's not dead (playable)
    // 2. Hard: Try to give a useful card

    // Simple implementation: Draw top card. If it's dead, bury it and draw again.
    // Try 3 times max to avoid infinite loops
    for (int attempt = 0; attempt < 3; attempt++) {
      String candidate = deck.last; // Peek

      if (_isCardPlayable(candidate, boardState, boardLayout)) {
        // In Hard mode, maybe check if it's "Good"?
        // For now, let's just return it to keep game flow smooth.
        return deck.removeLast();
      } else {
        // It's dead. Move to bottom of deck.
        deck.insert(0, deck.removeLast());
      }
    }

    // If all failed, just take the top one
    return deck.removeLast();
  }

  static bool _isCardPlayable(String card, List<int> boardState, List<String> boardLayout) {
    // Jacks are always playable
    if (card.startsWith("J")) return true;

    // Check if the two spots for this card are open
    for (int i = 0; i < 100; i++) {
      if (boardLayout[i] == card && boardState[i] == 0) {
        return true; // Found an open spot
      }
    }
    return false; // Both spots taken
  }
}