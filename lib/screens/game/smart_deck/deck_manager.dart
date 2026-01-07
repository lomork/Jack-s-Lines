import 'dart:math';

class DeckManager {
  final int playerCount;
  final String difficulty;

  // Instance-level deck for the running game
  List<String> _currentDeck = [];
  final Random _random = Random();

  DeckManager({
    this.playerCount = 2,
    this.difficulty = "Easy",
  }) {
    _initializeDeck();
  }

  void _initializeDeck() {
    _currentDeck = createFullDeck();
    _currentDeck.shuffle();
  }

  // --- Static Helpers (Used by OnlineService) ---

  /// Creates a raw, ordered double deck (104 cards)
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

  /// Returns a NEW shuffled deck (Used by OnlineService to init game state)
  static List<String> getShuffledDeck() {
    List<String> deck = createFullDeck();
    deck.shuffle();
    return deck;
  }

  // --- Instance Methods (Used by GameBoard) ---

  /// Draws a single card from the deck. Returns null if empty.
  String? drawCard() {
    if (_currentDeck.isEmpty) {
      return null;
    }
    return _currentDeck.removeLast();
  }

  /// Recycles a dead card back into the deck (shuffles it in).
  void recycleDeadCard(String deadCard) {
    if (_currentDeck.isEmpty) {
      _currentDeck.add(deadCard);
    } else {
      // Insert at random position to simulate shuffling back in
      _currentDeck.insert(_random.nextInt(_currentDeck.length), deadCard);
    }
  }

  // --- SMART DRAW (Optional: For adjusting difficulty) ---
  static String drawSmartCard(List<String> currentDeck, List<int> boardState, List<String> boardLayout, String difficulty, int playerValue) {
    if (currentDeck.isEmpty) return "BACK";
    return currentDeck.removeLast();
  }
}