import 'dart:math';
import '../smart_deck/deck_manager.dart';

class AiMove {
  final int index;
  final bool isRemoval;
  final String cardUsed; // --- NEW: Track which card AI decided to use ---

  AiMove({required this.index, required this.cardUsed, this.isRemoval = false});
}

class AiLogic {

  static AiMove? findBestMove(
      List<String> aiHand,
      List<int> boardState,
      List<String> boardLayout,
      String difficulty,
      int aiPlayerId
      ) {
    bool isHard = difficulty == "Hard";
    bool isMedium = difficulty == "Medium";

    List<AiMove> possibleMoves = [];
    Set<int> cornerIndices = {0, 9, 90, 99};

    for (String card in aiHand) {
      // JACK LOGIC: Check Suits for Jack types
      bool isJack = card.contains('J');
      bool isRedJack = card.contains('H') || card.contains('D');
      bool isBlackJack = card.contains('C') || card.contains('S');

      for (int i = 0; i < 100; i++) {
        if (cornerIndices.contains(i)) continue;
        int owner = boardState[i];

        // PLACING LOGIC
        if (owner == 0) {
          bool canPlace = false;
          if (isJack && isBlackJack) {
            canPlace = true; // Black Jack: Anywhere empty
          } else if (!isJack && boardLayout[i] == card) {
            canPlace = true; // Matching card
          }

          if (canPlace) {
            possibleMoves.add(AiMove(index: i, cardUsed: card, isRemoval: false));
          }
        }

        // REMOVAL LOGIC
        else if (isJack && isRedJack && owner != 0 && owner != aiPlayerId) {
          // AI checks if this chip is part of a sequence before trying to remove
          // Note: GameBoard logic prevents sequence removal, but AI should be smart enough not to try.
          possibleMoves.add(AiMove(index: i, cardUsed: card, isRemoval: true));
        }
      }
    }

    if (possibleMoves.isEmpty) return null;

    AiMove? bestMove;
    double bestScore = -1000;

    for (var move in possibleMoves) {
      double score = 0;

      if (move.isRemoval) {
        score += 30; // Base removal value
        // --- NEW: Prioritize blocking player's building lines ---
        int oppNeighbors = _countNeighbors(move.index, boardState, (aiPlayerId == 1 ? 2 : 1));
        score += (oppNeighbors * 20); // Remove chips that are helping player
      } else {
        // Placing: Build your own line
        int neighbors = _countNeighbors(move.index, boardState, aiPlayerId);
        score += (neighbors * 15);

        // --- NEW: Actively Block Player ---
        int oppNeighbors = _countNeighbors(move.index, boardState, (aiPlayerId == 1 ? 2 : 1));
        if (oppNeighbors >= 3) {
          score += 100; // Strong desire to block player's near-complete line
        }

        // Wild card conservation
        if (move.cardUsed.contains('J')) {
          score -= 10; // Try to save Jacks unless they are very useful
        }
      }

      // Randomness based on difficulty
      if (!isHard) {
        score += Random().nextInt(isMedium ? 10 : 30);
      }

      if (score > bestScore) {
        bestScore = score;
        bestMove = move;
      }
    }

    return bestMove;
  }

  static int _countNeighbors(int index, List<int> board, int playerId) {
    int count = 0;
    List<int> offsets = [-1, 1, -10, 10, -11, 11, -9, 9];
    for (int offset in offsets) {
      int neighbor = index + offset;
      if (neighbor >= 0 && neighbor < 100) {
        // Check grid boundary for horizontal
        if ((offset.abs() == 1 || offset.abs() == 11 || offset.abs() == 9)) {
          int row = index ~/ 10;
          int nRow = neighbor ~/ 10;
          if ((row - nRow).abs() > 1) continue;
        }
        if (board[neighbor] == playerId) count++;
      }
    }
    return count;
  }
}