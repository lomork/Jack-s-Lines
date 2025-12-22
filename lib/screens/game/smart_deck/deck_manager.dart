import 'dart:math';

class DeckManager {

  // Create a standard double deck (104 cards)
  static List<String> createFullDeck() {
    List<String> suits = ['H', 'D', 'C', 'S']; // Hearts, Diamonds, Clubs, Spades
    List<String> ranks = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];

    List<String> deck = [];
    // Add two of every card
    for (int i = 0; i < 2; i++) {
      for (var suit in suits) {
        for (var rank in ranks) {
          deck.add('$rank$suit');
        }
      }
    }
    return deck;
  }

  // --- GAME RULES FOR JACKS ---

  // Two-Eyed Jacks are Wild (Clubs and Diamonds)
  static bool isTwoEyedJack(String card) {
    return card == "JC" || card == "JD";
  }

  // One-Eyed Jacks remove chips (Spades and Hearts)
  static bool isOneEyedJack(String card) {
    return card == "JS" || card == "JH";
  }

  // --- SMART DRAW (Optional: For adjusting difficulty) ---
  // If you want the game to give better cards when losing, use this.
  static String drawSmartCard(List<String> currentDeck, List<int> boardState, List<String> boardLayout, String difficulty, int playerValue) {
    if (currentDeck.isEmpty) return "BACK"; // Should not happen

    // For now, just return a random card to keep it fair
    // You can expand this later to pick a "Jack" if the player is losing badly
    return currentDeck.removeLast();
  }
}